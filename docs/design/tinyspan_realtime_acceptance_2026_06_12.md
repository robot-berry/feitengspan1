# TinySPAN realtime acceptance gate

Date: 2026-06-12

Purpose: provide one command that checks whether a TinySPAN checkpoint is usable for the current realtime video SR target. It combines stream throughput, encoded-video readback, teacher quality, and temporal quality.

## Tool

Script: `tools/run_tinyspan_realtime_acceptance.py`

The gate runs:

1. `tools/run_span_video_stream.py`
   - verifies end-to-end stream FPS
   - writes an MP4
   - checks output dimensions
   - verifies encoded-video readback with OpenCV
2. `tools/evaluate_tinyspan_video_quality.py`
   - measures student-vs-official-SPAN PSNR/MAE
   - measures temporal delta error against the official SPAN teacher
   - writes quality preview and per-frame CSV

Outputs:

- `summary.json`
- `summary.md`
- stream `metrics.json` and preview PNG
- quality `metrics.json`, per-frame CSV, and preview PNG

## Command

```powershell
python tools\run_tinyspan_realtime_acceptance.py `
  --checkpoint runs\tinyspan_distill\video_smoke_x4_c16_b3_baboon\student_last.pt `
  --scale 4 `
  --student-channels 16 `
  --student-blocks 3 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 320 `
  --height 180 `
  --fps 30 `
  --stream-frames 60 `
  --quality-frames 30 `
  --min-fps 30 `
  --out-dir runs\tinyspan_acceptance\video_smoke_c16_b3_x4_320x180_60f `
  --half `
  --async-writer `
  --motion `
  --preview-tile 180
```

## Result

Checkpoint:

- `runs/tinyspan_distill/video_smoke_x4_c16_b3_baboon/student_last.pt`

Target:

- X4 `320x180 -> 1280x720`
- target FPS: `30`
- stream frames: `60`
- quality frames: `30`

Gate result: `PASS`

Checks:

| Check | Result | Value | Target |
| --- | --- | ---: | ---: |
| stream FPS | `PASS` | `65.375` | `>= 30.0` |
| stream output size | `PASS` | `1280x720` | `1280x720` |
| stream frame count | `PASS` | `60` | `60` |
| quality output size | `PASS` | `1280x720` | `1280x720` |
| video readback | `PASS` | `60 frames, 30.000 fps, 1280x720` | `60 frames, 1280x720` |

Stream metrics:

- end-to-end FPS: `65.375`
- end-to-end latency: `15.296 ms/frame`
- inference: `11.347 ms/frame`
- preprocess: `2.056 ms/frame`
- postprocess: `1.363 ms/frame`
- async encode work: `6.329 ms/frame`

Quality metrics against official SPAN teacher:

- mean PSNR: `29.939 dB`
- mean MAE: `0.020711`
- temporal MAE: `0.029147`
- temporal PSNR: `32.977 dB`
- teacher inference inside paired quality run: `31.227 ms/frame`
- student inference inside paired quality run: `8.303 ms/frame`

Artifacts:

- summary: `runs/tinyspan_acceptance/video_smoke_c16_b3_x4_320x180_60f/summary.md`
- stream metrics: `runs/tinyspan_acceptance/video_smoke_c16_b3_x4_320x180_60f/stream/metrics.json`
- stream preview: `runs/tinyspan_acceptance/video_smoke_c16_b3_x4_320x180_60f/stream/baboon_tinyspan_c16_b3_stream_comparison_x4.png`
- quality metrics: `runs/tinyspan_acceptance/video_smoke_c16_b3_x4_320x180_60f/quality/metrics.json`
- quality preview: `runs/tinyspan_acceptance/video_smoke_c16_b3_x4_320x180_60f/quality/baboon_tinyspan_teacher_quality_x4.png`

## Interpretation

The current TinySPAN C16/B3 smoke checkpoint passes the software realtime gate for X4 `320x180 -> 1280x720 @30fps`. This proves the lightweight model and stream pipeline can support a 720p30 video demo on GPU.

This does not mean the final quality target is complete. The checkpoint is still smoke-trained, and the quality preview shows visible high-frequency differences against the official SPAN teacher. The next quality-moving step remains full REDS or extracted-video-frame distillation, followed by this same acceptance gate.
