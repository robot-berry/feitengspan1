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
   - `rtl/sr_stream_top.v`：AXI4-Stream 风格超分加速器顶层。
   - `rtl/sr_residual_enhancer.v`：流式局部残差增强模块。
   - `rtl/sr_nearest_upsampler.v`：参数化 x2/x4 上采样模块。
   - `rtl/sr_board_demo_top.v`：板上自检顶层，内部产生测试像素流并用 LED 显示状态/CRC。

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

### 2026-05-21 方案更新

1. 根据 `2311.12770v3.pdf` 和 `2604.03198v1.pdf` 更新方案：
   - 训练主模型调整为 TinySPAN。
   - 结构对齐 SPAN 的 `head conv + SPAB x6 + feature concat + PixelShuffle`。
   - 评估目标补充 runtime、参数量、FLOPs 和 PSNR 的综合指标。

2. 新增 REDS 训练代码：
   - `train/span_model.py`：TinySPAN/SPAB/Conv3XC 模型。
   - `train/reds_dataset.py`：REDS HR 帧读取、在线 x2/x4 bicubic LR 生成和退化增强。
   - `train/train_reds_span.py`：训练、验证、checkpoint 和 PSNR 评估。
   - `configs/train_reds_span_x4.json`：x4 训练命令模板。

3. 验证：
   - Python 语法检查通过。
   - 在临时设置 `KMP_DUPLICATE_LIB_OK=TRUE` 时，TinySPAN x2/x4 前向输出尺寸检查通过。
   - 当前 Anaconda 环境默认运行 PyTorch 前向会触发 OpenMP runtime 冲突，需后续整理依赖环境。

4. 已连接 G 盘 REDS 数据集并完成短训练：
   - 训练集：`G:/REDS/train_sharp`，24000 张。
   - 验证集：`G:/REDS/val_sharp`，3000 张。
   - smoke 训练命令：`scripts/train_reds_x4_smoke.ps1`。
   - smoke 输出：`runs/tinyspan_reds_x4_smoke/best.pt` 和 `last.pt`。
   - 已通过 `scripts/export_latest_tinyspan_to_rtl.ps1` 导出 INT8 `.mem` 权重与 `rtl/generated/tinyspan_model_config.vh`。

5. TinySPAN RTL 替换：
   - 新增 `rtl/sr_tinyspan_core.v`。
   - `rtl/sr_stream_top.v` 已改为实例化 `sr_tinyspan_core`。
   - 旧的 `sr_residual_enhancer` 不再位于顶层数据通路中。
   - `sr_tinyspan_core` 按 `head -> SPAB x6 -> stream PixelShuffle` 组织，并读取 `rtl/generated/tinyspan_model_config.vh`。

6. 完整训练任务：
   - 启动脚本：`scripts/start_full_training.ps1`。
   - 状态脚本：`scripts/training_status.ps1`。
   - 日志路径：`runs/tinyspan_reds_x4_full/train_stdout.log`。
   - 当前配置：x4、48 通道、6 个 SPAB、batch size 16、200 epoch、AMP。
   - 数据路径：`G:/REDS/train_sharp` 与 `G:/REDS/val_sharp`。
   - 说明：按当前 RTX 3060 Laptop 速度，完整 200 epoch 预计需要十几个小时，训练会按 `last.pt`、`best.pt` 和每 5 epoch 一个 `epoch_XXXX.pt` 持续保存，可中断后用 `--resume` 恢复。

7. 训练可视化：
   - 新增 `train/visualize_training.py`，解析训练日志并生成 HTML 仪表盘。
   - 新增 `scripts/update_training_dashboard.ps1`，单次刷新仪表盘。
   - 新增 `scripts/watch_training_dashboard.ps1`，后台每 30 秒刷新仪表盘。
   - 新增 `scripts/open_training_dashboard.ps1`，刷新并打开仪表盘。
   - 当前仪表盘路径：`runs/tinyspan_reds_x4_full/dashboard.html`。
### 2026-05-21 训练异常修正

1. 停止了旧的异常训练任务：
   - 旧日志目录：`runs/tinyspan_reds_x4_full`
   - 异常现象：验证 PSNR 长时间停留在约 7.956 dB，SR 输出亮度明显塌缩。
2. 定位到训练模型输出路径问题：
   - 原模型从随机初始化直接生成 HR 图像。
   - `forward()` 中训练阶段直接 `clamp(0, 1)`，容易让输出和梯度被截断。
   - 初始 SR 均值远低于 HR/LR，说明网络先学“整幅图重建”而不是“高频残差”。
3. 修正 `train/span_model.py`：
   - 增加 bicubic 上采样基底：`base = F.interpolate(...)`。
   - 网络输出改为 `base + residual`。
   - 去掉训练前向中的最终 clamp，仅在 PSNR 评估函数中 clamp。
   - 将最后 `reconstruct` 层初始化为 0，使未训练模型从 bicubic 基线开始。
4. 修正后验证：
   - 8 张验证样本的 bicubic/初始模型 PSNR 均为约 24.795 dB。
   - 小规模 smoke 训练 1 epoch 后，验证 PSNR 达到 26.294 dB。
5. 重新启动修正后的全量训练：
   - 新日志目录：`runs/tinyspan_reds_x4_full_fixed`
   - 新 dashboard：`runs/tinyspan_reds_x4_full_fixed/dashboard.html`
   - 当前旧目录保留作为问题记录，不再继续写入。

### 2026-05-21 切换到官方 SPAN 训练

1. 按要求停止了当前本地 TinySPAN 训练：
   - 停止进程树：`train/train_reds_span.py` 及其 DataLoader 子进程。
   - 不再继续更新 `runs/tinyspan_reds_x4_full_fixed`。
2. 下载并接入官方 SPAN 代码：
   - 官方代码目录：`external/SPAN`
   - 来源：`https://github.com/hongyuanyu/SPAN`
   - 当前使用官方 `basicsr/archs/span_arch.py` 中的 `SPAN` 网络结构。
3. 准备官方 BasicSR 配对数据：
   - 解压 `G:/REDS/train_sharp_bicubic.zip` 到 `G:/REDS/train/train_sharp_bicubic/X4`
   - 解压 `G:/REDS/val_sharp_bicubic.zip` 到 `G:/REDS/val/val_sharp_bicubic/X4`
   - 生成 `configs/meta_info_REDS_train_GT.txt`，共 24000 张。
   - 生成 `configs/meta_info_REDS_val_GT.txt`，共 3000 张。
4. 新增官方训练配置和脚本：
   - 配置：`external/SPAN/options/train/SPAN/train_SPAN_REDS_x4.yml`
   - 启动：`scripts/start_official_span_training.ps1`
   - 训练：`scripts/train_official_span_reds_x4.ps1`
   - 状态：`scripts/official_span_status.ps1`
5. 兼容当前 Python 环境：
   - 修复新版 torchvision 中 `functional_tensor` 路径变化。
   - 补充 `basicsr/version.py`。
   - 补充 L1-only 训练所需的 `vgg_arch.py` 兼容占位。
   - 修复 REDS 嵌套目录 meta-info 配对时丢失子目录的问题。
   - 关闭 TensorBoard logger，避免当前环境缺少 `tensorboard` 导致训练中断。
6. 官方 SPAN 训练已启动：
   - 日志：`runs/official_span_logs/train_stdout.log`
   - 实验输出：`runs/official_span/official_SPAN_REDS_x4_f48`
   - 配置：x4、feature_channels=48、L1Loss、EMA=0.999、total_iter=300000。

### 2026-05-21 官方训练可视化替换

1. 停止旧 TinySPAN dashboard watcher。
2. 新增官方 SPAN/BasicSR 日志可视化：
   - 脚本：`train/visualize_official_span.py`
   - 输出：`runs/official_span/dashboard.html`
   - 解析内容：iter、epoch、learning rate、ETA、L1 loss、验证 PSNR。
3. 替换原有可视化入口：
   - `scripts/update_training_dashboard.ps1` 已改为刷新官方 SPAN dashboard。
   - `scripts/open_training_dashboard.ps1` 已改为打开 `runs/official_span/dashboard.html`。
   - `scripts/watch_training_dashboard.ps1` 已改为每 30 秒刷新官方 SPAN dashboard。
