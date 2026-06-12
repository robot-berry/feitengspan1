# SPAN 色彩通道与 PixelShuffle 验证记录（2026-06-11）

## 背景

用户反馈超分后图像色彩不对。检查输入 PNG、RGB raw、JTAG-to-AXI 写入、AXI-Lite 端点和 frame engine 输入通道后，普通 RGB/BGR 顺序未发现问题：

- `tools/convert_rgb_raw.py` 使用 PIL `RGB`，raw 字节顺序为 `R,G,B`。
- `scripts/jtag_rgb_transfer.tcl` 写入 `REG_INPUT_PIXEL` 的格式为 `{R,G,B}`，即 AXI word `{8'd0,R,G,B}`。
- `rtl/board/sr_sd_axi_lite_accel.v` 直接传递 `s_axi_wdata[23:0]`。
- `rtl/span/span_official_frame_engine.v` 输入读取为 `s_data[23:16]`、`s_data[15:8]`、`s_data[7:0]`。

## 根因

真正问题在 upsampler 输出到 PixelShuffle 的通道解释顺序。

官方 SPAN 使用 PyTorch `nn.PixelShuffle(scale)`。其通道布局为：

```text
input channel = color * scale * scale + subpixel
```

即先排列 R 的所有子像素，再排列 G 的所有子像素，再排列 B 的所有子像素。

修复前 RTL 与 Python 固定点参考都使用了：

```text
input channel = subpixel * 3 + color
```

这会导致参考和硬件“同错”，因此旧的逐字节比较仍然通过，但视觉颜色会不对。

## 修复内容

1. 修复 Python 固定点参考：
   - `tools/span_official_fixed_ref.py`
   - `pixelshuffle()` 改为 PyTorch PixelShuffle 通道顺序。

2. 修复 RTL frame engine：
   - `rtl/span/span_official_frame_engine.v`
   - `write_up_mem` 改为 `color = out_ch / UP_SUBPIXELS`，`sub = out_ch % UP_SUBPIXELS`。

3. 新增通用对比图工具：
   - `tools/make_sr_validation_preview.py`
   - 输出面板包括：Input、Reference、Actual、Diff。

4. 更新验证脚本，使每次测试都可以生成对比图：
   - `scripts/compare_jtag_full_span_output.ps1`：生成 board/reference/diff 对比图。
   - `scripts/compare_span_frame_engine_smoke.ps1`：生成 RTL/reference/diff 对比图。
   - `scripts/run_jtag_full_span_smoke.ps1`：硬件测试成功后自动调用比较脚本并生成对比图。

## 已完成验证

### 1. 旧 X4 8x8 板测输出反证

使用修复后的参考重新比较旧 bitstream 的 X4 `8x8 -> 32x32` 输出，出现 mismatch：

```text
JTAG full SPAN output mismatch count: 2660
```

该结果证明旧 bitstream 的输出通道顺序确实与 PyTorch PixelShuffle 不一致。

### 2. X4 RTL smoke

修复后运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compare_span_frame_engine_smoke.ps1 -ImgW 4
```

结果：

```text
PASS compare_span_frame_engine_smoke_x4_4x4: 768 bytes match
```

### 3. X2 RTL smoke

切换 X2 权重后运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compare_span_frame_engine_smoke.ps1 -ImgW 4
```

结果：

```text
PASS compare_span_frame_engine_smoke_x2_4x4: 192 bytes match
```

对比图：

```text
build/span_validation_preview_x2_4x4.png
```

### 4. X4 8x8 修复版 bitstream 与板测

已重新生成修复后的 X4 `IMG_W=8` bitstream：

```text
vivado/bitstreams/jfs_full_span_x4_8x8.bit
```

时序结果：

| 项目 | 数值 |
| --- | ---: |
| WNS | 14.511 ns |
| WHS | 0.016 ns |
| CLB LUTs | 6444 |
| CLB Registers | 3769 |
| Block RAM Tile | 184.5 |
| DSPs | 1 |

已完成一次修复版 X4 `8x8 -> 32x32` JTAG 板测，结果：

```text
Input counter : 64
Output counter: 1024
Error flags   : 0x00000000
PASS compare_jtag_full_span_output_x4_8x8: 3072 bytes match
```

对比图：

```text
board_runs/full_span_jtag_smoke/compare_x4_8x8_pixelshuffle_fixed/validation_preview_x4_8x8.png
```

### 5. X2 4x4 修复版 bitstream 与板测

已重新生成修复后的 X2 `IMG_W=4` bitstream：

```text
vivado/bitstreams/jfs_full_span_x2_4x4.bit
```

时序结果：

| 项目 | 数值 |
| --- | ---: |
| WNS | 12.909 ns |
| WHS | 0.017 ns |
| CLB LUTs | 5681 |
| CLB Registers | 3673 |
| Block RAM Tile | 178.5 |
| DSPs | 1 |

