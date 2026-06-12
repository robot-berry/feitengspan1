# Video GPU realtime prototype

Date: 2026-06-12

Purpose: keep a fast software reference for the next video super-resolution stage. The FPGA RTL remains the hardware target, but the CUDA path lets us measure achievable model throughput and generate a comparison image for every test run.

## Tool

Added:

- `tools/run_span_gpu_realtime.py`

The tool loads the official exported SPAN checkpoint through the existing manifest:

- X4 manifest: `rtl/generated/official_span_x4/official_span_manifest.json`
- X4 checkpoint: `runs/official_span/official_SPAN_REDS_x4_f48/models/net_g_latest.pth`
- X2 manifest: `rtl/generated/official_span_x2/official_span_manifest.json`
- X2 checkpoint: `runs/official_span/official_SPAN_REDS_x2_f48/models/net_g_latest.pth`

It supports:

- image input
- image-directory input
- video input through OpenCV
- CUDA or CPU device selection
- FP16 CUDA inference with `--half`
- output PNG frames, optional output MP4, `metrics.json`, and a side-by-side comparison PNG

## Command

```powershell
python tools\run_span_gpu_realtime.py `
  --scale 4 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 160 `
  --height 160 `
  --out-dir runs\span_gpu_realtime\baboon_x4_160_fp16 `
  --half `
  --warmup 5 `
  --repeat 30 `
  --tile 220
```

## Result

Hardware:

- GPU: NVIDIA GeForce RTX 3060 Laptop GPU
- VRAM: 6144 MiB
- PyTorch: CUDA build available (`torch.cuda.is_available() == True`)

X4 official SPAN FP16 run:

- LR input: `160x160`
- SR output: `640x640`
- measured throughput: `52.059 fps`
- measured latency: `19.209 ms/frame`
- comparison image: `runs/span_gpu_realtime/baboon_x4_160_fp16/baboon_comparison_x4.png`
- metrics: `runs/span_gpu_realtime/baboon_x4_160_fp16/metrics.json`

Video input smoke:

- input video: `runs/span_gpu_realtime/baboon_x4_160_fp16/baboon_span_gpu_x4.mp4`
- LR input after resize: `160x160`
- SR output: `640x640`
- measured throughput: `55.037 fps`
- measured latency: `18.169 ms/frame`
- comparison image: `runs/span_gpu_realtime/baboon_video_smoke_x4_160_fp16/baboon_span_gpu_x4_comparison_x4.png`

## Interpretation

The GPU prototype can already run the current official SPAN X4 model around realtime for a `160x160 -> 640x640` frame size on this RTX 3060 Laptop GPU. This gives a practical software path for previewing video quality and collecting FPS baselines.

This does not change the FPGA conclusion: the current byte-exact sequential RTL validation engine is far too slow for realtime video by clock frequency alone. The GPU run should be used as the quality and throughput reference while the FPGA datapath is redesigned toward a video-oriented parallel architecture.