4. 旧页面 `runs/tinyspan_reds_x4_full/dashboard.html` 已改为自动跳转到官方 SPAN dashboard。

### 2026-05-21 X4 训练验证与 X2 准备

1. 验证当前 X4 官方 SPAN 训练链路：
   - 训练数据配对：`G:/REDS/train/train_sharp_bicubic/X4/...` -> `G:/REDS/train_sharp/...`
   - 训练样本尺寸：LR `3x48x48`，HR `3x192x192`。
   - 验证样本尺寸：LR `3x180x320`，HR `3x720x1280`。
   - `5000 iter` 已成功保存 `net_g_5000.pth` 和 `5000.state`。
   - 第一次完整验证结果：REDS_val PSNR `25.6775 dB @ 5000 iter`。
2. 修正官方 dashboard 对 UTF-16 PowerShell 日志和 BasicSR 验证日志的解析。
3. 准备 X2 官方 SPAN 训练入口，但暂不启动：
   - 数据生成脚本：`scripts/generate_reds_bicubic.py`
   - X2 数据准备脚本：`scripts/prepare_official_span_x2.ps1`
   - X2 配置：`external/SPAN/options/train/SPAN/train_SPAN_REDS_x2.yml`
   - X2 训练脚本：`scripts/train_official_span_reds_x2.ps1`
   - X2 启动脚本：`scripts/start_official_span_x2_training.ps1`
   - X2 状态脚本：`scripts/official_span_x2_status.ps1`
4. 执行顺序约定：
   - 当前继续完整跑完 X4。
   - X4 完成后运行 `scripts/prepare_official_span_x2.ps1` 生成 X2 LR 数据。
   - 先验证 X2 数据配对和小规模训练正常，再启动完整 X2 训练。

### 2026-05-22 视频会议实时超分外围模块

1. 在不打断官方 SPAN x4 训练的前提下，新增两个硬件友好的视频稳定模块：
   - `rtl/video_gain_smoother.v`：帧间亮度/增益平滑，只保存亮度统计寄存器，不需要帧缓存。
   - `rtl/video_temporal_residual_filter.v`：轻量时域残差滤波预留模块。
2. 更新 `rtl/sr_stream_top.v` 数据通路：
   - `SPAN core -> video_gain_smoother -> video_temporal_residual_filter -> AXI-Stream output`
   - `VIDEO_GAIN_EN=1` 默认打开亮度稳定。
   - `TEMPORAL_FILTER_EN=0` 默认旁路时域残差滤波，避免在没有 DDR/帧缓存规划时增加 BRAM。
3. `video_temporal_residual_filter` 在 `ENABLE=0` 时综合为纯旁路，不会保留完整上一帧缓存。
4. 当前工作机未检测到 `xvlog`、`iverilog` 或 `yosys`，本次只完成 RTL 接入和静态检查；Vivado 仿真需在安装 Vivado 的环境中执行。

### 2026-05-23 X4 恢复训练

1. 检查发现官方 SPAN x4 训练未正常结束：
   - 已保存到 `280000.state` / `net_g_280000.pth`。
   - 最好验证结果：`REDS_val PSNR 28.3087 dB @ 280000 iter`。
   - 日志中未出现 `End of training`。
2. 新增恢复脚本：
   - `scripts/resume_official_span_x4_training.ps1`
   - 自动选择 `training_states` 中最大 iter 的 `.state` 继续训练。
3. 修复 BasicSR 在 Windows 恢复训练时覆盖实验配置文件导致的权限问题：
   - `external/SPAN/basicsr/train.py` 在 resume 时跳过重复复制配置文件。
4. 已从 `280000.state` 成功恢复：
   - 日志：`runs/official_span_logs/resume_stdout.log`
   - 恢复位置：`epoch 186, iter 280000`
   - 已继续输出 `280100+` 训练记录。
5. 官方 dashboard 已改为同时解析原始训练日志和恢复训练日志。
## 2026-05-24 下一步执行记录

1. 完成官方 SPAN x4 训练结果确认：
   - 最终权重：`runs/official_span/official_SPAN_REDS_x4_f48/models/net_g_latest.pth`
   - 完整 checkpoint：`runs/official_span/official_SPAN_REDS_x4_f48/training_states/300000.state`
   - 最佳验证结果：REDS_val PSNR `28.3118 dB @ 295000 iter`
   - 最终验证结果：REDS_val PSNR `28.3110 dB @ latest`

2. 新增官方 SPAN 权重导出流程：
   - 新增 `train/export_official_span_to_rtl.py`
   - 新增 `scripts/export_official_span_x4_to_rtl.ps1`
   - 从官方 checkpoint 的 `params_ema` 加载模型，并在 eval 前向中融合 Conv3XC 的 `eval_conv`
   - 导出 44 个部署卷积张量到 `rtl/generated/official_span_x4/weights`
   - 生成 `rtl/generated/official_span_model_config.vh`
   - 同步更新 `rtl/generated/tinyspan_model_config.vh`，将 RTL 兼容参数切换为 x4、48 通道、6 个 SPAB block

3. 修正 RTL 注释和流式核心边界说明：
   - 重写 `rtl/sr_tinyspan_core.v` 中损坏的中文注释
   - 修复因乱码导致的部分语句被注释吞掉的问题
   - 明确当前 RTL 是可综合的流式硬件近似核心；官方 SPAN 权重已经导出，下一步需要继续把近似计算替换成 INT8 卷积阵列

4. 准备并启动官方 SPAN x2 训练：
   - 生成 x2 训练 LR 数据：`G:/REDS/train/train_sharp_bicubic/X2`，共 24000 张
   - 生成 x2 验证 LR 数据：`G:/REDS/val/val_sharp_bicubic/X2`，共 3000 张
   - 验证样本尺寸：GT `1280x720`，LQ `640x360`，比例为 x2
   - 启动后台训练脚本：`scripts/start_official_span_x2_training.ps1`
   - 训练日志：`runs/official_span_logs_x2/train_stdout.log`
   - 当前进度记录：已完成第一次验证，REDS_val PSNR `29.4535 dB @ 5000 iter`
   - 训练已继续运行到 `5200 iter` 以后，后台进程仍在继续完整训练

5. 更新训练可视化：
   - 修复 `train/visualize_official_span.py` 的中文乱码
   - 增加 `--title` 参数，支持 x4/x2 共用
   - 新增 `scripts/update_training_dashboard_x2.ps1`
   - 新增 `scripts/watch_training_dashboard_x2.ps1`
   - x4 dashboard：`runs/official_span/dashboard.html`
   - x2 dashboard：`runs/official_span_x2/dashboard.html`

6. 当前限制：
   - 当前机器 PATH 中未检测到 `vivado`、`xvlog`、`iverilog` 或 `verilator`
   - 因此本轮只完成 RTL 文件修正、权重导出、脚本语法检查和训练启动；Vivado 仿真仍需在安装 Vivado 的环境中执行

## 2026-05-25 X2 完成与 RTL 更新

1. 官方 SPAN x2 完整训练结束：
   - 结束时间：`2026-05-25 19:33:19`
   - 日志状态：`End of training`
   - 最终权重：`runs/official_span/official_SPAN_REDS_x2_f48/models/net_g_latest.pth`
   - 300000 iter 权重：`runs/official_span/official_SPAN_REDS_x2_f48/models/net_g_300000.pth`
   - 训练状态：`runs/official_span/official_SPAN_REDS_x2_f48/training_states/300000.state`
   - 最终/最佳 PSNR：`34.4297 dB @ 300000 iter`

2. 更新 X2 权重到 RTL：
   - 新增 `scripts/export_official_span_x2_to_rtl.ps1`
   - 重新运行 `train/export_official_span_to_rtl.py`
   - 输出目录：`rtl/generated/official_span_x2`
   - 当前 RTL 默认配置已切换到 X2、48 通道、6 个 SPAB block
   - 新增 `rtl/generated/official_span_layers.vh`，将 44 个官方部署张量映射为 RTL 层表

