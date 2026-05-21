# 硬件加速器详细设计

## 顶层接口

`rtl/sr_stream_top.sv` 是加速器顶层，使用 AXI4-Stream 风格握手：

- `s_axis_tvalid/tready/tdata/tuser/tlast`：输入像素流。
- `m_axis_tvalid/tready/tdata/tuser/tlast`：输出像素流。
- `tdata`：RGB888。
- `tuser`：一帧首个像素。
- `tlast`：每行最后一个像素。

## 模块划分

`sr_residual_enhancer`

- 保存前一行像素和当前行左邻像素。
- 对非边界像素执行局部残差增强。
- 使用加法、移位和饱和截断，不使用 DSP 乘法器。

`sr_nearest_upsampler`

- 每个输入像素扩展为 `SCALE x SCALE` 个输出像素。
- `SCALE=2` 对应 x2 超分，`SCALE=4` 对应 x4 超分。
- 按输出行重新生成 `tlast`，保持 AXI-Stream 视频时序语义。

`sr_board_demo_top`

- 板级自检顶层。
- 使用资料包中的 `xczu19eg-ffvc1760-2-i` 和 LED/SW/差分时钟约束。
- 内部生成测试像素流，经过加速器后计算 CRC，并在 LED 上显示运行状态。

## 性能与资源分析

当前 baseline 每个输入像素经过残差增强后，上采样输出 `SCALE^2` 个像素。由于上采样模块按像素重复输出，吞吐上限由输出侧带宽决定：

```text
input_accept_rate ~= output_rate / SCALE^2
```

资源特征：

- 残差增强：主要消耗 LUT/FF 和一行 RGB line buffer。
- 上采样：主要消耗寄存器和小规模控制逻辑。
- DSP：当前 baseline 不使用 DSP。
- BRAM：`IMG_W` 较大时，综合器可将 line buffer 推断为分布式 RAM 或 BRAM。

## 上板方式

生成工程：

```tcl
vivado -mode batch -source scripts/create_vivado_project.tcl
```

生成 bitstream：

```tcl
vivado -mode batch -source scripts/run_vivado_bitstream.tcl
```

上板现象：

- `led_0`：复位释放。
- `led_1`：输入可接收。
- `led_2`：输出有效。
- `led_3`：输出行尾脉冲。
- `led_4..led_7`：`sw_1=0` 显示 CRC 抽样位，`sw_1=1` 显示输出计数抽样位。
