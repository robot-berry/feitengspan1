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
- optional async video writer via `--async-writer`

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
  --async-writer `
  --preview-tile 240
```

## Result

Streaming X4 `320x180 -> 1280x720`, FP16, async writer, 60 synthetic motion frames:

- end-to-end FPS: `34.581`
- end-to-end latency: `28.917 ms/frame`
- inference: `25.196 ms/frame`
- preprocess: `2.065 ms/frame`
- postprocess: `1.130 ms/frame`
- async encode work: `6.320 ms/frame`
- output video: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_async_writer/baboon_span_stream_x4.mp4`
- metrics: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_async_writer/metrics.json`
- comparison: `runs/span_video_stream/baboon_x4_320x180_60f_fp16_async_writer/baboon_stream_comparison_x4.png`

Stability run with 180 synthetic motion frames:

- end-to-end FPS: `41.218`
- end-to-end latency: `24.261 ms/frame`
- inference: `21.125 ms/frame`
- preprocess: `1.974 ms/frame`
- postprocess: `0.893 ms/frame`
- async encode work: `6.901 ms/frame`
- output video verified by OpenCV: `180` frames, `30.0 fps`, `1280x720`
- output video: `runs/span_video_stream/baboon_x4_320x180_180f_fp16_async_writer/baboon_span_stream_x4.mp4`
- metrics: `runs/span_video_stream/baboon_x4_320x180_180f_fp16_async_writer/metrics.json`
- comparison: `runs/span_video_stream/baboon_x4_320x180_180f_fp16_async_writer/baboon_stream_comparison_x4.png`

## Optimization found

The first streaming implementation converted the model output through a PIL/float CPU path. That made postprocess cost about `22.064 ms/frame`, and the whole pipeline only reached `16.691 fps`.

The optimized path quantizes the tensor to `uint8` on GPU, transfers one contiguous RGB array to CPU, and passes it directly to OpenCV. That reduced postprocess to `1.079 ms/frame` and improved end-to-end throughput to `29.861 fps`.

The async writer then overlaps MP4 encoding with the next frame's preprocessing/inference/postprocess. That lifted the same 60-frame stream from `29.861 fps` to `34.581 fps`.

Channels-last was tested for the same stream and was slower on this model/GPU:

- NCHW FP16: `29.861 fps`
- channels-last FP16: `27.444 fps`

## Interpretation

The CUDA software pipeline now exceeds the 720p30 demo target for X4 `320x180 -> 1280x720`, including output encoding. The best verified end-to-end run is `41.218 fps` on a 180-frame stream.

This still does not complete the FPGA realtime goal. It does prove a practical software reference path and gives concrete timing targets for the hardware video datapath:

- X4 720p30 total budget: `33.333 ms/frame`
- current CUDA stream with async writer: `24.261 ms/frame` on the 180-frame run
- current CUDA model inference alone: `21.125 ms/frame` on the 180-frame run

## TinySPAN acceptance gate

The stream tool is now part of `tools/run_tinyspan_realtime_acceptance.py`, which also runs teacher/student quality and temporal consistency checks. The first C16/B3 smoke checkpoint gate is documented in `docs/design/tinyspan_realtime_acceptance_2026_06_12.md`.

Result for `runs/tinyspan_distill/video_smoke_x4_c16_b3_baboon/student_last.pt`:

- X4 `320x180 -> 1280x720 @30`
- end-to-end stream FPS: `65.375`
- end-to-end stream latency: `15.296 ms/frame`
- encoded-video readback: `60` frames, `30.000 fps`, `1280x720`
- gate result: `PASS`

This verifies the current lightweight software path as a realtime 720p30 demo path. Quality remains smoke-level until full video-frame distillation is run.