3. 新增官方 SPAN RTL 集成入口和 INT8 基础模块：
   - `rtl/sr_span_official_core.v`：官方 SPAN 部署核心入口
   - `rtl/span_int8_dot3x3.v`：INT8 3x3 点积 MAC
   - `rtl/span_int8_conv3x3_layer.v`：读取 `.mem` 权重的顺序式 INT8 3x3 卷积层
   - `rtl/span_int8_quantize.v`：INT32 到 INT8 重量化与饱和
   - `rtl/span_int8_activations.v`：SiLU/LeakyReLU/sigmoid 硬件近似
   - `rtl/span_spab_int8_block.v`：SPAB 控制和 parameter-free attention 算术骨架

4. 更新顶层接入方式：
   - `rtl/sr_stream_top.v` 新增 `USE_OFFICIAL_SPAN` 参数
   - 默认进入 `sr_span_official_core`
   - `sr_span_official_core` 已接入 `conv_1.eval_conv` 的 X2 官方权重层锚点
   - 当前 `sr_span_official_core` 输出仍保留兼容流式核心，保证仿真和上板链路不断

5. 状态说明：
   - 新增 `docs/design/rtl_span_completion_status.md`
   - 明确当前已完成官方训练、权重导出、层表和 RTL 基础模块
   - 明确剩余工作是逐层连接 48 通道 INT8 卷积流水线，并做 Python 定点模型与 Vivado 仿真对齐
## 2026-05-26 阶段一 DVP 摄像头到 HDMI 纯 PL 验证链路

1. 新增阶段一上板验证顶层：
   - `rtl/sr_stage1_dvp_hdmi_top.v`
   - 功能链路：DVP RGB565 摄像头输入 -> BRAM 帧缓存 -> 2x 最近邻放大 -> 并行 RGB HDMI 输出。
   - 默认输入窗口为 `320x240`，输出为 `640x480`，便于先用常见 VGA/HDMI 时序上屏验证。

2. 新增阶段一基础 RTL 模块：
   - `rtl/dvp_rgb565_frame_writer.v`：接收 DVP 两字节 RGB565 像素，扩展为 RGB888，并按行列写入帧缓存。
   - `rtl/video_framebuffer_dual_clock.v`：双时钟 BRAM 帧缓存，写端为摄像头 pclk，读端为 HDMI 像素时钟。
   - `rtl/framebuffer_x2_hdmi_reader.v`：从帧缓存读取图像并做 2x 最近邻放大，输出 DE/HS/VS/RGB。

3. 新增 Vivado 阶段一仿真：
   - `sim/tb_stage1_dvp_hdmi.sv`
   - `scripts/run_vivado_sim_stage1.tcl`
   - 仿真工程独立放在 `build/vivado_stage1_sim`，避免和当前打开的主 Vivado 工程冲突。
   - Vivado 2025.2 行为仿真通过：`PASS stage1_dvp_hdmi: writes=12 nonblack=12 out_pixels=22`。

4. 新增上板说明：
   - `docs/design/stage1_dvp_hdmi_bringup.md`
   - 说明了阶段一顶层、LED 含义、预期上屏效果，以及仍需从原理图补齐的 DVP/HDMI XDC 管脚和摄像头/HDMI TX I2C 初始化表。

## 2026-05-26 SD 文件输入输出方案替换

1. 根据 FACE-ZUSSD 主板资源重新调整上板验证方案：
   - 主板 MicroSD 位于 PS 侧 SD1/MIO44..51。
   - 主板没有独立 DVP 摄像头接口，也没有并行 RGB HDMI TX 接口。
   - 当前输入输出模式改为 PS 读写 SD 文件，PL 通过 AXI-Lite 完成超分像素处理。

2. 删除旧 DVP/HDMI 输入输出链路：
   - 删除 `rtl/sr_camera_hdmi_top.v`、`rtl/sr_stage1_dvp_hdmi_top.v`
   - 删除 DVP/HDMI 相关采集、帧缓存、HDMI 读出 RTL
   - 删除对应 XDC 模板、阶段一仿真脚本和说明文档

3. 新增 SD/AXI-Lite RTL 与软件示例：
   - `rtl/sr_sd_axi_lite_accel.v`
   - `sim/tb_sr_sd_axi_lite_accel.sv`
   - `scripts/run_vivado_sim_sd_axi.tcl`
   - `scripts/create_vivado_sd_axi_open_project.tcl`
   - `scripts/run_vivado_synth_sd_axi.tcl`
   - `software/sd_file_sr_demo/src/main.c`
   - `tools/convert_rgb_raw.py`
   - `docs/design/sd_file_io_plan.md`

4. 完成验证：
   - Vivado 行为仿真通过：`PASS sr_sd_axi_lite_accel: out=48`
   - Vivado 综合通过：`SD_AXI_SYNTH_STATUS=synth_design Complete!`
   - 可打开 Vivado 工程：`vivado/sd_axi_accel_openable/sd_axi_accel_openable.xpr`
## 2026-06-03 完整官方 SPAN RTL 对齐与完整上板工程入口

1. 完成完整官方 SPAN 帧级 RTL 与 Python 定点参考对齐：
   - 新增/完善 `tools/span_official_fixed_ref.py`，读取官方 X2 `.mem` 权重并复现 RTL INT8 计算。
   - 修正 `rtl/span/span_official_frame_engine.v` 中 SiLU 和 SPAB attention 的有符号整数计算，避免负数激活被错误压成 0。
   - 修复该文件头部中文注释乱码导致 `module` 声明被注释掉的问题，并保存为 UTF-8 无 BOM。
   - 通过 `scripts/compare_span_frame_engine_smoke.ps1`，结果为 `PASS compare_span_frame_engine_smoke: 12 bytes match`。

2. 完成完整 SPAN 的 AXI 端点参数接入：
   - `rtl/board/sr_sd_axi_lite_accel.v` 增加 `USE_FULL_OFFICIAL_SPAN` 参数。
   - `rtl/board/sr_jtag_rgb_transfer_endpoint.v` 增加 `USE_FULL_OFFICIAL_SPAN` 参数。
   - 完整官方 SPAN 可通过 `USE_FULL_OFFICIAL_SPAN=1` 从 SD/PS 或 JTAG AXI 入口打开。

3. 完成完整 SPAN 的 Vivado Block Design 工程入口：
   - 新增 `scripts/create_vivado_jtag_full_span_bd_project.tcl`。
   - 已生成工程 `vivado/jtag_full_span_rgb_transfer_bd/jtag_full_span_rgb_transfer_bd.xpr`。
   - 新增 `scripts/create_vivado_sd_full_span_bd_project.tcl`。
   - 已生成工程 `vivado/sd_full_span_sr_bd/sd_full_span_sr_bd.xpr`。
   - 两个工程均使用 AXI 基地址 `0xA0000000`。

4. 完成完整 SPAN AXI smoke 仿真：
   - 新增 `sim/tb_sr_sd_axi_lite_accel_full_span_smoke.sv`。
   - 新增 `scripts/run_vivado_sim_sd_axi_full_span_smoke.tcl`。
   - 仿真结果为 `PASS sr_sd_axi_lite_accel_full_span_smoke: out=4`。

5. 完成第一版 BRAM/ROM 友好化整理：
   - 官方权重银行增加 `rom_style="block"` 属性。
   - frame engine 的帧缓存和特征缓存增加 `ram_style="block"` 属性。
   - 保持已通过的仿真行为不变。
   - 完整资源收益仍需后续长时间综合、实现和资源报告确认。

6. 当前边界：
   - 纯 RTL 已经实现官方 SPAN 的完整计算流程，并能在小图 smoke 中对齐 Python 定点参考。
   - 当前完整 engine 是功能验证版，采用整帧缓存和单 MAC 顺序调度，适合小图上板验证，不适合实时视频吞吐。
   - 下一步需要对完整 SPAN BD 工程生成 bitstream，并用 JTAG/SD 输入 1x1、2x2、4x4 小图做板级验证。

## 2026-06-05 完整官方 SPAN X2/X4 Vivado 实现闭环

1. 完成完整官方 SPAN frame engine 的同步 RAM 改造：
   - 新增 `rtl/span/span_sync_ram_1r1w.v`。
   - `rtl/span/span_official_frame_engine.v` 中主要特征缓存和 pixel-shuffle 输出缓存改为同步 RAM。
   - 增加同步权重 ROM 与同步特征 RAM 的读延迟等待状态，修正 MAC 输入错位问题。
