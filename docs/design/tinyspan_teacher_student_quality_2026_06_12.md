# TinySPAN teacher-student video quality check

Date: 2026-06-12

Purpose: add a repeatable quality gate for realtime video SR. Throughput alone is not enough; every TinySPAN student checkpoint should also be compared frame-by-frame against the official SPAN teacher on the same LR video frames.

## Tool

Script: `tools/evaluate_tinyspan_video_quality.py`

Inputs:

- official SPAN teacher manifest/checkpoint
- TinySPAN student checkpoint
- image, image-frame directory, or video input
- LR stream size and frame count

Outputs:

- `metrics.json`: aggregate quality and timing metrics
- `frame_metrics.csv`: per-frame MSE, MAE, max absolute error, PSNR, and adjacent-frame temporal error
- comparison PNG: LR input, bicubic, official teacher, TinySPAN student, amplified absolute diff
- first-frame teacher/student/diff PNGs

Temporal metrics compare adjacent-frame deltas:

```text
student_delta = student_frame_i - student_frame_(i-1)
teacher_delta = teacher_frame_i - teacher_frame_(i-1)
temporal_error = student_delta - teacher_delta
```

## Smoke command

```powershell
python tools\evaluate_tinyspan_video_quality.py `
  --scale 4 `
  --student-checkpoint runs\tinyspan_distill\smoke_x4_c16_b3_baboon\student_last.pt `
  --student-channels 16 `
  --student-blocks 3 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 320 `
  --height 180 `
  --frames 30 `
  --fps 30 `
  --motion `
  --out-dir runs\tinyspan_quality\smoke_c16_b3_baboon_x4_320x180_30f `
  --half `
  --preview-tile 180 `
  --diff-gain 8
```

## Smoke result

- input: generated 30-frame image sequence from official `baboon.png`
- LR size: `320x180`
- SR size: `1280x720`
- device: RTX 3060 Laptop GPU
- dtype: FP16
- student: TinySPAN X4 C16/B3 smoke checkpoint
- teacher: official SPAN X4 checkpoint

Aggregate student-vs-teacher quality:

- mean PSNR: `29.942 dB`
- minimum PSNR: `29.469 dB`
- mean MAE: `0.020633`
- mean MSE: `0.00101630`
- max absolute channel error: `0.385742`

Timing observed inside this paired quality run:

- official teacher inference: `32.060 ms/frame`
- TinySPAN student inference: `8.224 ms/frame`

Artifacts:

- metrics: `runs/tinyspan_quality/smoke_c16_b3_baboon_x4_320x180_30f/metrics.json`
- per-frame CSV: `runs/tinyspan_quality/smoke_c16_b3_baboon_x4_320x180_30f/frame_metrics.csv`
- preview: `runs/tinyspan_quality/smoke_c16_b3_baboon_x4_320x180_30f/baboon_tinyspan_teacher_quality_x4.png`

## Interpretation

This is a smoke-quality baseline, not the final realtime model quality. The C16/B3 student is already much faster than the teacher, but the amplified diff preview shows visible high-frequency differences around texture and edges. The next quality step is full distillation on REDS/video-frame data, then rerun this exact quality tool and require the student-vs-teacher PSNR/MAE and visual diff to improve.

## Temporal metric update

The evaluator now also reports temporal consistency against the official SPAN teacher. On the same 30-frame generated `baboon.png` sequence:

| Checkpoint | Mean PSNR | Mean MAE | Temporal MAE | Temporal MSE | Student ms/frame |
| --- | ---: | ---: | ---: | ---: | ---: |
| single-frame smoke C16/B3 | `29.942 dB` | `0.020633` | `0.029199` | `0.00196856` | `7.726` |
| video-smoke C16/B3 | `29.939 dB` | `0.020711` | `0.029147` | `0.00196206` | `7.821` |

The 6-step video-smoke checkpoint gives only a tiny temporal improvement, as expected. The important result is that video stability is now a measured gate, not just a visual impression.
