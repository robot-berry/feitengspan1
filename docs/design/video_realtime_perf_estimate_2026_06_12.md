# Video Realtime Performance Estimate - 2026-06-12

The image SPAN FPGA path is functionally complete and byte-exact against the Python RTL reference. For realtime video, the key issue is throughput.

## Recommended realtime target

Use `30 fps` as the first realtime target. It is a good balance for project demonstration and leaves room to close timing and bandwidth. Use `60 fps` as the later smooth-video target.

Typical display pixel clocks are separate from compute throughput:

| Output mode | Typical pixel clock |
| --- | ---: |
| 640x480 @ 60Hz | 25.175 MHz |
| 1280x720 @ 60Hz | 74.25 MHz |
| 1920x1080 @ 30Hz | 74.25 MHz |
| 1920x1080 @ 60Hz | 148.5 MHz |

So a `150 MHz` PL/video clock is a reasonable target for a 1080p60-class output path, but it is not enough by itself for the current SPAN compute engine.

## Current engine throughput

The current `span_official_frame_engine` uses a sequential validation architecture. It is designed to prove correctness, not realtime throughput.

For X4, the current engine takes about `1,276,752` cycles per low-resolution input pixel. For X2, it takes about `1,230,060` cycles per input pixel.

At X4 `32x32 -> 128x128`:

| Clock | Estimated fps |
| --- | ---: |
| 25 MHz | 0.019 fps |
| 40 MHz | 0.031 fps |
| 50 MHz | 0.038 fps |
| 150 MHz | 0.115 fps |

To make the current X4 `32x32` validation engine reach `30 fps`, the equivalent sequential clock would be about `39.2 GHz`, which is impossible on FPGA.

## Examples

Using the current sequential engine:

| Mode | Required sequential clock for 30 fps |
| --- | ---: |
| X4 32x32 -> 128x128 | 39.2 GHz |
| X4 320x180 -> 1280x720 | 2206.2 GHz |
| X4 480x270 -> 1920x1080 | 4964.0 GHz |
| X2 640x360 -> 1280x720 | 8502.2 GHz |
| X2 960x540 -> 1920x1080 | 19129.9 GHz |

This confirms that realtime video requires architectural parallelism, not only clock frequency.

## Estimator

Run:

```powershell
python tools\estimate_span_video_perf.py --scale 4 --width 32 --height 32 --fps 30 --clock-mhz 150
```

For an output target such as X4 `320x180 -> 1280x720`:

```powershell
python tools\estimate_span_video_perf.py --scale 4 --width 320 --height 180 --fps 30 --clock-mhz 150
```

The `speedup_needed` field is the approximate throughput improvement required over the current sequential engine at the selected clock.

## Optimization direction

The next realtime path should:

1. Keep the byte-exact Python/RTL reference as the quality oracle.
2. Create a video-oriented streaming shell with line buffers and frame-rate accounting.
3. Replace the single-MAC sequential convolution engine with a parameterized multi-lane MAC datapath.
4. Pipeline every BRAM read, multiply, adder-tree, activation, and writeback stage.
5. Start with a smaller realtime target such as X2 320x180 -> 640x360 or X2 640x360 -> 1280x720 at 30 fps before attempting X4 1080p-class output.
