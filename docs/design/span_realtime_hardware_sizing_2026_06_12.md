# SPAN realtime hardware sizing

Date: 2026-06-12

Purpose: convert the 720p realtime video target into approximate MAC lane and DSP requirements for FPGA architecture work.

## Tool

Added:

- `tools/estimate_span_parallel_hardware.py`

This tool estimates the sustained MAC lanes required for a parallel SPAN datapath:

```powershell
python tools\estimate_span_parallel_hardware.py `
  --scale 4 `
  --width 320 `
  --height 180 `
  --fps 30 `
  --clock-mhz 150 `
  --channels 48 `
  --blocks 6 `
  --candidate-lanes 4096
```

It is an architecture estimator, not a Vivado implementation report. It assumes one MAC lane can retire one multiply-accumulate per clock. DSP estimates are first-order:

- `1 MAC/DSP`: conservative INT8 mapping
- `2 MAC/DSP`: optimistic packed INT8 mapping

## Official SPAN cost

Official SPAN X4 with `48` feature channels and `6` SPAB blocks costs:

- MACs per LR input pixel: `425,232`
- X4 `320x180 -> 1280x720` per frame: `24,493,363,200` MACs

At `150 MHz`:

| Target | Required compute | MAC lanes | DSP estimate, 1 MAC/DSP | DSP estimate, 2 MAC/DSP |
| --- | ---: | ---: | ---: | ---: |
| X4 `320x180 -> 1280x720 @30` | `734.801 GMAC/s` | `4899` | `4899` | `2450` |
| X4 `320x180 -> 1280x720 @60` | `1469.602 GMAC/s` | `9798` | `9798` | `4899` |
| X2 `640x360 -> 1280x720 @30` | `2831.708 GMAC/s` | `18879` | `18879` | `9440` |
| X4 `480x270 -> 1920x1080 @30` | `1653.302 GMAC/s` | `11023` | `11023` | `5512` |

Conclusion: the full official 48-channel 6-block model is not a practical first FPGA realtime target at 150 MHz. It should remain the correctness and quality reference, while the realtime FPGA model should be reduced and retrained/distilled.

## Lightweight FPGA candidates

For the software demo target X4 `320x180 -> 1280x720 @30`:

| Candidate | Clock | MACs / LR pixel | Required compute | MAC lanes for 30fps | Candidate lanes | Estimated FPS at candidate lanes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| C16/B3 | `150 MHz` | `31,408` | `54.273 GMAC/s` | `362` | `512` | `42.452` |
| C16/B6 | `150 MHz` | `52,144` | `90.105 GMAC/s` | `601` | `768` | `38.355` |
| C24/B3 | `150 MHz` | `65,160` | `112.596 GMAC/s` | `751` | `1024` | `40.925` |
| C32/B3 | `150 MHz` | `110,944` | `191.711 GMAC/s` | `1279` | `2048` | `48.072` |
| C16/B3 | `200 MHz` | `31,408` | `54.273 GMAC/s` | `272` | `512` | `56.603` |
| C24/B3 | `200 MHz` | `65,160` | `112.596 GMAC/s` | `563` | `768` | `40.925` |

For a later 720p60 software-equivalent target:

| Candidate | Clock | MAC lanes for 60fps | Candidate lanes | Estimated FPS |
| --- | ---: | ---: | ---: | ---: |
| C16/B3 | `150 MHz` | `724` | `1024` | `84.904` |

## Recommended hardware target

Use a two-step FPGA path:

1. **Realtime candidate A:** X4 C16/B3, `320x180 -> 1280x720 @30`, `150 MHz`, `512` MAC lanes.
2. **Quality candidate B:** X4 C24/B3 or C16/B6, same video mode, `150 MHz`, `768-1024` MAC lanes.

Candidate A is the first practical hardware target because it leaves room for line buffers, feature RAM banking, AXI/video shell logic, and timing margin. Candidate B can follow after training/distillation shows whether C16/B3 quality is too low.

## RTL implications

The next RTL should not extend the current single-MAC frame engine directly. It should introduce:

- parameterized `MAC_LANES`
- banked feature memory with enough read ports or time-multiplexed groups
- tiled/channel-grouped convolution scheduling
- pipelined adder trees and registered activation stages
- line-buffer or tile-buffer video shell
- AXI-stream or frame-DMA input/output path

The current byte-exact official SPAN frame engine remains the regression oracle for small images. The realtime datapath should be validated against the Python fixed-point reference layer by layer, then retrained/distilled against the official SPAN GPU output for video quality.