2. 完成当前 X4 默认配置功能复核：
   - `powershell -ExecutionPolicy Bypass -File scripts\compare_span_frame_engine_smoke.ps1 -ImgW 2`
   - 结果：`PASS compare_span_frame_engine_smoke_x4_2x2: 192 bytes match`。
3. 完成 X4 最小 JTAG 完整 SPAN Vivado 实现：
   - bitstream：`vivado/bitstreams/jfs_full_span_x4_1x1.bit`
   - timing：`vivado/reports/jtag_full_span_x4_1x1_timing_impl.rpt`
   - utilization：`vivado/reports/jtag_full_span_x4_1x1_utilization_impl.rpt`
   - 实现后 WNS：`14.516 ns`，Vivado 报告显示约束满足。
4. 完成 X2 最小 JTAG 完整 SPAN Vivado 实现：
   - bitstream：`vivado/bitstreams/jfs_full_span_x2_1x1.bit`
   - timing：`vivado/reports/jtag_full_span_x2_1x1_timing_impl.rpt`
   - utilization：`vivado/reports/jtag_full_span_x2_1x1_utilization_impl.rpt`
   - 实现后 WNS：`13.592 ns`，Vivado 报告显示约束满足。
5. 更新脚本：
   - `scripts/run_vivado_bitstream_jtag_full_span_scale.ps1` 现在会同时归档 bitstream、utilization 报告和 timing 报告。
6. 新增详细记录：
   - `docs/design/full_span_vivado_implementation_2026_06_05.md`。

当前结论：完整官方 SPAN 的 44 个导出张量已接入 RTL，并完成 X2/X4 最小输入尺寸的 Vivado 综合、实现、布线和 bitstream 生成。当前仍属于最小板级验证工程，下一步应扩大输入尺寸并进行 JTAG 图像读写上板验证。

## 2026-06-05 完整官方 SPAN 2x2 Vivado 扩展与上板 smoke 准备

1. 完成 X4 `IMG_W=2` 完整 SPAN JTAG 工程 bitstream：
   - bitstream：`vivado/bitstreams/jfs_full_span_x4_2x2.bit`
   - timing：`vivado/reports/jtag_full_span_x4_2x2_timing_impl.rpt`
   - utilization：`vivado/reports/jtag_full_span_x4_2x2_utilization_impl.rpt`
   - 实现后 WNS：`14.223 ns`，Vivado 报告显示约束满足。
   - 资源：CLB LUTs `5102`，CLB Registers `3607`，Block RAM Tile `184.5`，DSP `3`。
2. 完成 X2 `IMG_W=2` 完整 SPAN JTAG 工程 bitstream：
   - bitstream：`vivado/bitstreams/jfs_full_span_x2_2x2.bit`
   - timing：`vivado/reports/jtag_full_span_x2_2x2_timing_impl.rpt`
   - utilization：`vivado/reports/jtag_full_span_x2_2x2_utilization_impl.rpt`
   - 实现后 WNS：`14.144 ns`，Vivado 报告显示约束满足。
   - 资源：CLB LUTs `5080`，CLB Registers `3595`，Block RAM Tile `178.5`，DSP `3`。
3. 更新 `scripts/run_jtag_full_span_smoke.ps1`：
   - 新增 `-ImgW` 参数，支持 `1x1` 和 `2x2` 输入尺寸。
   - `2x2` smoke 输入自动生成 4 个确定性 RGB888 色块，输入 raw 文件大小为 12 bytes。
   - X4 2x2 预期输出为 `8x8`，共 64 个 RGB888 像素。
   - X2 2x2 预期输出为 `4x4`，共 16 个 RGB888 像素。
4. 完成脚本 dry-run：
   - `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 2 -SkipHardware`
   - `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 2 -SkipHardware`
   - 两个输入文件均成功生成，大小均为 12 bytes。
5. 恢复默认 RTL 配置到 X4：
   - 执行 `scripts/export_official_span_x4_to_rtl.ps1`，重新导出官方 SPAN X4 的 44 个张量。
   - 当前 `rtl/generated/official_span_model_config.vh` 为 `OFFICIAL_SPAN_MODEL_SCALE 4`。
6. 重新验证 X4 `2x2` RTL/Python 固定点一致性：
   - 命令：`powershell -ExecutionPolicy Bypass -File scripts\compare_span_frame_engine_smoke.ps1 -ImgW 2`
   - 结果：`PASS compare_span_frame_engine_smoke_x4_2x2: 192 bytes match`。
7. 新增详细记录：
   - `docs/design/full_span_2x2_vivado_and_board_smoke_2026_06_05.md`。
8. 尝试 X4 `2x2` 实际 JTAG 上板 smoke：
   - 命令：`powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 2`
   - 脚本确认输入为 `2x2`、X4，输入大小 12 bytes，预期输出 192 bytes。
   - Vivado 返回：`No hardware target found. Check USB-JTAG cable and board power.`
   - 结论：当前阻塞在 Vivado 未识别板卡 JTAG 目标，尚未进入 bitstream 下载和 SPAN 计算阶段。
   - 已清理本次 Vivado 探测留下的 `hw_server/cs_server` 进程。

当前结论：完整官方 SPAN 已经完成 X2/X4 的 `2x2` Vivado 可实现验证，并具备通过 USB-JTAG 做最小多像素上板 smoke 的 bitstream 和脚本。实际上板验证现在是必要步骤，但当前失败在 Vivado 没有找到 hardware target，下一步需要先确认板卡上电、USB-JTAG 驱动和 Vivado Hardware Manager 能识别目标，再运行 X4 2x2 和 X2 2x2 smoke。
## 2026-06-11 完整官方 SPAN X2/X4 实际上板 smoke 验证

1. 完成 Vivado/JTAG 板卡识别复测：
   - Vivado Hardware Manager 已能枚举到 JTAG target：`localhost:3121/xilinx_tcf/Digilent/210203367162A`。
   - 识别到器件：`xczu19_0` 和 `arm_dap_1`。
   - 结论：之前的 `No hardware target found` 阻塞已解除，可以进入 bitstream 下载和 JTAG-to-AXI 读写验证。

2. 完成完整官方 SPAN X4 `IMG_W=4` 板级 smoke：
   - bitstream：`vivado/bitstreams/jfs_full_span_x4_4x4.bit`。
   - 输入：`4x4` RGB888，共 16 个输入像素。
   - 输出：X4 后 `16x16` RGB888，共 256 个输出像素，`768 bytes`。
   - 板上计数：`Input counter : 16`，`Output counter: 256`，`Error flags : 0x00000000`。
   - 同输入固定点参考比较：`PASS board_x4_4x4_matches_same_input_ref bytes=768`。

3. 完成完整官方 SPAN X2 `IMG_W=2` 和 `IMG_W=4` 板级 smoke：
   - X2 `2x2`：输出 `4x4`，`48 bytes`，同输入参考比较通过。
   - X2 `4x4`：输出 `8x8`，`192 bytes`，同输入参考比较通过。
   - X2 `4x4` 板上计数：`Input counter : 16`，`Output counter: 64`，`Error flags : 0x00000000`。
   - X2 `4x4` 同输入固定点参考比较：`PASS board_x2_4x4_matches_same_input_ref bytes=192`。

4. 补齐 X2 `IMG_W=4` Vivado 实现结果：
   - bitstream：`vivado/bitstreams/jfs_full_span_x2_4x4.bit`。
   - timing：`vivado/reports/jtag_full_span_x2_4x4_timing_impl.rpt`。
   - utilization：`vivado/reports/jtag_full_span_x2_4x4_utilization_impl.rpt`。
   - WNS：`15.010 ns`，WHS：`0.007 ns`，Vivado 报告显示约束满足。
   - 资源：CLB LUTs `5705`，CLB Registers `3674`，Block RAM Tile `178.5`，DSP `1`。

5. 复核 X4 `IMG_W=4` Vivado 实现结果：
   - bitstream：`vivado/bitstreams/jfs_full_span_x4_4x4.bit`。
   - timing：`vivado/reports/jtag_full_span_x4_4x4_timing_impl.rpt`。
   - utilization：`vivado/reports/jtag_full_span_x4_4x4_utilization_impl.rpt`。
   - WNS：`14.606 ns`，WHS：`0.010 ns`，Vivado 报告显示约束满足。
   - 资源：CLB LUTs `5717`，CLB Registers `3684`，Block RAM Tile `184.5`，DSP `1`。

