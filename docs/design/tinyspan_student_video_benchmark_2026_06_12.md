# TinySPAN student video benchmark

Date: 2026-06-12

Purpose: benchmark the first lightweight FPGA-realtime candidate in the same end-to-end video stream used for the official SPAN GPU reference.

## Student

- architecture: TinySPAN X4 C16/B3
- checkpoint: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/student_last.pt`
- training status: smoke only, not a final quality model
- parameters: `125792`
- hardware target: X4 `320x180 -> 1280x720 @30`, `150 MHz`, about `512` MAC lanes

## Command

```powershell
python tools\run_span_video_stream.py `
  --model tinyspan `
  --checkpoint runs\tinyspan_distill\smoke_x4_c16_b3_baboon\student_last.pt `
  --scale 4 `
  --student-channels 16 `
  --student-blocks 3 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 320 `
  --height 180 `
  --frames 180 `
  --fps 30 `
  --motion `
  --out-dir runs\span_video_stream\tinyspan_c16_b3_smoke_x4_320x180_180f_fp16_async_labeled `
  --half `
  --async-writer `
  --preview-tile 240
```

## Result

- frames: `180`
- output: `1280x720`, `30.0 fps`, verified by OpenCV readback
- end-to-end FPS: `90.225`
- end-to-end latency: `11.083 ms/frame`
- inference: `7.423 ms/frame`
- preprocess: `2.375 ms/frame`
- postprocess: `1.004 ms/frame`
- async encode work: `6.153 ms/frame`
- metrics: `runs/span_video_stream/tinyspan_c16_b3_smoke_x4_320x180_180f_fp16_async_labeled/metrics.json`
- comparison: `runs/span_video_stream/tinyspan_c16_b3_smoke_x4_320x180_180f_fp16_async_labeled/baboon_tinyspan_c16_b3_stream_comparison_x4.png`

## Comparison with official SPAN stream

Same stream target, X4 `320x180 -> 1280x720`, FP16, async writer:

| Model | Training state | End-to-end FPS | Inference ms/frame |
| --- | --- | ---: | ---: |
| official SPAN X4 C48/B6 | full official teacher | `41.218` | `21.125` |
| TinySPAN X4 C16/B3 | smoke student only | `90.225` | `7.423` |

The smoke student is about `2.19x` faster end-to-end and about `2.85x` faster in model inference. Its quality is not final; this benchmark proves the lightweight architecture has enough software throughput and is aligned with the FPGA lane budget.

## Next use

After a full REDS/video-frame distillation run, rerun the same command with the trained C16/B3 checkpoint and compare:

- visual preview
- teacher/student PSNR or L1 against official SPAN output
- end-to-end FPS
- exported INT8 manifest

The same stream script now supports both `--model official` and `--model tinyspan`, so future comparisons use one measurement path.
