# 工作日志

## 2026-05-21

### 已完成事项

1. 阅读赛题要求文档，明确交付目标：
   - 面向视频会议场景的 AI 超分硬件加速器。
   - 支持 REDS 数据集上的 x2、x4 超分验证。
   - 提供模型结构、训练、量化说明，硬件详细设计文档，硬件源代码。
   - RTL 需可在 Vivado 中进行仿真、综合，并用于资源开销评估。

2. 阅读相关论文调研，确定工程路线：
   - 主路线参考 SPAN 的轻量高效超分思想。
   - 上采样参考 ESPCN/PixelShuffle 的低分辨率域计算思路。
   - 量化采用 INT8 激活/权重、INT32 累加的工程方向。
   - 当前先完成纯 RTL baseline，后续可替换为训练后的多层卷积阵列。

3. 阅读 FACE-ZUSSD 资料包，提取板卡与工程信息：
   - 资料包中提供 ZCU106 HPC0 双 SSD 参考工程。
   - Vivado 参考器件为 `xczu19eg-ffvc1760-2-i`。
   - 约束文件中包含 LED、SW、差分时钟等可用于板级自检的引脚。

4. 完成纯 SystemVerilog RTL baseline：
   - `rtl/sr_stream_top.sv`：AXI4-Stream 风格超分加速器顶层。
   - `rtl/sr_residual_enhancer.sv`：流式局部残差增强模块。
   - `rtl/sr_nearest_upsampler.sv`：参数化 x2/x4 上采样模块。
   - `rtl/sr_board_demo_top.sv`：板上自检顶层，内部产生测试像素流并用 LED 显示状态/CRC。

5. 完成 Vivado 工程与验证脚本：
   - `scripts/create_vivado_project.tcl`：创建 Vivado 工程。
   - `scripts/run_vivado_sim.tcl`：运行 x2 仿真。
   - `scripts/run_vivado_sim_x4.tcl`：运行 x4 仿真。
   - `scripts/run_vivado_bitstream.tcl`：综合、实现并生成 bitstream。
   - `constraints/face_zussd_demo.xdc`：从资料包裁剪出的板级自检约束。

6. 完成仿真用例：
   - `sim/tb_sr_stream_top.sv`：x2 输出数量、帧首、行尾验证。
   - `sim/tb_sr_stream_top_x4.sv`：x4 输出数量、帧首、行尾验证。

7. 完成赛题交付文档初版：
   - `docs/design/README.md`：工程总体说明。
   - `docs/design/model_quantization.md`：模型结构、训练与量化说明。
   - `docs/design/hardware_design.md`：硬件加速器详细设计。
   - `docs/design/verification.md`：验证方案与验证用例。

8. 完成模型到硬件参数转换工具初版：
   - `model/example_model.json`：模型/量化结构描述。
   - `model/model_to_rtl.py`：将模型描述转换为 RTL include 参数。

### 已验证事项

- `model/model_to_rtl.py` 已通过 Python 语法检查。
- 模型转换脚本已实际运行，可根据 `--scale 4` 生成 RTL 参数 include。
- 当前工作机 PATH 中未检测到 Vivado，因此尚未在本机完成 xsim 仿真和 bitstream 生成。
- 当前工作机未安装 GitHub CLI `gh`，且工程目录尚未初始化为 git 仓库。

### 当前工程状态

工程已经具备纯 RTL 源码、x2/x4 仿真入口、Vivado 创建工程脚本、综合/bitstream 脚本、板级 LED 自检顶层和赛题交付文档。下一步建议在安装 Vivado 的环境中运行 xsim 与综合实现，依据报告继续优化资源占用和时序。
