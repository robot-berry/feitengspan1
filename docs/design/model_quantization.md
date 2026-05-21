# 模型结构、训练与量化说明

## 模型选择

调研文档建议以 SPAN 为主线，并结合 ESPCN 的低分辨率域计算和上采样思想。本工程的纯 RTL baseline 采用同一硬件友好方向：先在输入分辨率上做低成本局部残差增强，再进行流式 x2/x4 上采样。

当前 RTL baseline 的网络等价结构为：

```text
RGB888 input
  -> stream residual enhancement
  -> scale x2/x4 pixel upsampler
  -> RGB888 output
```

其中 `stream residual enhancement` 使用无乘法的局部高频增强：

```text
y = clip(x + 0.5 * (x - avg(up, left)), 0, 255)
```

该结构可作为比赛工程闭环 baseline。后续如接入训练好的 SPAN/FSRCNN/ESPCN 权重，可保持 AXI-Stream 顶层不变，将该模块替换为多层 INT8 卷积阵列。

## 训练建议

- 数据集：REDS，按赛题要求生成 x2/x4 LR-HR 图像对。
- 退化：建议叠加视频会议常见退化，包括低码率压缩、轻微模糊、噪声、人脸区域和文档文字区域。
- Teacher：可使用较大 x4 SR 模型生成软标签，对轻量模型蒸馏。
- Loss：`L1 + edge loss + text/face ROI loss`，用于兼顾 PSNR 和会议主观清晰度。

## 量化策略

- 输入/输出：RGB888，每通道 8 bit。
- 激活：uint8。
- 权重：int8。
- 累加：int32，输出前做缩放、偏置和饱和截断。
- 当前 baseline：无显式权重乘法，内部差分使用 16 bit signed 中间值，最终饱和回 uint8。

## 模型到硬件转换

`model/example_model.json` 描述模型层级、量化格式和尺度；`model/model_to_rtl.py` 可生成 RTL include 参数：

```bash
python model/model_to_rtl.py model/example_model.json -o build/model_params.vh --scale 4
```

当前 RTL 直接用参数配置尺度；训练权重接入时，可扩展 JSON 的 `layers[].weights` 字段，并由脚本生成 ROM 初始化文件或 Verilog package。
