# 验证方案与验证用例

## 仿真目标

Vivado xsim testbench 覆盖以下行为：

- 输入 AXI-Stream 握手。
- 输出端反压。
- `tuser` 帧首只出现一次。
- `tlast` 行尾按放大后的输出行数出现。
- x2 和 x4 两种尺度输出像素数量正确。

## 用例

`sim/tb_sr_stream_top.sv`

- 输入尺寸：8 x 5。
- 放大倍率：x2。
- 期望输出 beat：`8 * 5 * 2 * 2 = 160`。
- 期望输出行尾：`5 * 2 = 10`。

`sim/tb_sr_stream_top_x4.sv`

- 输入尺寸：4 x 3。
- 放大倍率：x4。
- 期望输出 beat：`4 * 3 * 4 * 4 = 192`。
- 期望输出行尾：`3 * 4 = 12`。

## 运行命令

```tcl
vivado -mode batch -source scripts/run_vivado_sim.tcl
vivado -mode batch -source scripts/run_vivado_sim_x4.tcl
```

预期日志包含：

```text
PASS sr_stream_top: out=160 sof=1 eol=10
PASS sr_stream_top_x4: out=192 sof=1 eol=12
```

## 综合/实现检查

```tcl
vivado -mode batch -source scripts/run_vivado_bitstream.tcl
```

完成后检查：

- `build/vivado_sr_accel/sr_accel.runs/synth_1/*.rpt`
- `build/vivado_sr_accel/sr_accel.runs/impl_1/*.rpt`
- `build/vivado_sr_accel/sr_accel.runs/impl_1/*.bit`

当前工作机 PATH 未检测到 Vivado，因此本次未在本机完成 xsim 与 bitstream 生成。
