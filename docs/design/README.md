# AI 超分 FPGA 纯 RTL 工程说明

本工程面向赛题“AI 超分辨率模型高效硬件加速器设计与实现”，使用资料包中的 `xczu19eg-ffvc1760-2-i` 器件信息创建 Vivado 工程。实现采用纯 SystemVerilog RTL，不依赖 HLS。

## 设计方案

- 输入/输出：RGB888 AXI4-Stream，`tuser` 表示帧首，`tlast` 表示行尾。
- 模型路线：参考 SPAN/ESPCN 的轻量化思想，硬件 baseline 使用低成本残差增强和流式上采样。
- 量化格式：激活 8 bit，内部残差计算使用 16 bit 有符号中间量并饱和回 8 bit。
- x2/x4：`sr_stream_top` 的 `SCALE` 参数可设为 2 或 4。
- 板上验证：`sr_board_demo_top` 在板上生成测试像素流，通过加速器后计算 CRC，并将状态映射到 LED。

## 目录

- `rtl/`：纯 RTL 加速器源代码。
- `sim/`：Vivado xsim testbench。
- `constraints/`：FACE-ZUSSD/ZCU106 资料包裁剪出的 LED、SW、差分时钟约束。
- `scripts/`：Vivado 工程创建、仿真、综合/bitstream 脚本。
- `model/`：模型结构描述和模型到 RTL 参数 include 的转换脚本。

## Vivado 使用

```tcl
vivado -mode batch -source scripts/run_vivado_sim.tcl
vivado -mode batch -source scripts/run_vivado_sim_x4.tcl
vivado -mode batch -source scripts/run_vivado_bitstream.tcl
```

当前机器 PATH 未检测到 Vivado；安装 Vivado 后可直接运行以上命令。

## 后续可替换点

当前 RTL 是可综合、可仿真的硬件 baseline，用于先完成赛题工程闭环。若已有训练好的 SPAN/FSRCNN INT8 权重，可继续将 `sr_residual_enhancer` 替换为多层 3x3 卷积阵列，并沿用同一 AXI-Stream 顶层、testbench 和 Vivado 工程脚本。
