# Full SPAN Board Validation Status - 2026-06-12

This file is a compact handoff index for the Feiteng/SPAN board validation work. The authoritative detailed log remains `docs/design/work_log.md` and `docs/design/full_span_board_verification_2026_06_11.md`.

## Current result

The official SPAN X2 and X4 FPGA paths have been validated on board with the current official image `external/SPAN/test_scripts/data/baboon.png`. Color-channel order is validated by byte-for-byte comparison between board RGB raw output and the fixed-point software reference.

## Passing board runs

| Scale | Input | Output | Result | Preview | Commit |
| --- | --- | --- | --- | --- | --- |
| X2 | 4x4 | 8x8 | PASS, 192 bytes match | `board_runs/full_span_jtag_smoke/compare_x2_4x4/validation_preview_x2_4x4.png` | `93af649` |
| X4 | 4x4 | 16x16 | PASS, 768 bytes match | `board_runs/full_span_jtag_smoke/compare_x4_4x4/validation_preview_x4_4x4.png` | `b6ab2a2` |
| X2 | 8x8 | 16x16 | PASS, 768 bytes match | `board_runs/full_span_jtag_smoke/compare_x2_8x8/validation_preview_x2_8x8.png` | `badda89` |
| X4 | 8x8 | 32x32 | PASS, 3072 bytes match | `board_runs/full_span_jtag_smoke/compare_x4_8x8_pixelshuffle_fixed/validation_preview_x4_8x8.png` | `93af649` |
| X2 | 16x16 | 32x32 | PASS, 3072 bytes match | `board_runs/full_span_jtag_smoke/compare_x2_16x16/validation_preview_x2_16x16.png` | `ee3c41c` |
| X4 | 16x16 | 64x64 | PASS, 12288 bytes match | `board_runs/full_span_jtag_smoke/compare_x4_16x16/validation_preview_x4_16x16.png` | `7bcb221` |
| X2 | 32x32 | 64x64 | PASS, 12288 bytes match | `board_runs/full_span_jtag_smoke/compare_x2_32x32_banked_ram/validation_preview_x2_32x32.png` | `1c968e0` |
| X4 | 32x32 | 128x128 | PASS, 49152 bytes match | `board_runs/full_span_jtag_smoke/compare_x4_32x32_banked_ram/validation_preview_x4_32x32.png` | `b99dc86` |

## Key fixes

1. PixelShuffle RGB order was corrected to match PyTorch layout: `color * scale * scale + subpixel`.
2. Full-span validation disables post-processing video gain so board output is raw SPAN output.
3. `span_sync_ram_1r1w` now banks RAMs deeper than 4096 entries into 4K physical banks. This fixed the X4 32x32 board-only failure caused by problematic deep BRAM inference.
4. `scripts/run_jtag_full_span_smoke.ps1` and `scripts/compare_jtag_full_span_output.ps1` generate comparison previews for each board test.

## Git archive status

The validation checkpoints are committed locally on branch `master`:

- `1c968e0 Validate X2 32x32 banked RAM board output`
- `b99dc86 Validate X4 32x32 banked RAM board output`
- `b976f40 Record X4 32x32 failed board attempt`
- `ee3c41c Validate fixed X2 16x16 board output`
- `7bcb221 Validate fixed X4 16x16 board output`
- `badda89 Validate fixed X2 8x8 board output`
- `b6ab2a2 Validate fixed X4 4x4 board output`
- `93af649 Fix SPAN PixelShuffle color order and validate X2 X4`

`git remote -v` is currently empty, so these commits cannot be pushed to GitHub yet. After a GitHub repository URL is chosen, run:

```powershell
git remote add origin <github-repo-url>
git push -u origin master
```

## Next recommended work

1. Configure the GitHub remote and push the local commits.
2. If SD-card based validation is still desired, reuse the current official image and the passing X2/X4 32x32 bitstreams as the baseline.
3. Keep using `run_jtag_full_span_smoke.ps1` for board tests so every run produces raw output, PNG output, and a comparison preview.