# 2026-06-11 完整 SPAN X2/X4 板级验证记录

本文记录本次在 FACE-ZUSSD 板卡上的 Vivado/JTAG 验证结果。当前验证目标是确认完整官方 SPAN RTL 能在 FPGA 上下载运行，并通过 USB-JTAG/JTAG-to-AXI 完成 RGB 小图输入、超分计算和输出读回。

## 1. JTAG 连接状态

Vivado Hardware Manager 已能枚举到板卡：

```text
HW_TARGETS
  [0] localhost:3121/xilinx_tcf/Digilent/210203367162A
HW_DEVICES
  [0] xczu19_0
  [1] arm_dap_1
JTAG_TARGET_FOUND=1
```

初始检测时当前板上旧设计没有 JTAG-to-AXI master，因此 `JTAG_AXI_FOUND=0` 是正常现象；下载本工程 JTAG full SPAN bitstream 后，JTAG-to-AXI 链路可用于 smoke 测试。

## 2. 已通过的板级 smoke

### X4 4x4

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 4
```

板级计数结果：

```text
Input counter : 16
Output counter: 256
Error flags   : 0x00000000
Wrote board_runs\full_span_jtag_smoke\output_x4_4x4.rgb (768 bytes)
```

同输入固定点参考比较：

```text
PASS board_x4_4x4_matches_same_input_ref bytes=768
```

输出文件：

- `board_runs/full_span_jtag_smoke/input_x4_4x4.rgb`
- `board_runs/full_span_jtag_smoke/output_x4_4x4.rgb`
- `board_runs/full_span_jtag_smoke/output_x4_4x4.ppm`
- `build/span_fixed_ref_jtag_x4_4x4.rgb`
- `build/span_fixed_ref_jtag_x4_4x4.png`

### X2 2x2

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 2
```

板级计数结果：

```text
Input counter : 4
Output counter: 16
Error flags   : 0x00000000
Wrote board_runs\full_span_jtag_smoke\output_x2_2x2.rgb (48 bytes)
```

同输入固定点参考比较：

```text
PASS board_x2_2x2_matches_same_input_ref bytes=48
```

### X2 4x4

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 4
```

板级计数结果：

```text
Input counter : 16
Output counter: 64
Error flags   : 0x00000000
Wrote board_runs\full_span_jtag_smoke\output_x2_4x4.rgb (192 bytes)
```

同输入固定点参考比较：

```text
PASS board_x2_4x4_matches_same_input_ref bytes=192
```

输出文件：

- `board_runs/full_span_jtag_smoke/input_x2_4x4.rgb`
- `board_runs/full_span_jtag_smoke/output_x2_4x4.rgb`
- `board_runs/full_span_jtag_smoke/output_x2_4x4.ppm`
- `build/span_fixed_ref_jtag_x2_4x4.rgb`
- `build/span_fixed_ref_jtag_x2_4x4.png`

## 3. Vivado 实现结果

### X4 4x4

文件：

- bitstream：`vivado/bitstreams/jfs_full_span_x4_4x4.bit`
- timing：`vivado/reports/jtag_full_span_x4_4x4_timing_impl.rpt`
- utilization：`vivado/reports/jtag_full_span_x4_4x4_utilization_impl.rpt`

关键结果：

| 项目 | 数值 |
| --- | ---: |
| WNS | 14.606 ns |
| WHS | 0.010 ns |
| CLB LUTs | 5717 |
| CLB Registers | 3684 |
| Block RAM Tile | 184.5 |
| DSPs | 1 |

Vivado 报告显示：`All user specified timing constraints are met.`

### X2 4x4

文件：

- bitstream：`vivado/bitstreams/jfs_full_span_x2_4x4.bit`
- timing：`vivado/reports/jtag_full_span_x2_4x4_timing_impl.rpt`
- utilization：`vivado/reports/jtag_full_span_x2_4x4_utilization_impl.rpt`

关键结果：

| 项目 | 数值 |
| --- | ---: |
| WNS | 15.010 ns |
| WHS | 0.007 ns |
| CLB LUTs | 5705 |
| CLB Registers | 3674 |
| Block RAM Tile | 178.5 |
| DSPs | 1 |

Vivado 报告显示：`All user specified timing constraints are met.`

## 4. 当前默认配置

本次验证后已恢复默认 RTL 生成配置为 X4：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\export_official_span_x4_to_rtl.ps1
```

