"""Compare TinySPAN video outputs against the official SPAN teacher.

The realtime work needs two separate checks: throughput and quality. This tool
keeps the quality side explicit by running the official SPAN teacher and a
TinySPAN student on the same LR video/image-sequence frames, then writing
per-frame metrics plus a visual comparison preview.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import time
from pathlib import Path
from typing import Iterator

os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import numpy as np
import torch
from PIL import Image, ImageDraw

from run_span_gpu_realtime import (
    IMAGE_EXTS,
    configure_torch,
    default_manifest,
    fit_tile,
    image_to_tensor,
    load_manifest,
    load_model,
    resize_lr,
    resolve_checkpoint,
    sync,
)
from run_span_video_stream import VIDEO_EXTS, SourceInfo, image_source, load_tinyspan_model, video_source


def tensor_to_rgb_u8(tensor: torch.Tensor) -> np.ndarray:
    out = tensor.detach().clamp(0, 1).mul(255).round().to(torch.uint8)
    return out.squeeze(0).permute(1, 2, 0).contiguous().cpu().numpy()


def tensor_diff_metrics(student: torch.Tensor, teacher: torch.Tensor, peak: float = 1.0) -> dict[str, float]:
    diff = (student.float().clamp(0, 1) - teacher.float().clamp(0, 1)).abs()
    mse = float((diff * diff).mean().item())
    mae = float(diff.mean().item())
    max_abs = float(diff.max().item())
    psnr = float("inf") if mse <= 0.0 else 10.0 * math.log10((peak * peak) / mse)
    return {"mse": mse, "mae": mae, "max_abs": max_abs, "psnr_db": psnr}


def tensor_delta_metrics(student_delta: torch.Tensor, teacher_delta: torch.Tensor) -> dict[str, float]:
    diff = (student_delta.float() - teacher_delta.float()).abs()
    mse = float((diff * diff).mean().item())
    mae = float(diff.mean().item())
    max_abs = float(diff.max().item())
    psnr = float("inf") if mse <= 0.0 else 10.0 * math.log10(4.0 / mse)
    return {
        "temporal_mse": mse,
        "temporal_mae": mae,
        "temporal_max_abs": max_abs,
        "temporal_psnr_db": psnr,
    }


def diff_image(student_rgb: np.ndarray, teacher_rgb: np.ndarray, gain: float) -> Image.Image:
    diff = np.abs(student_rgb.astype(np.int16) - teacher_rgb.astype(np.int16)).astype(np.float32)
    diff = np.clip(diff * gain, 0, 255).astype(np.uint8)
    return Image.fromarray(diff, "RGB")


def make_quality_preview(
    path: Path,
    title: str,
    lr: Image.Image,
    bicubic: Image.Image,
    teacher: Image.Image,
    student: Image.Image,
    diff: Image.Image,
    metrics: dict,
    tile: int,
) -> None:
    panels = [
        (f"Input {lr.width}x{lr.height}", fit_tile(lr, tile)),
        (f"Bicubic {bicubic.width}x{bicubic.height}", fit_tile(bicubic, tile)),
        (f"Teacher {teacher.width}x{teacher.height}", fit_tile(teacher, tile)),
        (f"Student {student.width}x{student.height}", fit_tile(student, tile)),
        (f"Abs diff x{metrics['diff_gain']}", fit_tile(diff, tile)),
    ]
    label_h = 28
    title_h = 42
    summary_h = 44
    gap = 12
    width = len(panels) * tile + (len(panels) + 1) * gap
    height = title_h + label_h + tile + summary_h + 2 * gap
    canvas = Image.new("RGB", (width, height), (246, 248, 250))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 12), title, fill=(20, 24, 31))
    summary = (
        f"frames: {metrics['frames']}, PSNR: {metrics['psnr_db_mean']:.3f} dB, "
        f"MAE: {metrics['mae_mean']:.6f}, temporal MAE: {metrics['temporal_mae_mean']:.6f}"
    )
    draw.text((gap, height - summary_h + 5), summary, fill=(64, 72, 84))
    x = gap
    for label, img in panels:
        draw.text((x, title_h), label, fill=(32, 37, 45))
        canvas.paste(img, (x, title_h + label_h))
        x += tile + gap
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def finite_mean(values: list[float]) -> float:
    finite = [v for v in values if math.isfinite(v)]
    return float(sum(finite) / len(finite)) if finite else float("inf")


def image_dir_source(path: Path, max_frames: int, fps: float) -> tuple[Iterator[Image.Image], SourceInfo]:
    paths = sorted(p for p in path.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    if max_frames > 0:
        paths = paths[:max_frames]
    if not paths:
        raise SystemExit(f"no image frames found in {path}")

    def gen() -> Iterator[Image.Image]:
        for frame_path in paths:
            yield Image.open(frame_path).convert("RGB")

    return gen(), SourceInfo(name=path.name, fps=fps, frames_expected=len(paths), mode="image_dir")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate TinySPAN student quality against official SPAN teacher.")
    parser.add_argument("--input", type=Path, default=Path("external/SPAN/test_scripts/data/baboon.png"))
    parser.add_argument("--out-dir", type=Path, default=Path("runs/tinyspan_quality/latest"))
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--teacher-checkpoint", type=Path)
    parser.add_argument("--student-checkpoint", type=Path, required=True)
    parser.add_argument("--student-channels", type=int, default=16)
    parser.add_argument("--student-blocks", type=int, default=3)
    parser.add_argument("--device", default="cuda", choices=("auto", "cuda", "cpu"))
    parser.add_argument("--half", action="store_true")
    parser.add_argument("--channels-last", action="store_true")
    parser.add_argument("--tf32", action="store_true")
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=180)
    parser.add_argument("--frames", type=int, default=30)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--motion", action="store_true")
    parser.add_argument("--preview-tile", type=int, default=180)
    parser.add_argument("--diff-gain", type=float, default=8.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest_path = args.manifest or default_manifest(args.scale)
    manifest = load_manifest(manifest_path)
    scale = int(manifest["scale"])
    if scale != args.scale:
        raise SystemExit(f"teacher scale X{scale} does not match --scale X{args.scale}")

    if args.device == "auto":
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        device = torch.device(args.device)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise SystemExit("CUDA was requested but torch.cuda.is_available() is false")

    half = bool(args.half and device.type == "cuda")
    channels_last = bool(args.channels_last and device.type == "cuda")
    configure_torch(bool(args.tf32 and device.type == "cuda"))

    teacher_checkpoint = resolve_checkpoint(manifest, args.teacher_checkpoint)
    teacher = load_model(manifest, teacher_checkpoint, device, half, channels_last)
    student = load_tinyspan_model(
        args.student_checkpoint,
        args.scale,
        args.student_channels,
        args.student_blocks,
        device,
        half,
        channels_last,
    )

    if args.input.is_dir():
        frames, source = image_dir_source(args.input, args.frames, args.fps)
    elif args.input.suffix.lower() in VIDEO_EXTS:
        frames, source = video_source(args.input, args.frames)
    else:
        frames, source = image_source(args.input, args.frames, args.fps, args.width, args.height, args.motion)

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    frame_rows: list[dict[str, float | int]] = []
    first_lr: Image.Image | None = None
    first_bicubic: Image.Image | None = None
    first_teacher: Image.Image | None = None
    first_student: Image.Image | None = None
    first_diff: Image.Image | None = None
    prev_teacher: torch.Tensor | None = None
    prev_student: torch.Tensor | None = None
    teacher_s = 0.0
    student_s = 0.0
    start = time.perf_counter()

    with torch.inference_mode():
        for frame_index, frame in enumerate(frames):
            lr = resize_lr(frame, args.width, args.height)
            tensor = image_to_tensor(lr, device, half, channels_last)

            t0 = time.perf_counter()
            teacher_out = teacher(tensor)
            sync(device)
            teacher_s += time.perf_counter() - t0

            t0 = time.perf_counter()
            student_out = student(tensor)
            sync(device)
            student_s += time.perf_counter() - t0

            row = tensor_diff_metrics(student_out, teacher_out)
            if prev_teacher is not None and prev_student is not None:
                temporal = tensor_delta_metrics(student_out - prev_student, teacher_out - prev_teacher)
                row.update(temporal)
            else:
                row.update(
                    {
                        "temporal_mse": "",
                        "temporal_mae": "",
                        "temporal_max_abs": "",
                        "temporal_psnr_db": "",
                    }
                )
            frame_rows.append({"frame": frame_index, **row})
            prev_teacher = teacher_out.detach()
            prev_student = student_out.detach()

            if first_lr is None:
                teacher_rgb = tensor_to_rgb_u8(teacher_out)
                student_rgb = tensor_to_rgb_u8(student_out)
                first_lr = lr
                first_bicubic = lr.resize((lr.width * scale, lr.height * scale), Image.Resampling.BICUBIC)
                first_teacher = Image.fromarray(teacher_rgb, "RGB")
                first_student = Image.fromarray(student_rgb, "RGB")
                first_diff = diff_image(student_rgb, teacher_rgb, args.diff_gain)

    total_s = time.perf_counter() - start
    if not frame_rows:
        raise SystemExit("no frames were processed")

    mse_values = [float(row["mse"]) for row in frame_rows]
    mae_values = [float(row["mae"]) for row in frame_rows]
    psnr_values = [float(row["psnr_db"]) for row in frame_rows]
    max_abs_values = [float(row["max_abs"]) for row in frame_rows]
    temporal_rows = [row for row in frame_rows if row["temporal_mae"] != ""]
    temporal_mse_values = [float(row["temporal_mse"]) for row in temporal_rows]
    temporal_mae_values = [float(row["temporal_mae"]) for row in temporal_rows]
    temporal_psnr_values = [float(row["temporal_psnr_db"]) for row in temporal_rows]
    temporal_max_abs_values = [float(row["temporal_max_abs"]) for row in temporal_rows]
    metrics = {
        "input": str(args.input),
        "source_mode": source.mode,
        "source_fps": source.fps,
        "manifest": str(manifest_path),
        "teacher_checkpoint": str(teacher_checkpoint),
        "student_checkpoint": str(args.student_checkpoint),
        "scale": scale,
        "student_channels": args.student_channels,
        "student_blocks": args.student_blocks,
        "frames": len(frame_rows),
        "input_width": args.width,
        "input_height": args.height,
        "output_width": args.width * scale,
        "output_height": args.height * scale,
        "device": torch.cuda.get_device_name(device) if device.type == "cuda" else "cpu",
        "dtype": "fp16" if half else "fp32",
        "channels_last": channels_last,
        "tf32": bool(args.tf32 and device.type == "cuda"),
        "mse_mean": float(sum(mse_values) / len(mse_values)),
        "mae_mean": float(sum(mae_values) / len(mae_values)),
        "psnr_db_mean": finite_mean(psnr_values),
        "psnr_db_min": float(min(psnr_values)),
        "max_abs_max": float(max(max_abs_values)),
        "temporal_frames": len(temporal_rows),
        "temporal_mse_mean": float(sum(temporal_mse_values) / len(temporal_mse_values)) if temporal_mse_values else 0.0,
        "temporal_mae_mean": float(sum(temporal_mae_values) / len(temporal_mae_values)) if temporal_mae_values else 0.0,
        "temporal_psnr_db_mean": finite_mean(temporal_psnr_values) if temporal_psnr_values else float("inf"),
        "temporal_psnr_db_min": float(min(temporal_psnr_values)) if temporal_psnr_values else float("inf"),
        "temporal_max_abs_max": float(max(temporal_max_abs_values)) if temporal_max_abs_values else 0.0,
        "teacher_ms_per_frame": teacher_s / len(frame_rows) * 1000.0,
        "student_ms_per_frame": student_s / len(frame_rows) * 1000.0,
        "total_elapsed_s": total_s,
        "diff_gain": args.diff_gain,
    }

    metrics_path = out_dir / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    csv_path = out_dir / "frame_metrics.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "frame",
                "mse",
                "mae",
                "max_abs",
                "psnr_db",
                "temporal_mse",
                "temporal_mae",
                "temporal_max_abs",
                "temporal_psnr_db",
            ],
        )
        writer.writeheader()
        writer.writerows(frame_rows)

    assert first_lr is not None
    assert first_bicubic is not None
    assert first_teacher is not None
    assert first_student is not None
    assert first_diff is not None
    preview_path = out_dir / f"{source.name}_tinyspan_teacher_quality_x{scale}.png"
    make_quality_preview(
        preview_path,
        f"TinySPAN C{args.student_channels}/B{args.student_blocks} vs official SPAN X{scale}",
        first_lr,
        first_bicubic,
        first_teacher,
        first_student,
        first_diff,
        metrics,
        args.preview_tile,
    )

    first_teacher.save(out_dir / f"{source.name}_teacher_x{scale}.png")
    first_student.save(out_dir / f"{source.name}_student_x{scale}.png")
    first_diff.save(out_dir / f"{source.name}_student_teacher_diff_x{scale}.png")

    print(json.dumps(metrics, indent=2))
    print(f"metrics: {metrics_path}")
    print(f"frame metrics: {csv_path}")
    print(f"preview: {preview_path}")


if __name__ == "__main__":
    main()
