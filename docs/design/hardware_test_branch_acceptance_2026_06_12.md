# Hardware-test branch acceptance

Date: 2026-06-12

Branch: `hardware-test`

Purpose: keep FPGA/Vivado/JTAG validation separate from the software model-training branch. The software branch can continue optimizing TinySPAN/video SR checkpoints, while this branch validates the hardware path with bitstreams, timing/resource reports, board output, byte comparison, and preview images.

## Hardware acceptance wrapper

Script:

```powershell
scripts\run_full_span_hardware_acceptance.ps1
```

Modes:

- default: build bitstream, run JTAG, compare output, write summary
- `-DryRun`: check paths and print planned commands without touching the board
- `-SummarizeExisting`: summarize already generated hardware/JTAG artifacts and require byte-exact reference match
- `-SkipBuild`: reuse an existing bitstream
- `-SkipJtag`: skip board transfer and only summarize build artifacts

The wrapper writes:

- `summary.json`
- `summary.md`
- board output raw/PNG
- fixed-point reference comparison preview

## Dry-run readiness check

Command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_full_span_hardware_acceptance.ps1 `
  -Scale 4 `
  -ImgW 32 `
  -InputPng external\SPAN\test_scripts\data\baboon.png `
  -DryRun
```

Result:

- Vivado path exists: `True`
- input PNG exists: `True`
- bitstream exists: `True`
- timing report parsed: WNS `12.959 ns`, WHS `0.005 ns`
- utilization report parsed: CLB LUTs `7753`, CLB Registers `4015`, Block RAM Tile `307`, DSPs `4`

## X4 32x32 JTAG hardware acceptance

The X4 `IMG_W=32` bitstream was already available from the banked-RAM full SPAN build, so the board test reused the existing bitstream and ran JTAG validation.

Command launched:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_full_span_hardware_acceptance.ps1 `
  -Scale 4 `
  -ImgW 32 `
  -InputPng external\SPAN\test_scripts\data\baboon.png `
  -SkipBuild
```

The outer command timed out after the board transfer had completed, so the already generated artifacts were summarized with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_full_span_hardware_acceptance.ps1 `
  -Scale 4 `
  -ImgW 32 `
  -InputPng external\SPAN\test_scripts\data\baboon.png `
  -SummarizeExisting
```

Board/JTAG result:

- input counter: `1024`
- output counter: `16384`
- error flags: `0x00000000`
- board output bytes: `49152`
- expected bytes: `49152`
- fixed-point reference bytes: `49152`
- mismatch bytes: `0`

Implementation result:

- bitstream: `vivado/bitstreams/jfs_full_span_x4_32x32.bit`
- timing report: `vivado/reports/jtag_full_span_x4_32x32_timing_impl.rpt`
- utilization report: `vivado/reports/jtag_full_span_x4_32x32_utilization_impl.rpt`
- WNS: `12.959 ns`
- WHS: `0.005 ns`
- timing: all user specified constraints met
- CLB LUTs: `7753`
- CLB Registers: `4015`
- Block RAM Tile: `307`
- DSPs: `4`

Acceptance artifacts:

- summary: `board_runs/hardware_acceptance/full_span_x4_32x32/summary.md`
- board output raw: `board_runs/hardware_acceptance/full_span_x4_32x32/board_output_x4_32x32.rgb`
- board output PNG: `board_runs/hardware_acceptance/full_span_x4_32x32/board_output_x4_32x32.png`
- comparison preview: `board_runs/hardware_acceptance/full_span_x4_32x32/jtag/compare_x4_32x32/validation_preview_x4_32x32.png`

Gate result: `PASS`

## Why the hardware preview differs from software SR

The X4 `32x32` hardware preview is not expected to look the same as the GPU/software video SR preview.

Hardware acceptance in this branch currently validates:

- official full SPAN RTL
- INT8/fixed-point datapath
- `32x32 -> 128x128` tile size
- JTAG input/output transport
- byte-exact match against `tools/span_official_fixed_ref.py`

Software acceptance on the other branch validates:

- PyTorch/GPU model execution
- usually FP16/FP32 arithmetic
- TinySPAN or official SPAN software checkpoints
- `320x180 -> 1280x720` stream target
- visual/video quality and realtime FPS

Therefore the hardware preview can look visually different from the previous software training preview and still be correct. The key hardware proof is:

```text
board output bytes: 49152
reference bytes:    49152
mismatch bytes:     0
```

That means the FPGA output matches the current fixed-point RTL reference exactly. To make hardware visual output match a newly trained TinySPAN software model, the software branch must first export that TinySPAN checkpoint into hardware weights/RTL, then this branch must rebuild and rerun the same acceptance gate.

## Branch workflow

Recommended split:

1. Software branch trains or optimizes TinySPAN/video SR checkpoints.
2. Software branch runs GPU realtime acceptance.
3. Software branch exports RTL/weights for the selected checkpoint.
4. `hardware-test` branch imports those exported hardware artifacts.
5. `hardware-test` runs `scripts\run_full_span_hardware_acceptance.ps1`.
6. Hardware results are recorded with timing/resource/JTAG byte-match evidence and preview images.

This keeps software quality iteration and hardware validation independent while preserving a shared acceptance format.