6. 恢复当前默认 RTL 配置为 X4：
   - 执行 `scripts/export_official_span_x4_to_rtl.ps1`，重新导出官方 SPAN X4 的 44 个张量。
   - 复测命令：`powershell -ExecutionPolicy Bypass -File scripts\compare_span_frame_engine_smoke.ps1 -ImgW 4`。
   - 复测结果：`PASS compare_span_frame_engine_smoke_x4_4x4: 768 bytes match`。

7. 新增详细记录：
   - `docs/design/full_span_board_verification_2026_06_11.md`。

8. 新增板级输出复测脚本：
   - `scripts/compare_jtag_full_span_output.ps1`。
   - X4 4x4 复测：`PASS compare_jtag_full_span_output_x4_4x4: 768 bytes match`。
   - X2 4x4 复测：`PASS compare_jtag_full_span_output_x2_4x4: 192 bytes match`。

9. 将 JTAG 上板输入从固定色块扩展为真实 PNG 图像块：
   - 重写 `scripts/run_jtag_full_span_smoke.ps1`，新增 `-InputPng`、`-InputRaw`、`-OutputRaw`、`-OutputPng` 参数。
   - 修复默认色块生成中 R 通道赋值被旧乱码注释吞掉的问题。
   - 测试图像：`external/SPAN/test_scripts/data/baboon.png`。
   - X4 4x4 实图上板：输出 `board_runs/full_span_jtag_smoke/baboon_x4_4x4_out.png`，并通过 `PASS compare_jtag_full_span_output_x4_4x4: 768 bytes match`。
   - X2 4x4 实图上板：输出 `board_runs/full_span_jtag_smoke/baboon_x2_4x4_out.png`，并通过 `PASS compare_jtag_full_span_output_x2_4x4: 192 bytes match`。
   - 新增 `tools/make_sr_preview.py`，生成 X2/X4 板上输出对比图：`board_runs/full_span_jtag_smoke/baboon_x2_x4_preview.png`。

当前结论：完整官方 SPAN 的 X2/X4 小图功能验证已经完成到实际板级 JTAG smoke，且板上输出与同输入固定点参考逐字节一致。当前仍属于小图功能验证阶段，后续要继续扩展到 SD/PS 或更高吞吐输入输出链路，逐步扩大图像尺寸并验证真实图像/视频显示效果。

### 2026-06-11 完整官方 SPAN X4 8x8 上板扩展验证

1. 完成 X4 `IMG_W=8` JTAG full SPAN Vivado bitstream：
   - bitstream：`vivado/bitstreams/jfs_full_span_x4_8x8.bit`
   - timing：`vivado/reports/jtag_full_span_x4_8x8_timing_impl.rpt`
   - utilization：`vivado/reports/jtag_full_span_x4_8x8_utilization_impl.rpt`
   - WNS：`14.550 ns`，WHS：`0.012 ns`，Vivado 报告显示约束满足。
   - 资源：CLB LUTs `6461`，CLB Registers `3767`，Block RAM Tile `184.5`，DSP `1`。
2. 完成 X4 `8x8 -> 32x32` 真实 PNG 输入 JTAG 上板验证：
   - 输入：`external/SPAN/test_scripts/data/baboon.png` 缩放为 `8x8` RGB888，共 `64` 个输入像素。
   - 输出：`board_runs/full_span_jtag_smoke/output_x4_8x8.rgb` 和 `board_runs/full_span_jtag_smoke/baboon_x4_8x8_out.png`。
   - 板上计数：`Input counter : 64`，`Output counter: 1024`，`Error flags : 0x00000000`。
   - 同输入固定点参考比较：`PASS compare_jtag_full_span_output_x4_8x8: 3072 bytes match`。

当前结论：完整官方 SPAN X4 已从 4x4 小图扩展到 `8x8 -> 32x32` 真实 PNG 图像块，上板输出继续与固定点参考逐字节一致。下一步可以继续尝试 X4 `16x16 -> 64x64`，或转向 SD/PS 数据通路以减少 JTAG 小图链路的吞吐限制。
### 2026-06-11 SPAN 色彩通道与 PixelShuffle 修复

1. 定位色彩异常根因：
   - RGB 输入链路本身保持 `R,G,B` 顺序：PNG/raw、JTAG 写入、AXI-Lite 端点、frame engine 输入拆包均未发现 BGR 交换。
   - 真正问题在 PixelShuffle 通道解释：旧 RTL 与旧 Python 固定点参考都按 `subpixel * 3 + color` 解释 upsampler 输出。
   - 官方 PyTorch `nn.PixelShuffle` 应按 `color * scale * scale + subpixel` 解释。
   - 因为 RTL 和参考同错，旧板测仍能逐字节匹配，但视觉颜色会不对。

2. 完成修复：
   - `tools/span_official_fixed_ref.py` 的 `pixelshuffle()` 改为 PyTorch PixelShuffle 通道顺序。
   - `rtl/span/span_official_frame_engine.v` 的 `write_up_mem` 改为 `color = out_ch / UP_SUBPIXELS`，`sub = out_ch % UP_SUBPIXELS`。

3. 增加每次测试对比图能力：
   - 新增 `tools/make_sr_validation_preview.py`，生成 Input / Reference / Actual / Diff 四面板对比图。
   - `scripts/compare_jtag_full_span_output.ps1` 现在会生成 board PNG 和 validation preview。
   - `scripts/compare_span_frame_engine_smoke.ps1` 现在会生成 RTL PNG 和 validation preview。
   - `scripts/run_jtag_full_span_smoke.ps1` 在硬件输出成功后自动调用比较脚本，后续每次板测都会留下对比图。

4. 完成无板与历史输出验证：
   - 用修复后的参考重新比较旧 X4 8x8 板测输出，出现 `JTAG full SPAN output mismatch count: 2660`，证明旧 bitstream 确实存在 PixelShuffle 顺序问题。
   - X4 RTL smoke 修复后通过：`PASS compare_span_frame_engine_smoke_x4_4x4: 768 bytes match`。
   - X2 RTL smoke 修复后通过：`PASS compare_span_frame_engine_smoke_x2_4x4: 192 bytes match`。
   - X2 RTL 对比图：`build/span_validation_preview_x2_4x4.png`。

5. 完成修复版 X4 8x8 bitstream 与板测闭环：
   - bitstream：`vivado/bitstreams/jfs_full_span_x4_8x8.bit`。
   - timing：WNS `14.511 ns`，WHS `0.016 ns`，约束满足。
   - 资源：CLB LUTs `6444`，CLB Registers `3769`，Block RAM Tile `184.5`，DSP `1`。
   - 修复版 X4 8x8 板测：`Input counter : 64`，`Output counter: 1024`，`Error flags : 0x00000000`。
   - 比较结果：`PASS compare_jtag_full_span_output_x4_8x8: 3072 bytes match`。
   - 对比图：`board_runs/full_span_jtag_smoke/compare_x4_8x8_pixelshuffle_fixed/validation_preview_x4_8x8.png`。

6. 当前无板状态下已完成 X2 4x4 修复版 bitstream 生成，但未执行 JTAG 上板测试：
   - bitstream：`vivado/bitstreams/jfs_full_span_x2_4x4.bit`。
   - 后续接板后运行 `scripts/run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 4 -InputPng external\SPAN\test_scripts\data\baboon.png`，脚本会自动生成对比图。

7. GitHub 存档状态：
   - 当前仓库 `git remote -v` 为空，尚不能 push 到 GitHub。
   - 需要配置远端后，才能按“每完成一个规模提交并推送”的节奏归档。
### 2026-06-11 修复版 X2 4x4 上板验证补充

1. 板卡重新连接后，完成修复版 X2 `4x4 -> 8x8` JTAG 实图验证：
   - 命令：`powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 4 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x2_4x4_pixelshuffle_fixed_out.png`。
   - bitstream：`vivado/bitstreams/jfs_full_span_x2_4x4.bit`。
   - 板上计数：`Input counter : 16`，`Output counter: 64`。
   - 错误标志：`Error flags : 0x00000000`。
   - 输出：`board_runs/full_span_jtag_smoke/output_x2_4x4.rgb`，共 `192 bytes`。
   - 比较结果：`PASS compare_jtag_full_span_output_x2_4x4: 192 bytes match`。
   - 对比图：`board_runs/full_span_jtag_smoke/compare_x2_4x4/validation_preview_x2_4x4.png`。
