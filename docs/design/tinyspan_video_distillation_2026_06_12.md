# TinySPAN video-frame distillation

Date: 2026-06-12

Purpose: move the realtime TinySPAN optimization path from single-frame image distillation toward video super-resolution. Video SR should preserve both per-frame teacher quality and adjacent-frame consistency.

## Tool

Script: `train/distill_tinyspan_video.py`

The script trains on adjacent frame pairs:

- `frame0 -> teacher0/student0`
- `frame1 -> teacher1/student1`

Loss terms:

- `distill_loss`: L1 student-to-official-SPAN teacher on both frames
- `hr_loss`: L1 student-to-HR bicubic target crop on both frames
- `edge_loss`: Sobel edge consistency against teacher on both frames
- `temporal_loss`: L1 between student and teacher frame deltas

Temporal loss:

```text
L1((student1 - student0), (teacher1 - teacher0))
```

Supported inputs:

- a real video-frame directory, including nested REDS-style sequence folders
- a single sequence directory
- a single image for smoke tests, where the script generates a deterministic pan/zoom sequence

Config:

- `configs/distill_tinyspan_video_x4_c16_b3.json`

## Smoke command

```powershell
python train\distill_tinyspan_video.py `
  --train-frames external\SPAN\test_scripts\data\baboon.png `
  --scale 4 `
  --channels 16 `
  --num-blocks 3 `
  --patch-size 128 `
  --batch-size 1 `
  --epochs 1 `
  --max-steps 6 `
  --synthetic-frames 12 `
  --resume-student runs\tinyspan_distill\smoke_x4_c16_b3_baboon\student_last.pt `
  --output runs\tinyspan_distill\video_smoke_x4_c16_b3_baboon `
  --amp
```

Smoke training result:

- steps: `6`
- final loss: `0.04101366`
- final distill loss: `0.02210080`
- final HR loss: `0.04958007`
- final edge loss: `0.11474466`
- final temporal loss: `0.03350976`
- final teacher PSNR vs HR patch: `23.455042 dB`
- final student PSNR vs HR patch: `22.748724 dB`

Artifacts:

- checkpoint: `runs/tinyspan_distill/video_smoke_x4_c16_b3_baboon/student_last.pt`
- metrics: `runs/tinyspan_distill/video_smoke_x4_c16_b3_baboon/metrics.csv`
- preview: `runs/tinyspan_distill/video_smoke_x4_c16_b3_baboon/video_distill_preview.png`

## Teacher quality check after smoke

Command:

```powershell
python tools\evaluate_tinyspan_video_quality.py `
  --scale 4 `
  --student-checkpoint runs\tinyspan_distill\video_smoke_x4_c16_b3_baboon\student_last.pt `
  --student-channels 16 `
  --student-blocks 3 `
  --input external\SPAN\test_scripts\data\baboon.png `
  --width 320 `
  --height 180 `
  --frames 30 `
  --fps 30 `
  --motion `
  --out-dir runs\tinyspan_quality\video_smoke_c16_b3_baboon_x4_320x180_30f `
  --half `
  --preview-tile 180 `
  --diff-gain 8
```

Result against the official SPAN teacher:

- mean PSNR: `29.939 dB`
- minimum PSNR: `29.465 dB`
- mean MAE: `0.020711`
- mean MSE: `0.00101686`
- max absolute channel error: `0.386230`
- temporal MAE: `0.029147`
- temporal MSE: `0.00196206`
- paired teacher inference: `32.882 ms/frame`
- paired student inference: `8.357 ms/frame`

Artifacts:

- metrics: `runs/tinyspan_quality/video_smoke_c16_b3_baboon_x4_320x180_30f/metrics.json`
- per-frame CSV: `runs/tinyspan_quality/video_smoke_c16_b3_baboon_x4_320x180_30f/frame_metrics.csv`
- preview: `runs/tinyspan_quality/video_smoke_c16_b3_baboon_x4_320x180_30f/baboon_tinyspan_teacher_quality_x4.png`

## Interpretation

The short smoke fine-tune proves the video-frame distillation loop and temporal loss work. It is not expected to improve image quality after only six synthetic steps; the teacher quality check remains essentially unchanged from the previous smoke checkpoint. The next meaningful optimization step is a full run on real video-frame data such as REDS, starting from the best single-frame C16/B3 checkpoint, then rerunning both:

- `tools/evaluate_tinyspan_video_quality.py` for student-vs-teacher quality
- `tools/run_span_video_stream.py` for realtime FPS

## Temporal evaluation baseline

After adding temporal metrics to `tools/evaluate_tinyspan_video_quality.py`, the same 30-frame generated `baboon.png` sequence was evaluated for the pre-video and post-video-smoke checkpoints:

| Checkpoint | Mean PSNR | Temporal MAE | Temporal PSNR |
| --- | ---: | ---: | ---: |
| single-frame smoke C16/B3 | `29.942 dB` | `0.029199` | `32.963 dB` |
| video-smoke C16/B3 | `29.939 dB` | `0.029147` | `32.977 dB` |

This is a small movement, not a quality claim. The value is the new measurement loop: future full video-frame distillation runs can be judged by both frame PSNR/MAE and temporal MAE/PSNR.
