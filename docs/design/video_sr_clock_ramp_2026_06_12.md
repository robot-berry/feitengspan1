# Video SR Clock Ramp Plan - 2026-06-12

This note records the practical path from the current image-validation SPAN FPGA design toward a video super-resolution design with a higher PL clock.

## Current evidence

The current validated full official SPAN board path runs from PS PL0 at `25 MHz`.

For the largest passing X4 image validation design, `IMG_W=32` and `32x32 -> 128x128`, the archived timing report shows:

- `clk_pl_0` period: `40.000 ns`
- `clk_pl_0` frequency: `25.000 MHz`
- `clk_pl_0` intra-clock WNS: `19.857 ns`
- Approximate current PL critical path delay: `40.000 - 19.857 = 20.143 ns`
- Approximate current PL-only ceiling: about `49.6 MHz`

This means the present image-validation architecture should be tested at `40 MHz` first, then around `50 MHz`. It should not be expected to reach `150 MHz` without RTL micro-architecture work.

## Why 150 MHz is not a simple clock setting

`150 MHz` means a `6.667 ns` clock period. The current validated design has an estimated PL critical path near `20 ns`, so a direct jump from `25 MHz` to `150 MHz` would likely fail timing by roughly `13 ns`.

The present full-frame engine is built for correctness validation:

- It buffers a whole small frame.
- It executes the official INT8 SPAN math in a sequential frame-engine style.
- It uses large feature memories and address/control paths.
- It produces byte-exact results matching the Python RTL reference and board output.

For video, frequency alone is not enough. The design must also provide enough pixels per second and enough compute throughput per frame.

## Recommended ramp

Use the new frequency sweep script:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_jtag_full_span_freq_sweep.ps1 -Scale 4 -ImgW 32 -FrequenciesMhz 40,50,75,100,125,150 -StopOnFailure
```

The script writes a CSV summary such as:

```text
vivado\reports\jtag_full_span_x4_32x32_freq_sweep.csv
```

Each passing frequency archives:

- bitstream under `vivado\bitstreams`
- utilization report under `vivado\reports`
- timing report under `vivado\reports`

## Milestones

1. `40 MHz`: reasonable first target from the current timing margin.
2. `50 MHz`: near the current estimated PL limit; requires a real Vivado implementation check.
3. `75 MHz`: requires reducing the critical path with local pipelining.
4. `100 MHz`: likely requires deeper datapath pipelining and cleaner BRAM/register boundaries.
5. `150 MHz`: likely requires a video-oriented architecture, not only the current validation engine.

## RTL work needed for 150 MHz

The likely changes are:

- Pipeline the 3x3 convolution multiply/accumulate path across multiple cycles.
- Register address-generation and feature-bank read paths.
- Split long control-state transitions around SPAB blocks.
- Keep BRAM read data registered and avoid large combinational fanout after memory outputs.
- Consider multiple MAC lanes for video throughput after timing is under control.
- Add a streaming video shell with line buffers, frame buffering, and rate matching separate from the JTAG validation shell.

## Practical conclusion

The answer is: yes, the clock can be increased gradually and the project now has a script path to test that. But `150 MHz` should be treated as an optimization milestone that needs pipelining and video-architecture work. The next concrete step is to run the `40 MHz` and `50 MHz` builds and use the timing reports to identify the first failing path.
