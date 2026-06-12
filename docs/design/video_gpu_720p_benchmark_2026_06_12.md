# GPU 720p SPAN benchmark

Date: 2026-06-12

Purpose: measure whether the current official SPAN checkpoints can support a practical realtime video demo on the local RTX 3060 Laptop GPU.

## Environment

- GPU: NVIDIA GeForce RTX 3060 Laptop GPU
- PyTorch: CUDA available
- Script: `tools/run_span_gpu_realtime.py`
- Dtype: FP16 (`--half`)
- Input image: `external/SPAN/test_scripts/data/baboon.png`

## Results

| Path | LR input | SR output | FPS | Latency |
| --- | ---: | ---: | ---: | ---: |
| X4 official SPAN | `320x180` | `1280x720` | `38.394` | `26.046 ms/frame` |
| X2 official SPAN | `640x360` | `1280x720` | `26.526` | `37.698 ms/frame` |

Artifacts:

- X4 metrics: `runs/span_gpu_realtime/baboon_x4_320x180_fp16/metrics.json`
- X4 comparison: `runs/span_gpu_realtime/baboon_x4_320x180_fp16/baboon_comparison_x4.png`
- X2 metrics: `runs/span_gpu_realtime/baboon_x2_640x360_fp16/metrics.json`
- X2 comparison: `runs/span_gpu_realtime/baboon_x2_640x360_fp16/baboon_comparison_x2.png`

## Commands

```powershell
python tools\run_span_gpu_realtime.py `
  --scale 4 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 320 `
  --height 180 `
  --out-dir runs\span_gpu_realtime\baboon_x4_320x180_fp16 `
  --half `
  --warmup 5 `
  --repeat 15 `
  --tile 240
```

```powershell
python tools\run_span_gpu_realtime.py `
  --scale 2 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 640 `
  --height 360 `
  --out-dir runs\span_gpu_realtime\baboon_x2_640x360_fp16 `
  --half `
  --warmup 3 `
  --repeat 8 `
  --tile 240
```

## Interpretation

For a software video demo, X4 `320x180 -> 1280x720` is the best current route: it clears the 30 fps realtime target with margin on this GPU. X2 `640x360 -> 1280x720` is close but still below 30 fps, so it needs either a lighter model, frame skipping, smaller input, or additional runtime optimization.

Neither path reaches 60 fps yet on this GPU, and these GPU results do not imply the FPGA RTL is realtime. They define the quality/FPS target that the next FPGA video datapath should work toward.