2. 修复版 X2 `IMG_W=4` Vivado 实现结果：
   - WNS：`12.909 ns`，WHS：`0.017 ns`，Vivado 报告显示约束满足。
   - 资源：CLB LUTs `5681`，CLB Registers `3673`，Block RAM Tile `178.5`，DSP `1`。
3. 当前状态：修复后的 PixelShuffle 通道顺序已在 X2 4x4 和 X4 8x8 板测中闭环；后续每次测试会自动生成 Input / Reference / Board / Diff 对比图。
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

### 2026-06-12 X4 32x32 board validation attempt - FAILED / in progress

1. Generated a new X4 `IMG_W=32` JTAG full SPAN bitstream with the validation path configured as raw SPAN output:
   - bitstream: `vivado/bitstreams/jfs_full_span_x4_32x32.bit`
   - timing report: `vivado/reports/jtag_full_span_x4_32x32_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x4_32x32_utilization_impl.rpt`
   - WNS: `13.099 ns`, WHS: `0.003 ns`; Vivado reports all user timing constraints met.
   - resources: CLB Registers `3925`, Block RAM Tile `275`, DSPs `4`.
2. Disabled validation-time video brightness post-processing in the full-span JTAG/SD BD path:
   - `sr_jtag_rgb_transfer_endpoint` and `sr_sd_axi_lite_accel` now pass `VIDEO_GAIN_EN` into `sr_super_resolution_pipeline`.
   - `create_vivado_jtag_full_span_bd_project.tcl` and `create_vivado_sd_full_span_bd_project.tcl` set `CONFIG.VIDEO_GAIN_EN {0}` for full-span validation designs.
