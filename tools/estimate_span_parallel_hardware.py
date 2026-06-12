"""Size a parallel SPAN hardware datapath for realtime video targets.

This is an architecture estimator, not a Vivado resource report. It converts
the official SPAN layer MAC count into the required sustained MAC lanes at a
given PL clock and frame-rate target.
"""

from __future__ import annotations

import argparse
import csv
import math
from dataclasses import dataclass, asdict
from pathlib import Path


FEATURE_CH = 48


@dataclass(frozen=True)
class LayerMac:
    name: str
    out_channels: int
    in_channels: int
    kernel_taps: int
    macs_per_pixel: int


@dataclass(frozen=True)
class HardwareEstimate:
    scale: int
    input_width: int
    input_height: int
    output_width: int
    output_height: int
    fps_target: float
    clock_mhz: float
    feature_channels: int
    blocks: int
    input_pixels_per_frame: int
    macs_per_input_pixel: int
    macs_per_frame: int
    required_gmac_s: float
    macs_per_cycle_required: float
    mac_lanes_for_target: int
    dsp_estimate_int8_1mac_per_dsp: int
    dsp_estimate_int8_2mac_per_dsp: int
    fps_at_candidate_lanes: float
    candidate_lanes: int
    cycles_per_frame_at_candidate: int
    utilization_of_candidate: float


def layer_macs(scale: int, ch: int = FEATURE_CH, blocks: int = 6) -> list[LayerMac]:
    up_ch = 3 * scale * scale
    layers = [LayerMac("conv1", ch, 3, 9, ch * 3 * 9)]
    for block in range(1, blocks + 1):
        layers.extend(
            [
                LayerMac(f"block{block}_c1", ch, ch, 9, ch * ch * 9),
                LayerMac(f"block{block}_c2", ch, ch, 9, ch * ch * 9),
                LayerMac(f"block{block}_c3", ch, ch, 9, ch * ch * 9),
            ]
        )
    layers.append(LayerMac("conv2", ch, ch, 9, ch * ch * 9))
    layers.append(LayerMac("conv_cat", ch, ch * 4, 1, ch * ch * 4))
    layers.append(LayerMac("upsampler", up_ch, ch, 9, up_ch * ch * 9))
    return layers


def macs_per_input_pixel(scale: int, ch: int = FEATURE_CH, blocks: int = 6) -> int:
    return sum(layer.macs_per_pixel for layer in layer_macs(scale, ch, blocks))


def estimate(
    scale: int,
    width: int,
    height: int,
    fps: float,
    clock_mhz: float,
    candidate_lanes: int,
    ch: int = FEATURE_CH,
    blocks: int = 6,
) -> HardwareEstimate:
    in_pixels = width * height
    out_w = width * scale
    out_h = height * scale
    per_pixel = macs_per_input_pixel(scale, ch, blocks)
    per_frame = per_pixel * in_pixels
    required_macs_s = per_frame * fps
    macs_per_cycle = required_macs_s / (clock_mhz * 1_000_000.0)
    lanes = math.ceil(macs_per_cycle)
    candidate_cycles = math.ceil(per_frame / candidate_lanes)
    candidate_fps = (clock_mhz * 1_000_000.0) / candidate_cycles
    utilization = macs_per_cycle / candidate_lanes
    return HardwareEstimate(
        scale=scale,
        input_width=width,
        input_height=height,
        output_width=out_w,
        output_height=out_h,
        fps_target=fps,
        clock_mhz=clock_mhz,
        feature_channels=ch,
        blocks=blocks,
        input_pixels_per_frame=in_pixels,
        macs_per_input_pixel=per_pixel,
        macs_per_frame=per_frame,
        required_gmac_s=required_macs_s / 1_000_000_000.0,
        macs_per_cycle_required=macs_per_cycle,
        mac_lanes_for_target=lanes,
        dsp_estimate_int8_1mac_per_dsp=lanes,
        dsp_estimate_int8_2mac_per_dsp=math.ceil(lanes / 2),
        fps_at_candidate_lanes=candidate_fps,
        candidate_lanes=candidate_lanes,
        cycles_per_frame_at_candidate=candidate_cycles,
        utilization_of_candidate=utilization,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Estimate SPAN realtime parallel hardware size.")
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=180)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--clock-mhz", type=float, default=150.0)
    parser.add_argument("--candidate-lanes", type=int, default=4096)
    parser.add_argument("--channels", type=int, default=FEATURE_CH)
    parser.add_argument("--blocks", type=int, default=6)
    parser.add_argument("--csv", type=Path)
    return parser.parse_args()


def write_csv(path: Path, rows: list[HardwareEstimate]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def main() -> None:
    args = parse_args()
    est = estimate(
        args.scale,
        args.width,
        args.height,
        args.fps,
        args.clock_mhz,
        args.candidate_lanes,
        args.channels,
        args.blocks,
    )
    print(f"scale: X{est.scale}")
    print(f"input: {est.input_width}x{est.input_height}")
    print(f"output: {est.output_width}x{est.output_height}")
    print(f"fps_target: {est.fps_target:g}")
    print(f"clock_mhz: {est.clock_mhz:g}")
    print(f"feature_channels: {est.feature_channels}")
    print(f"blocks: {est.blocks}")
    print(f"macs_per_input_pixel: {est.macs_per_input_pixel:,}")
    print(f"macs_per_frame: {est.macs_per_frame:,}")
    print(f"required_compute: {est.required_gmac_s:.3f} GMAC/s")
    print(f"macs_per_cycle_required: {est.macs_per_cycle_required:.2f}")
    print(f"mac_lanes_for_target: {est.mac_lanes_for_target}")
    print(f"dsp_estimate_int8_1mac_per_dsp: {est.dsp_estimate_int8_1mac_per_dsp}")
    print(f"dsp_estimate_int8_2mac_per_dsp: {est.dsp_estimate_int8_2mac_per_dsp}")
    print(f"fps_at_{est.candidate_lanes}_candidate_lanes: {est.fps_at_candidate_lanes:.3f}")
    print(f"candidate_lane_utilization_for_target: {est.utilization_of_candidate * 100.0:.2f}%")
    if args.csv:
        write_csv(args.csv, [est])
        print(f"csv: {args.csv}")


if __name__ == "__main__":
    main()