已完成修复版 X2 `4x4 -> 8x8` JTAG 板测，命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 4 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x2_4x4_pixelshuffle_fixed_out.png
```

结果：

```text
Input counter : 16
Output counter: 64
Error flags   : 0x00000000
Wrote board_runs\full_span_jtag_smoke\output_x2_4x4.rgb (192 bytes)
PASS compare_jtag_full_span_output_x2_4x4: 192 bytes match
```

输出图像：

```text
board_runs/full_span_jtag_smoke/baboon_x2_4x4_pixelshuffle_fixed_out.png
```

对比图：

```text
board_runs/full_span_jtag_smoke/compare_x2_4x4/validation_preview_x2_4x4.png
```

## 当前状态

- 色彩通道问题已定位并修复到 RTL 和固定点参考。
- 后续每次 RTL smoke 或 JTAG 输出比较都会生成对比图。
- 当前修复版 X2 4x4 和 X4 8x8 JTAG 上板验证均已通过并生成对比图。
- Git remote 当前为空，无法直接 push 到 GitHub；需要补充 GitHub 远端地址后才能按规模推送存档。
### 2026-06-11 PixelShuffle-fixed X4 4x4 board validation addendum

1. Regenerated the fixed X4 `IMG_W=4` JTAG full SPAN bitstream after correcting PixelShuffle channel order.
   - bitstream: `vivado/bitstreams/jfs_full_span_x4_4x4.bit`
   - timing report: `vivado/reports/jtag_full_span_x4_4x4_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x4_4x4_utilization_impl.rpt`
   - WNS: `14.733 ns`, WHS: `0.014 ns`; Vivado reports all user timing constraints met.
   - resources: CLB LUTs `5722`, CLB Registers `3686`, Block RAM Tile `184.5`, DSPs `1`.
2. Ran real PNG JTAG board validation with `external/SPAN/test_scripts/data/baboon.png` resized to `4x4`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 4 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x4_4x4_pixelshuffle_fixed_out.png`
   - input counter: `16`
   - output counter: `256`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x4_4x4.rgb` (`768 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x4_4x4_pixelshuffle_fixed_out.png`
3. Fixed-point reference comparison passed byte-for-byte.
   - result: `PASS compare_jtag_full_span_output_x4_4x4: 768 bytes match`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x4_4x4/validation_preview_x4_4x4.png`

Conclusion: after the PixelShuffle color-channel fix, X4 `4x4 -> 16x16` board output now matches the fixed-point reference byte-for-byte and produces the required Input / Reference / Board / Diff comparison image.

### 2026-06-11 PixelShuffle-fixed X2 8x8 board validation

1. Generated the fixed X2 `IMG_W=8` JTAG full SPAN bitstream.
   - bitstream: `vivado/bitstreams/jfs_full_span_x2_8x8.bit`
   - timing report: `vivado/reports/jtag_full_span_x2_8x8_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x2_8x8_utilization_impl.rpt`
   - WNS: `13.732 ns`, WHS: `0.012 ns`; Vivado reports all user timing constraints met.
   - resources: CLB LUTs `6448`, CLB Registers `3757`, Block RAM Tile `178.5`, DSPs `1`.
2. Ran real PNG JTAG board validation with the current official image `external/SPAN/test_scripts/data/baboon.png` resized to `8x8`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 8 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x2_8x8_pixelshuffle_fixed_out.png`
   - input counter: `64`
   - output counter: `256`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x2_8x8.rgb` (`768 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x2_8x8_pixelshuffle_fixed_out.png`
3. Fixed-point reference comparison passed byte-for-byte.
   - result: `PASS compare_jtag_full_span_output_x2_8x8: 768 bytes match`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x2_8x8/validation_preview_x2_8x8.png`

Conclusion: X2 `8x8 -> 16x16` board output matches the fixed-point reference byte-for-byte and the required Input / Reference / Board / Diff comparison image was generated.

### 2026-06-11 PixelShuffle-fixed X4 16x16 board validation

1. Generated the fixed X4 `IMG_W=16` JTAG full SPAN bitstream.
   - bitstream: `vivado/bitstreams/jfs_full_span_x4_16x16.bit`
   - timing report: `vivado/reports/jtag_full_span_x4_16x16_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x4_16x16_utilization_impl.rpt`
   - WNS: `14.159 ns`, WHS: `0.015 ns`; Vivado reports all user timing constraints met.
   - resources: CLB LUTs `6743`, CLB Registers `3847`, Block RAM Tile `202`, DSPs `1`.
2. Ran real PNG JTAG board validation with the current official image `external/SPAN/test_scripts/data/baboon.png` resized to `16x16`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 16 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x4_16x16_pixelshuffle_fixed_out.png`
   - input counter: `256`
   - output counter: `4096`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x4_16x16.rgb` (`12288 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x4_16x16_pixelshuffle_fixed_out.png`
3. Fixed-point reference comparison passed byte-for-byte.
   - result: `PASS compare_jtag_full_span_output_x4_16x16: 12288 bytes match`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x4_16x16/validation_preview_x4_16x16.png`

Conclusion: X4 `16x16 -> 64x64` board output matches the fixed-point reference byte-for-byte and the required Input / Reference / Board / Diff comparison image was generated.

### 2026-06-12 PixelShuffle-fixed X2 16x16 board validation

1. Generated the fixed X2 `IMG_W=16` JTAG full SPAN bitstream.
   - bitstream: `vivado/bitstreams/jfs_full_span_x2_16x16.bit`
   - timing report: `vivado/reports/jtag_full_span_x2_16x16_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x2_16x16_utilization_impl.rpt`
   - WNS: `13.150 ns`, WHS: `0.016 ns`; Vivado reports all user timing constraints met.
   - resources: CLB LUTs `6728`, CLB Registers `3837`, Block RAM Tile `194.5`, DSPs `1`.
2. Ran real PNG JTAG board validation with the current official image `external/SPAN/test_scripts/data/baboon.png` resized to `16x16`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 16 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x2_16x16_pixelshuffle_fixed_out.png`
   - input counter: `256`
   - output counter: `1024`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x2_16x16.rgb` (`3072 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x2_16x16_pixelshuffle_fixed_out.png`
3. Fixed-point reference comparison passed byte-for-byte.
   - result: `PASS compare_jtag_full_span_output_x2_16x16: 3072 bytes match`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x2_16x16/validation_preview_x2_16x16.png`

Conclusion: X2 `16x16 -> 32x32` board output matches the fixed-point reference byte-for-byte and the required Input / Reference / Board / Diff comparison image was generated.