3. Ran real PNG JTAG board validation with the current image `external/SPAN/test_scripts/data/baboon.png` resized to `32x32`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 32 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputPng board_runs\full_span_jtag_smoke\baboon_x4_32x32_pixelshuffle_fixed_out.png`
   - input counter: `1024`
   - output counter: `16384`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x4_32x32.rgb` (`49152 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x4_32x32_pixelshuffle_fixed_out.png`
4. Fixed-point reference comparison failed. The board output was saturated to `0x7F` for all `49152` bytes, while the reference starts with low fixed-point values.
   - result: `JTAG full SPAN output mismatch count: 49152`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x4_32x32_current_after_videogain_off/validation_preview_x4_32x32.png`
5. Ran an additional all-black `32x32` diagnostic frame using the same programmed bitstream; it also returned all `0x7F`, so the failure is not image-content-specific.
   - diagnostic input: `board_runs/full_span_jtag_smoke/input_x4_32x32_black.rgb`
   - diagnostic output: `board_runs/full_span_jtag_smoke/output_x4_32x32_black.rgb`
   - diagnostic preview: `board_runs/full_span_jtag_smoke/compare_x4_32x32_black/validation_preview_x4_32x32.png`

Conclusion: X4 `32x32 -> 128x128` is NOT validated yet. JTAG transfer and counters are complete, but the full SPAN frame engine or its synthesized storage/address path saturates at `IMG_W=32`. Keep X4 `16x16` as the largest passing X4 board result until the 32x32 engine issue is fixed.

### 2026-06-12 X4 32x32 banked RAM board validation - PASSED

1. Fixed the X4 `IMG_W=32` hardware failure by avoiding deep BRAM cascade inference in `span_sync_ram_1r1w`:
   - `span_official_frame_engine` now rounds frame-engine feature/output RAM depths up to a power of two.
   - `span_sync_ram_1r1w` now splits RAMs deeper than `4096` entries into independent 4K physical banks selected by the high address bits.
   - This keeps the one-read/one-write synchronous RAM interface unchanged while avoiding the problematic single deep 16K RAM inference seen only at `IMG_W=32`.
2. Regenerated the X4 `IMG_W=32` JTAG full SPAN bitstream.
   - bitstream: `vivado/bitstreams/jfs_full_span_x4_32x32.bit`
   - timing report: `vivado/reports/jtag_full_span_x4_32x32_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x4_32x32_utilization_impl.rpt`
   - WNS: `12.959 ns`, WHS: `0.005 ns`; Vivado reports all user timing constraints met.
   - resources: CLB LUTs `7753`, CLB Registers `4015`, Block RAM Tile `307`, DSPs `4`.
   - synthesis: `0` errors, `0` critical warnings; the earlier BRAM depth/cascade warning is gone.
3. Ran real PNG JTAG board validation with `external/SPAN/test_scripts/data/baboon.png` resized to `32x32`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 4 -ImgW 32 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputRaw board_runs\full_span_jtag_smoke\output_x4_32x32_banked_ram.rgb -OutputPng board_runs\full_span_jtag_smoke\baboon_x4_32x32_banked_ram_out.png`
   - input counter: `1024`
   - output counter: `16384`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x4_32x32_banked_ram.rgb` (`49152 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x4_32x32_banked_ram_out.png`
4. Fixed-point reference comparison passed byte-for-byte.
   - result: `PASS compare_jtag_full_span_output_x4_32x32: 49152 bytes match`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x4_32x32_banked_ram/validation_preview_x4_32x32.png`

Conclusion: X4 `32x32 -> 128x128` board output now matches the fixed-point reference byte-for-byte. The color-channel order remains validated by the exact raw-byte comparison and by the generated Input / Reference / Board / Diff preview.

### 2026-06-12 X2 32x32 banked RAM board validation - PASSED

1. Regenerated the X2 `IMG_W=32` JTAG full SPAN bitstream with the banked RAM storage fix already in place.
   - bitstream: `vivado/bitstreams/jfs_full_span_x2_32x32.bit`
   - timing report: `vivado/reports/jtag_full_span_x2_32x32_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x2_32x32_utilization_impl.rpt`
   - WNS: `14.254 ns`, WHS: `0.024 ns`; Vivado reports all user timing constraints met.
   - resources: CLB LUTs `7697`, CLB Registers `3973`, Block RAM Tile `292`, DSPs `4`.
   - synthesis: `0` errors, `0` critical warnings; no BRAM depth/cascade warning.
2. Ran real PNG JTAG board validation with `external/SPAN/test_scripts/data/baboon.png` resized to `32x32`.
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_jtag_full_span_smoke.ps1 -Scale 2 -ImgW 32 -InputPng external\SPAN\test_scripts\data\baboon.png -OutputRaw board_runs\full_span_jtag_smoke\output_x2_32x32_banked_ram.rgb -OutputPng board_runs\full_span_jtag_smoke\baboon_x2_32x32_banked_ram_out.png`
   - input counter: `1024`
   - output counter: `4096`
   - error flags: `0x00000000`
   - output raw: `board_runs/full_span_jtag_smoke/output_x2_32x32_banked_ram.rgb` (`12288 bytes`)
   - output png: `board_runs/full_span_jtag_smoke/baboon_x2_32x32_banked_ram_out.png`
3. Fixed-point reference comparison passed byte-for-byte.
   - result: `PASS compare_jtag_full_span_output_x2_32x32: 12288 bytes match`
   - comparison preview: `board_runs/full_span_jtag_smoke/compare_x2_32x32_banked_ram/validation_preview_x2_32x32.png`

Conclusion: X2 `32x32 -> 64x64` board output matches the fixed-point reference byte-for-byte. This gives matching, color-channel-checked board results for both X2 and X4 at `IMG_W=32` using the current official image.

### 2026-06-12 video realtime planning and 40MHz clock ramp - PASSED

1. Reframed the next project stage from single-image validation to realtime video super-resolution.
   - First practical realtime target: `30 fps`.
   - Later smooth-video target: `60 fps`.
   - Typical display pixel clocks: `1280x720@60` and `1920x1080@30` use about `74.25 MHz`; `1920x1080@60` uses about `148.5 MHz`.
2. Added a throughput estimator for the current sequential full SPAN frame engine:
   - script: `tools/estimate_span_video_perf.py`
   - note: `docs/design/video_realtime_perf_estimate_2026_06_12.md`
   - Current X4 engine estimate: `1,276,752` cycles per LR input pixel.
   - Current X2 engine estimate: `1,230,060` cycles per LR input pixel.
3. Key realtime estimates at `150 MHz`:
   - X4 `32x32 -> 128x128`: about `0.115 fps`; needs about `261.5x` speedup for `30 fps`.
   - X4 `320x180 -> 1280x720`: about `0.002 fps`; needs about `14708.7x` speedup for `30 fps`.
   - X2 `640x360 -> 1280x720`: about `0.00053 fps`; needs about `56681.8x` speedup for `30 fps`.
4. Ran the first real clock-ramp implementation point for X4 `IMG_W=32`:
   - command: `powershell -ExecutionPolicy Bypass -File scripts\run_vivado_jtag_full_span_freq_sweep.ps1 -Scale 4 -ImgW 32 -FrequenciesMhz 40 -StopOnFailure`
   - result CSV: `vivado/reports/jtag_full_span_x4_32x32_freq_sweep.csv`
   - timing report: `vivado/reports/jtag_full_span_x4_32x32_f40m_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x4_32x32_f40m_utilization_impl.rpt`
   - local bitstream: `vivado/bitstreams/jfs_full_span_x4_32x32_f40m.bit`
   - reported `clk_pl_0`: `40 MHz`
   - WNS: `6.289 ns`, TNS: `0`, WHS: `0.015 ns`; Vivado reports all user timing constraints met.

Conclusion: the existing byte-exact SPAN validation engine can pass `40 MHz`, and `50 MHz` is a reasonable next timing experiment. However, realtime video cannot be achieved by frequency ramp alone. The next architecture work should keep official SPAN as the correctness/quality reference and create a video-oriented lightweight/parallel datapath with many MAC lanes, registered BRAM boundaries, and a streaming video shell.

### 2026-06-12 X4 32x32 50MHz clock ramp - PASSED

1. Ran the next clock-ramp implementation point for X4 `IMG_W=32`.
   - command: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_vivado_jtag_full_span_freq_sweep.ps1 -Scale 4 -ImgW 32 -FrequenciesMhz 50 -StopOnFailure -OutCsv vivado\reports\jtag_full_span_x4_32x32_f50m_freq_sweep.csv`
   - result CSV: `vivado/reports/jtag_full_span_x4_32x32_f50m_freq_sweep.csv`
   - timing report: `vivado/reports/jtag_full_span_x4_32x32_f50m_timing_impl.rpt`
   - utilization report: `vivado/reports/jtag_full_span_x4_32x32_f50m_utilization_impl.rpt`
   - local bitstream: `vivado/bitstreams/jfs_full_span_x4_32x32_f50m.bit`
2. Vivado timing passed at reported `clk_pl_0 = 50 MHz`.
   - WNS: `2.825 ns`
   - TNS: `0`
   - WHS: `0.020 ns`
   - clock period: `20.000 ns`
3. Resource use remains essentially unchanged from the 25/40 MHz builds.
   - CLB LUTs: `7749`
   - CLB Registers: `4015`
   - DSPs: `4`

Conclusion: X4 `32x32 -> 128x128` still closes timing at `50 MHz`, with about `2.825 ns` setup margin remaining. This confirms there is modest frequency headroom for the current validation core, but the realtime-video gap is still architectural rather than clock-only.

### 2026-06-12 CUDA SPAN video prototype - PASSED

1. Confirmed the local GPU software path is usable for realtime prototyping.
   - GPU: `NVIDIA GeForce RTX 3060 Laptop GPU`
   - PyTorch CUDA: available
   - preferred prototype dtype: FP16 via `--half`
2. Added a reusable GPU benchmark and preview tool:
   - script: `tools/run_span_gpu_realtime.py`
   - note: `docs/design/video_gpu_realtime_prototype_2026_06_12.md`
   - supported inputs: image, image directory, video file
   - generated outputs per run: input PNG, bicubic PNG, SPAN GPU PNG, optional MP4, `metrics.json`, and a side-by-side comparison PNG
3. Ran the official SPAN X4 checkpoint on the current official `baboon.png` image.
   - command: `python tools\run_span_gpu_realtime.py --scale 4 --input external\SPAN\test_scripts\data\baboon.png --width 160 --height 160 --out-dir runs\span_gpu_realtime\baboon_x4_160_fp16 --half --warmup 5 --repeat 30 --tile 220`
   - LR input: `160x160`
   - SR output: `640x640`
   - measured throughput: `52.059 fps`
   - latency: `19.209 ms/frame`
   - comparison image: `runs/span_gpu_realtime/baboon_x4_160_fp16/baboon_comparison_x4.png`
4. Ran a video-input smoke test through the same tool.
   - input video: `runs\span_gpu_realtime\baboon_x4_160_fp16\baboon_span_gpu_x4.mp4`
   - measured throughput: `55.037 fps`
   - latency: `18.169 ms/frame`
   - comparison image: `runs/span_gpu_realtime/baboon_video_smoke_x4_160_fp16/baboon_span_gpu_x4_comparison_x4.png`

Conclusion: the CUDA prototype can run the current official SPAN X4 model at about realtime for `160x160 -> 640x640` frames on this GPU. This becomes the software quality/FPS reference while the FPGA implementation is redesigned from the current byte-exact sequential validation core into a parallel video datapath.

### 2026-06-12 GPU 720p realtime benchmark - PARTIAL PASS

1. Added practical CUDA inference optimization switches to `tools/run_span_gpu_realtime.py`.
   - `--channels-last` for CUDA NHWC/channels-last tensors and model weights
   - `--tf32` for FP32 CUDA TF32 kernels
   - `--compile` for optional `torch.compile(..., mode="reduce-overhead")`
   - cuDNN benchmark is enabled by the tool for repeated video-frame shapes.
2. Ran a 720p software-demo target with official SPAN X4.
   - command: `python tools\run_span_gpu_realtime.py --scale 4 --input external\SPAN\test_scripts\data\baboon.png --width 320 --height 180 --out-dir runs\span_gpu_realtime\baboon_x4_320x180_fp16 --half --warmup 5 --repeat 15 --tile 240`
   - LR input: `320x180`
   - SR output: `1280x720`
   - measured throughput: `38.394 fps`
   - latency: `26.046 ms/frame`
   - comparison image: `runs/span_gpu_realtime/baboon_x4_320x180_fp16/baboon_comparison_x4.png`
3. Ran a 720p software-demo target with official SPAN X2.
   - command: `python tools\run_span_gpu_realtime.py --scale 2 --input external\SPAN\test_scripts\data\baboon.png --width 640 --height 360 --out-dir runs\span_gpu_realtime\baboon_x2_640x360_fp16 --half --warmup 3 --repeat 8 --tile 240`
   - LR input: `640x360`
   - SR output: `1280x720`
   - measured throughput: `26.526 fps`
   - latency: `37.698 ms/frame`
   - comparison image: `runs/span_gpu_realtime/baboon_x2_640x360_fp16/baboon_comparison_x2.png`
4. Wrote benchmark note and summary CSV:
   - note: `docs/design/video_gpu_720p_benchmark_2026_06_12.md`
   - CSV: `runs/span_gpu_realtime/profile_summary_2026_06_12.csv`

Conclusion: for a software video demonstration, the current best route is official SPAN X4 with `320x180` input to `1280x720` output, which clears the `30 fps` realtime target on the RTX 3060 Laptop GPU. X2 `640x360 -> 1280x720` is close but not yet realtime at 30 fps. The FPGA target is still not complete; these GPU measurements define the next hardware throughput and quality target.

### 2026-06-12 end-to-end CUDA video stream - NEAR 720p30

1. Added a real streaming video pipeline:
   - script: `tools/run_span_video_stream.py`
   - note: `docs/design/video_streaming_pipeline_2026_06_12.md`
   - inputs: video file, still image as repeated frames, still image with synthetic pan motion
   - outputs: MP4 video, `metrics.json`, first-frame input/bicubic/SPAN comparison PNG
2. Ran an initial X4 `320x180 -> 1280x720` 60-frame stream with FP16.
   - source: `external/SPAN/test_scripts/data/baboon.png`
   - motion mode: enabled
   - result before output-path optimization: `16.691 fps`
   - bottleneck: PIL/float CPU postprocess path at `22.064 ms/frame`
3. Optimized streaming postprocess.
   - previous path: convert tensor to float CPU/PIL image, then to OpenCV BGR
   - new path: quantize tensor to `uint8` on GPU, transfer one contiguous RGB array, then encode with OpenCV
   - postprocess improved from `22.064 ms/frame` to `1.079 ms/frame`
4. Re-ran the same stream after optimization.
   - command: `python tools\run_span_video_stream.py --scale 4 --input external\SPAN\test_scripts\data\baboon.png --width 320 --height 180 --frames 60 --fps 30 --motion --out-dir runs\span_video_stream\baboon_x4_320x180_60f_fp16_fastpost --half --preview-tile 240`
   - end-to-end throughput: `29.861 fps`
   - end-to-end latency: `33.488 ms/frame`
   - inference: `24.420 ms/frame`
   - preprocess: `1.754 ms/frame`
   - postprocess: `1.079 ms/frame`
   - encode: `5.876 ms/frame`
   - output video: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_fastpost/baboon_span_stream_x4.mp4`
   - metrics: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_fastpost/metrics.json`
   - comparison image: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_fastpost/baboon_stream_comparison_x4.png`
5. Tested channels-last on the same stream.
   - channels-last FP16 result: `27.444 fps`
   - conclusion: keep ordinary NCHW FP16 for this SPAN checkpoint and RTX 3060 Laptop GPU.

Conclusion: the CUDA software path is now effectively at the X4 720p30 video-demo target including output encoding (`29.861 fps` versus the ideal `30 fps`). The FPGA realtime implementation is still not done, but the software reference is now a concrete end-to-end target rather than only a single-frame inference estimate.

### 2026-06-12 async CUDA video writer - 720p30 PASSED

1. Added asynchronous MP4 writing to `tools/run_span_video_stream.py`.
   - option: `--async-writer`
   - queue depth option: `--writer-queue`
   - purpose: overlap OpenCV MP4 encoding with the next frame's preprocessing, CUDA inference, and postprocess.
2. Re-ran the 60-frame X4 `320x180 -> 1280x720` FP16 stream with async writer.
   - command: `python tools\run_span_video_stream.py --scale 4 --input external\SPAN\test_scripts\data\baboon.png --width 320 --height 180 --frames 60 --fps 30 --motion --out-dir runs\span_video_stream\baboon_x4_320x180_60f_fp16_async_writer --half --async-writer --preview-tile 240`
   - end-to-end throughput: `34.581 fps`
   - end-to-end latency: `28.917 ms/frame`
   - inference: `25.196 ms/frame`
   - postprocess: `1.130 ms/frame`
   - async encode work: `6.320 ms/frame`
   - metrics: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_async_writer/metrics.json`
   - comparison image: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_async_writer/baboon_stream_comparison_x4.png`
3. Ran a longer 180-frame stability check with the same settings.
   - command: `python tools\run_span_video_stream.py --scale 4 --input external\SPAN\test_scripts\data\baboon.png --width 320 --height 180 --frames 180 --fps 30 --motion --out-dir runs\span_video_stream\baboon_x4_320x180_180f_fp16_async_writer --half --async-writer --preview-tile 240`
   - end-to-end throughput: `41.218 fps`
   - end-to-end latency: `24.261 ms/frame`
   - inference: `21.125 ms/frame`
   - postprocess: `0.893 ms/frame`
   - async encode work: `6.901 ms/frame`
   - OpenCV readback: `180` frames, `30.0 fps`, `1280x720`
   - metrics: `runs/span_video_stream/baboon_x4_320x180_180f_fp16_async_writer/metrics.json`
   - comparison image: `runs/span_video_stream/baboon_x4_320x180_180f_fp16_async_writer/baboon_stream_comparison_x4.png`

Conclusion: the CUDA software video path now exceeds the X4 720p30 realtime target end-to-end, including MP4 output. This is a software reference and demo path; the FPGA realtime datapath remains a separate implementation task.

### 2026-06-12 FPGA realtime hardware sizing

1. Added a parallel hardware sizing estimator:
   - script: `tools/estimate_span_parallel_hardware.py`
   - note: `docs/design/span_realtime_hardware_sizing_2026_06_12.md`
   - summary CSV: `runs/span_hardware_estimates/summary_2026_06_12.csv`
2. Estimated full official SPAN X4 `320x180 -> 1280x720 @30` at `150 MHz`.
   - MACs per LR input pixel: `425232`
   - MACs per frame: `24493363200`
   - required compute: `734.801 GMAC/s`
   - required MAC lanes: `4899`
   - rough DSP estimate: `4899` DSPs at `1 MAC/DSP`, or `2450` DSPs at `2 MAC/DSP`
3. Estimated full official SPAN X4 `320x180 -> 1280x720 @60` at `150 MHz`.
   - required compute: `1469.602 GMAC/s`
   - required MAC lanes: `9798`
4. Estimated full official SPAN X2 `640x360 -> 1280x720 @30` at `150 MHz`.
   - required compute: `2831.708 GMAC/s`
   - required MAC lanes: `18879`
   - conclusion: X2 720p is not easier than X4 320x180 input because it processes 4x more LR pixels.
5. Estimated lightweight X4 `320x180 -> 1280x720 @30` candidates at `150 MHz`.
   - C16/B3: `362` MAC lanes required; `512` candidate lanes gives about `42.452 fps`.
   - C16/B6: `601` MAC lanes required; `768` candidate lanes gives about `38.355 fps`.
   - C24/B3: `751` MAC lanes required; `1024` candidate lanes gives about `40.925 fps`.
   - C32/B3: `1279` MAC lanes required; `2048` candidate lanes gives about `48.072 fps`.

Conclusion: the full official SPAN model should remain the quality/correctness oracle, not the first realtime FPGA target. The practical next hardware target is a distilled/lightweight X4 model, starting with C16/B3 at `512` MAC lanes or C24/B3 at `1024` MAC lanes for `320x180 -> 1280x720 @30`.

### 2026-06-12 TinySPAN realtime distillation path

1. Updated `train/span_model.py` so TinySPAN supports fewer than 6 SPAB blocks.
   - 6-block behavior remains compatible with the previous model.
   - Smaller students use the first block output, deepest available block output, and fused tail in the concat path.
2. Added official-to-lightweight distillation:
   - script: `train/distill_tinyspan_from_official.py`
   - config: `configs/distill_tinyspan_x4_c16_b3.json`
   - note: `docs/design/tinyspan_distillation_realtime_plan_2026_06_12.md`
3. Ran a smoke distillation test for the first FPGA candidate, X4 C16/B3.
   - command: `python train\distill_tinyspan_from_official.py --scale 4 --channels 16 --num-blocks 3 --patch-size 128 --batch-size 1 --epochs 1 --max-steps 10 --train-hr external\SPAN\test_scripts\data --output runs\tinyspan_distill\smoke_x4_c16_b3_baboon --amp`
   - dataset: official `baboon.png` smoke image
   - executed steps: `1`
   - student parameters: `125792`
   - step loss: `0.03869177`
   - distill loss: `0.02133024`
   - teacher PSNR vs HR crop: `20.113368 dB`
   - student PSNR vs HR crop: `19.607937 dB`
   - preview: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/distill_preview.png`
   - checkpoint: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/student_last.pt`
4. Verified RTL export for the C16/B3 student checkpoint.
   - command: `python train\export_tinyspan_to_rtl.py --checkpoint runs\tinyspan_distill\smoke_x4_c16_b3_baboon\student_last.pt --scale 4 --channels 16 --num-blocks 3 --output-dir runs\tinyspan_distill\smoke_x4_c16_b3_baboon\rtl_export`
   - manifest: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/rtl_export/tinyspan_manifest.json`
   - config header: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/rtl_export/tinyspan_model_config.vh`

Conclusion: the project now has a concrete training path for the first practical FPGA realtime candidate: official SPAN X4 teacher -> TinySPAN X4 C16/B3 student -> INT8 RTL export. The smoke run proves the flow; the next substantial task is full REDS/video-frame distillation and quality validation against the official SPAN GPU reference.
