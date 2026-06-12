# TinySPAN realtime acceptance

Checkpoint: `runs\tinyspan_distill\video_smoke_x4_c16_b3_baboon\student_last.pt`
Target: X4 `320x180 -> 1280x720` at `30.0 fps`
Result: `PASS`

## Checks

| Check | Result | Value | Target |
| --- | --- | ---: | ---: |
| `stream_fps` | `PASS` | `65.3745673974486` | `>= 30.0` |
| `stream_output_size` | `PASS` | `1280x720` | `1280x720` |
| `stream_frame_count` | `PASS` | `60` | `60` |
| `quality_output_size` | `PASS` | `1280x720` | `1280x720` |
| `video_readback` | `PASS` | `60 frames, 30.000 fps, 1280x720` | `60 frames, 1280x720` |

## Stream

- end-to-end FPS: `65.375`
- end-to-end latency: `15.296 ms/frame`
- inference: `11.347 ms/frame`
- video: `runs\tinyspan_acceptance\video_smoke_c16_b3_x4_320x180_60f\stream\baboon_tinyspan_c16_b3_stream_x4.mp4`
- preview: `runs\tinyspan_acceptance\video_smoke_c16_b3_x4_320x180_60f\stream\baboon_tinyspan_c16_b3_stream_comparison_x4.png`

## Quality

- PSNR vs teacher: `29.939 dB`
- MAE vs teacher: `0.020711`
- temporal MAE vs teacher delta: `0.029147`
- temporal PSNR: `32.977 dB`
- preview: `runs\tinyspan_acceptance\video_smoke_c16_b3_x4_320x180_60f\quality\baboon_tinyspan_teacher_quality_x4.png`
