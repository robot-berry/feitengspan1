# Streaming video SPAN pipeline

Date: 2026-06-12

Purpose: move from repeated single-frame FPS tests to an end-to-end video path that reads frames, preprocesses them, runs official SPAN on CUDA, postprocesses GPU output, encodes an MP4, and records per-stage timing.

## Tool

Added:

- `tools/run_span_video_stream.py`

The script reuses the official SPAN manifest/checkpoint loader from `tools/run_span_gpu_realtime.py`.

Supported source modes:

- input video file
- input image expanded into a fixed-length image sequence
- optional synthetic pan motion for image input via `--motion`

Outputs:

- MP4 video
- `metrics.json`
- first-frame input/bicubic/SPAN comparison PNG

## Command

```powershell
python tools\run_span_video_stream.py `
  --scale 4 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 320 `
  --height 180 `
  --frames 60 `
  --fps 30 `
  --motion `
  --out-dir runs\span_video_stream\baboon_x4_320x180_60f_fp16_fastpost `
  --half `
  --preview-tile 240
```

## Result

Streaming X4 `320x180 -> 1280x720`, FP16, 60 synthetic motion frames:

- end-to-end FPS: `29.861`
- end-to-end latency: `33.488 ms/frame`
- inference: `24.420 ms/frame`
- preprocess: `1.754 ms/frame`
- postprocess: `1.079 ms/frame`
- encode: `5.876 ms/frame`
- output video: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_fastpost/baboon_span_stream_x4.mp4`
- metrics: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_fastpost/metrics.json`
- comparison: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_fastpost/baboon_stream_comparison_x4.png`

## Optimization found

The first streaming implementation converted the model output through a PIL/float CPU path. That made postprocess cost about `22.064 ms/frame`, and the whole pipeline only reached `16.691 fps`.

The optimized path quantizes the tensor to `uint8` on GPU, transfers one contiguous RGB array to CPU, and passes it directly to OpenCV. That reduced postprocess to `1.079 ms/frame` and improved end-to-end throughput to `29.861 fps`.

Channels-last was tested for the same stream and was slower on this model/GPU:

- NCHW FP16: `29.861 fps`
- channels-last FP16: `27.444 fps`

## Interpretation

The CUDA software pipeline is now effectively at the 720p30 demo target for X4 `320x180 -> 1280x720`, including output encoding. The remaining gap to a stable 30+ fps is small and mostly in inference plus MP4 encoding overhead.

This still does not complete the FPGA realtime goal. It does prove a practical software reference path and gives concrete timing targets for the hardware video datapath:

- X4 720p30 total budget: `33.333 ms/frame`
- current CUDA stream: `33.488 ms/frame`
- current CUDA model inference alone: `24.420 ms/frame`
