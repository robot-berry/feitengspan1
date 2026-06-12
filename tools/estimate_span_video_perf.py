"""Estimate throughput for the current SPAN RTL frame engine.

The current `span_official_frame_engine` is a byte-exact validation engine:
it computes one MAC tap through a sequential state machine. This estimator
keeps that model explicit so video work can quantify the gap before and after
RTL parallelization.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass


FEATURE_CH = 48


@dataclass(frozen=True)
class Estimate:
    scale: int
    input_width: int
    input_height: int
    fps_target: float
    clock_mhz: float
    cycles_per_input_pixel: int
    cycles_per_frame: int
    fps_at_clock: float
    clock_for_target_mhz: float
    parallel_speedup_for_target: float


def cycles_per_output_channel(taps: int) -> int:
    # ST_PREP once, then ST_WEIGHT_WAIT/ST_DATA_WAIT/ST_MAC for every tap.
    return 1 + 3 * taps


def cycles_per_input_pixel(scale: int, ch: int = FEATURE_CH) -> int:
    up_ch = 3 * scale * scale

    conv1 = ch * cycles_per_output_channel(3 * 9)
    spab_convs = 18 * ch * cycles_per_output_channel(ch * 9)
    conv2 = ch * cycles_per_output_channel(ch * 9)
    conv_cat = ch * cycles_per_output_channel(ch * 4)
    upsampler = up_ch * cycles_per_output_channel(ch * 9)
    return conv1 + spab_convs + conv2 + conv_cat + upsampler


def estimate(scale: int, width: int, height: int, fps: float, clock_mhz: float) -> Estimate:
    in_pixels = width * height
    per_pixel = cycles_per_input_pixel(scale)
    # Capture is one cycle per LR pixel. Output is three cycles per HR pixel
    # in the current output state machine when m_ready is always high.
    capture_cycles = in_pixels
    output_cycles = in_pixels * scale * scale * 3
    cycles_frame = in_pixels * per_pixel + capture_cycles + output_cycles
    clock_hz = clock_mhz * 1_000_000.0
    fps_at_clock = clock_hz / cycles_frame
    clock_for_target_mhz = cycles_frame * fps / 1_000_000.0
    parallel_speedup = clock_for_target_mhz / clock_mhz
    return Estimate(
        scale=scale,
        input_width=width,
        input_height=height,
        fps_target=fps,
        clock_mhz=clock_mhz,
        cycles_per_input_pixel=per_pixel,
        cycles_per_frame=cycles_frame,
        fps_at_clock=fps_at_clock,
        clock_for_target_mhz=clock_for_target_mhz,
        parallel_speedup_for_target=parallel_speedup,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--width", type=int, default=32, help="Low-resolution input width")
    parser.add_argument("--height", type=int, default=None, help="Low-resolution input height; defaults to width")
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--clock-mhz", type=float, default=150.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    height = args.height if args.height is not None else args.width
    est = estimate(args.scale, args.width, height, args.fps, args.clock_mhz)
    out_w = args.width * args.scale
    out_h = height * args.scale

    print(f"scale: X{est.scale}")
    print(f"input: {est.input_width}x{est.input_height}")
    print(f"output: {out_w}x{out_h}")
    print(f"cycles_per_input_pixel_current_engine: {est.cycles_per_input_pixel}")
    print(f"cycles_per_frame_current_engine: {est.cycles_per_frame}")
    print(f"fps_at_{est.clock_mhz:g}mhz_current_engine: {est.fps_at_clock:.6f}")
    print(f"clock_for_{est.fps_target:g}fps_current_engine_mhz: {est.clock_for_target_mhz:.3f}")
    print(f"speedup_needed_at_{est.clock_mhz:g}mhz_for_{est.fps_target:g}fps: {est.parallel_speedup_for_target:.1f}x")


if __name__ == "__main__":
    main()