恢复后复测：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compare_span_frame_engine_smoke.ps1 -ImgW 4
```

结果：

```text
PASS compare_span_frame_engine_smoke_x4_4x4: 768 bytes match
```

## 5. 阶段结论

当前已经证明：

1. Vivado 可以识别板卡 JTAG 目标。
2. 完整官方 SPAN X4 4x4 bitstream 可以下载到板上运行。
3. 完整官方 SPAN X2 2x2 和 X2 4x4 bitstream 可以下载到板上运行。
4. 板上输出与同输入固定点参考逐字节一致。
5. X2/X4 4x4 Vivado 实现均满足时序约束。

当前仍属于小图功能验证阶段，不等同于真实视频会议实时超分。下一阶段需要把输入从 JTAG 小图扩展到 SD/PS 或更高吞吐数据通路，并逐步扩大图像块尺寸，验证 DDR/缓存、数据搬运、端到端延迟和输出显示效果。

## 6. 复测脚本

本次将手工同输入参考比较固化为脚本：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compare_jtag_full_span_output.ps1 -Scale 4 -ImgW 4
powershell -ExecutionPolicy Bypass -File scripts\compare_jtag_full_span_output.ps1 -Scale 2 -ImgW 4
```

已复测通过：

```text
PASS compare_jtag_full_span_output_x4_4x4: 768 bytes match
PASS compare_jtag_full_span_output_x2_4x4: 192 bytes match
```

## 7. 真实 PNG 图像块验证

本次继续将输入从固定小色块扩展为真实 PNG 图像块。测试图像使用：

```text
external/SPAN/test_scripts/data/baboon.png
```

脚本会将 PNG 缩放为当前 bitstream 支持的输入尺寸，再转换为 RGB888 raw，通过 USB-JTAG 写入 FPGA。

### X4 4x4 实图输入

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 4 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x4_4x4_out.png
```

结果：

```text
Input counter : 16
Output counter: 256
Error flags   : 0x00000000
Wrote board_runs\full_span_jtag_smoke\output_x4_4x4.rgb (768 bytes)
PASS compare_jtag_full_span_output_x4_4x4: 768 bytes match
```

输出图像：

```text
board_runs/full_span_jtag_smoke/baboon_x4_4x4_out.png
```

### X2 4x4 实图输入

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 4 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x2_4x4_out.png
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
board_runs/full_span_jtag_smoke/baboon_x2_4x4_out.png
```

### 对比预览图

新增脚本：

```text
tools/make_sr_preview.py
```

生成的预览图：

```text
board_runs/full_span_jtag_smoke/baboon_x2_x4_preview.png
```

该图左侧为 4x4 输入放大显示，中间为 X2 板上输出，右侧为 X4 板上输出。由于当前 bitstream 只验证到 4x4 输入，图像只能证明真实 PNG 输入输出流程已跑通，不代表最终大图或视频会议画质。

## 8. X4 8x8 真实 PNG 图像块验证

在 X4 4x4 真实 PNG 链路通过后，本次继续扩大输入尺寸到 `8x8`，输出为 `32x32`。

### Vivado 实现结果

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_bitstream_jtag_full_span_scale.ps1 -Scale 4 -ImgW 8
```

生成文件：

- bitstream：`vivado/bitstreams/jfs_full_span_x4_8x8.bit`
- timing：`vivado/reports/jtag_full_span_x4_8x8_timing_impl.rpt`
- utilization：`vivado/reports/jtag_full_span_x4_8x8_utilization_impl.rpt`

关键结果：

| 项目 | 数值 |
| --- | ---: |
| WNS | 14.550 ns |
| WHS | 0.012 ns |
| CLB LUTs | 6461 |
| CLB Registers | 3767 |
| Block RAM Tile | 184.5 |
| DSPs | 1 |

Vivado 报告显示：`All user specified timing constraints are met.`

### JTAG 上板实图验证

命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 8 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x4_8x8_out.png
```

结果：

```text
Input counter : 64
Output counter: 1024
Error flags   : 0x00000000
Wrote board_runs\full_span_jtag_smoke\output_x4_8x8.rgb (3072 bytes)
```

输出图像：

```text
board_runs/full_span_jtag_smoke/baboon_x4_8x8_out.png
```

同输入固定点参考比较：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\compare_jtag_full_span_output.ps1 -Scale 4 -ImgW 8 -BuildDir board_runs\full_span_jtag_smoke\compare_x4_8x8
```

结果：

```text
PASS compare_jtag_full_span_output_x4_8x8: 3072 bytes match
```

结论：完整官方 SPAN X4 `8x8 -> 32x32` JTAG 上板实图验证通过，板上输出与同输入固定点参考逐字节一致。
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
