# TinySPAN realtime distillation plan

Date: 2026-06-12

Purpose: create the training path for a lightweight FPGA-realtime SPAN student. Hardware sizing showed that full official SPAN is too large for the first realtime FPGA target, so the next model should be distilled from official SPAN into a smaller TinySPAN.

## Changes

1. `train/span_model.py` now supports fewer than 6 SPAB blocks.
   - Old behavior for 6 blocks is preserved.
   - For smaller models, the concat path uses the first block output, the deepest available block output, and the fused tail.
2. Added:
   - `train/distill_tinyspan_from_official.py`
3. Updated:
   - `train/export_tinyspan_to_rtl.py`
   - Adds the same local OpenMP workaround used by the GPU tools.

## Distillation loss

The student is trained with:

```text
loss = distill_weight * L1(student, official_teacher)
     + hr_weight      * L1(student, HR)
     + edge_weight    * L1(edge(student), edge(official_teacher))
```

Default smoke values:

- `distill_weight = 1.0`
- `hr_weight = 0.2`
- `edge_weight = 0.02`

## Smoke test

Command:

```powershell
python train\distill_tinyspan_from_official.py `
  --scale 4 `
  --channels 16 `
  --num-blocks 3 `
  --patch-size 128 `
  --batch-size 1 `
  --epochs 1 `
  --max-steps 10 `
  --train-hr external\SPAN\test_scripts\data `
  --output runs\tinyspan_distill\smoke_x4_c16_b3_baboon `
  --amp
```

Because the smoke dataset contains one image, this run executes one training step. It verifies the complete path:

- official SPAN teacher loads from `rtl/generated/official_span_x4/official_span_manifest.json`
- TinySPAN X4 C16/B3 student builds and trains
- metrics are written
- preview image is generated
- checkpoint is written
- TinySPAN RTL manifest export works

Smoke result:

- student architecture: X4 C16/B3
- parameters: `125792`
- step loss: `0.03869177`
- distill loss: `0.02133024`
- teacher PSNR vs HR crop: `20.113368 dB`
- student PSNR vs HR crop: `19.607937 dB`
- preview: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/distill_preview.png`
- checkpoint: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/student_last.pt`
- RTL export manifest: `runs/tinyspan_distill/smoke_x4_c16_b3_baboon/rtl_export/tinyspan_manifest.json`

## Recommended full run

Use REDS HR frames and distill X4 C16/B3 first:

```powershell
python train\distill_tinyspan_from_official.py `
  --scale 4 `
  --channels 16 `
  --num-blocks 3 `
  --patch-size 192 `
  --batch-size 16 `
  --epochs 100 `
  --train-hr G:\REDS\train_sharp `
  --train-max-images 24000 `
  --output runs\tinyspan_distill\x4_c16_b3_reds `
  --amp
```

Then compare against the official SPAN GPU reference:

1. Run student image/video inference.
2. Measure PSNR/SSIM and visual quality against official SPAN teacher outputs.
3. Export INT8 weights with `train/export_tinyspan_to_rtl.py`.
4. Build the parameterized FPGA datapath around the C16/B3 target.

## Hardware alignment

From `docs/design/span_realtime_hardware_sizing_2026_06_12.md`:

- C16/B3 X4 `320x180 -> 1280x720 @30`, `150 MHz`
- required MAC lanes: `362`
- recommended first implementation: `512` MAC lanes
- estimated throughput at `512` lanes: `42.452 fps`

This makes C16/B3 the first practical FPGA realtime candidate.
