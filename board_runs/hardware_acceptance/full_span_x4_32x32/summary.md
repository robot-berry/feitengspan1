# Full SPAN hardware acceptance

Result: `PASS`

Target: X4 `32x32 -> 128x128`
PL frequency: `25 MHz`
Input PNG: `external\SPAN\test_scripts\data\baboon.png`

## Artifacts

- bitstream: `G:\UESTC\feitengspan1\vivado\bitstreams\jfs_full_span_x4_32x32.bit`
- timing report: `G:\UESTC\feitengspan1\vivado\reports\jtag_full_span_x4_32x32_timing_impl.rpt`
- utilization report: `G:\UESTC\feitengspan1\vivado\reports\jtag_full_span_x4_32x32_utilization_impl.rpt`
- board output PNG: `G:\UESTC\feitengspan1\board_runs\hardware_acceptance\full_span_x4_32x32\board_output_x4_32x32.png`
- comparison preview: `G:\UESTC\feitengspan1\board_runs\hardware_acceptance\full_span_x4_32x32\jtag\compare_x4_32x32\validation_preview_x4_32x32.png`

## Checks

| Check | Result | Value |
| --- | --- | --- |
| dry run | `False` | - |
| bitstream exists | `True` | `G:\UESTC\feitengspan1\vivado\bitstreams\jfs_full_span_x4_32x32.bit` |
| timing met | `True` | WNS `12.959` ns, WHS `0.005` ns |
| JTAG ran | `True` | output bytes `49152` |
| raw reference match | `True` | mismatch bytes `0` |
| comparison preview exists | `True` | `G:\UESTC\feitengspan1\board_runs\hardware_acceptance\full_span_x4_32x32\jtag\compare_x4_32x32\validation_preview_x4_32x32.png` |

## Resources

- CLB LUTs: `7753`
- CLB Registers: `4015`
- Block RAM Tile: `307`
- DSPs: `4`
