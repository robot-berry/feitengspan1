"""Stream video frames through official SPAN on GPU.

Unlike run_span_gpu_realtime.py, this script keeps only one frame in flight and
measures end-to-end decode/preprocess, inference, postprocess, and encode time.
It is the software rehearsal for a realtime video super-resolution pipeline.
"""

from __future__ import annotations

import argparse
import json
import queue
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import numpy as np
import torch
from PIL import Image

from run_span_gpu_realtime import (
    configure_torch,
    default_manifest,
    image_to_tensor,
    load_manifest,
    load_model,
    make_comparison,
    resize_lr,
    resolve_checkpoint,
    sync,
)


VIDEO_EXTS = {".avi", ".mkv", ".mov", ".mp4", ".webm"}


@dataclass
class SourceInfo:
    name: str
    fps: float
    frames_expected: int
    mode: str


@dataclass
class Timings:
    read_s: float = 0.0
    preprocess_s: float = 0.0
    inference_s: float = 0.0
    postprocess_s: float = 0.0
    encode_enqueue_s: float = 0.0
    encode_s: float = 0.0

    def total(self) -> float:
        return self.read_s + self.preprocess_s + self.inference_s + self.postprocess_s + self.encode_enqueue_s


def open_cv2():
    try:
        import cv2
    except ImportError as exc:
        raise SystemExit("OpenCV is required for streaming video output. Install opencv-python.") from exc
    return cv2


def crop_to_aspect(img: Image.Image, aspect: float, phase: float) -> Image.Image:
    src_aspect = img.width / img.height
    if abs(src_aspect - aspect) < 1e-6:
        return img
    if src_aspect > aspect:
        crop_w = round(img.height * aspect)
        travel = max(0, img.width - crop_w)
        left = round(travel * phase)
        return img.crop((left, 0, left + crop_w, img.height))
    crop_h = round(img.width / aspect)
    travel = max(0, img.height - crop_h)
    top = round(travel * phase)
    return img.crop((0, top, img.width, top + crop_h))


def image_source(path: Path, frames: int, fps: float, width: int, height: int, motion: bool) -> tuple[Iterator[Image.Image], SourceInfo]:
    base = Image.open(path).convert("RGB")
    aspect = width / height

    def gen() -> Iterator[Image.Image]:
        denom = max(frames - 1, 1)
        for idx in range(frames):
            if motion:
                phase = 0.5 - 0.5 * np.cos(2.0 * np.pi * idx / denom)
                frame = crop_to_aspect(base, aspect, float(phase))
            else:
                frame = base
            yield frame

    return gen(), SourceInfo(name=path.stem, fps=fps, frames_expected=frames, mode="image_sequence")


def video_source(path: Path, max_frames: int) -> tuple[Iterator[Image.Image], SourceInfo]:
    cv2 = open_cv2()
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise SystemExit(f"failed to open video: {path}")
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 30.0)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    limit = min(total, max_frames) if max_frames > 0 and total > 0 else max_frames

    def gen() -> Iterator[Image.Image]:
        seen = 0
        try:
            while max_frames <= 0 or seen < max_frames:
                ok, frame_bgr = cap.read()
                if not ok:
                    break
                frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
                seen += 1
                yield Image.fromarray(frame_rgb, "RGB")
        finally:
            cap.release()

    expected = limit if limit > 0 else total
    return gen(), SourceInfo(name=path.stem, fps=fps, frames_expected=expected, mode="video")


def make_writer(path: Path, fps: float, size: tuple[int, int]):
    cv2 = open_cv2()
    path.parent.mkdir(parents=True, exist_ok=True)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, size)
    if not writer.isOpened():
        raise SystemExit(f"failed to open output video writer: {path}")
    return writer


class AsyncVideoWriter:
    def __init__(self, path: Path, fps: float, size: tuple[int, int], max_queue: int = 4) -> None:
        self.cv2 = open_cv2()
        self.writer = make_writer(path, fps, size)
        self.queue: queue.Queue[np.ndarray | None] = queue.Queue(maxsize=max_queue)
        self.encode_s = 0.0
        self.frames = 0
        self.error: BaseException | None = None
        self.thread = threading.Thread(target=self._run, name="span-video-writer", daemon=True)
        self.thread.start()

    def _run(self) -> None:
        try:
            while True:
                frame = self.queue.get()
                try:
                    if frame is None:
                        return
                    t0 = time.perf_counter()
                    self.writer.write(self.cv2.cvtColor(frame, self.cv2.COLOR_RGB2BGR))
                    self.encode_s += time.perf_counter() - t0
                    self.frames += 1
                finally:
                    self.queue.task_done()
        except BaseException as exc:  # pragma: no cover - propagated on close
            self.error = exc

    def write(self, frame_rgb: np.ndarray) -> None:
        self.queue.put(frame_rgb)

    def close(self) -> None:
        self.queue.put(None)
        self.queue.join()
        self.thread.join()
        self.writer.release()
        if self.error is not None:
            raise RuntimeError("async video writer failed") from self.error


def tensor_to_rgb_u8(tensor: torch.Tensor) -> np.ndarray:
    out = tensor.detach().clamp(0, 1).mul(255).round().to(torch.uint8)
    return out.squeeze(0).permute(1, 2, 0).contiguous().cpu().numpy()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stream official SPAN over video frames and measure end-to-end FPS.")
    parser.add_argument("--input", type=Path, default=Path("external/SPAN/test_scripts/data/baboon.png"))
    parser.add_argument("--out-dir", type=Path, default=Path("runs/span_video_stream/latest"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--device", default="cuda", choices=("auto", "cuda", "cpu"))
    parser.add_argument("--half", action="store_true")
    parser.add_argument("--channels-last", action="store_true")
    parser.add_argument("--tf32", action="store_true")
    parser.add_argument("--width", type=int, default=320, help="Low-resolution stream width.")
    parser.add_argument("--height", type=int, default=180, help="Low-resolution stream height.")
    parser.add_argument("--frames", type=int, default=60, help="Frame count for image input, or max frames for video input.")
    parser.add_argument("--fps", type=float, default=30.0, help="Output FPS for image input.")
    parser.add_argument("--motion", action="store_true", help="Pan across an image input instead of repeating it exactly.")
    parser.add_argument("--async-writer", action="store_true", help="Encode frames in a background thread.")
    parser.add_argument("--writer-queue", type=int, default=4, help="Maximum queued frames for --async-writer.")
    parser.add_argument("--preview-tile", type=int, default=240)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest_path = args.manifest or default_manifest(args.scale)
    manifest = load_manifest(manifest_path)
    scale = int(manifest["scale"])
    if scale != args.scale:
        raise SystemExit(f"manifest scale X{scale} does not match --scale X{args.scale}")

    if args.device == "auto":
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        device = torch.device(args.device)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise SystemExit("CUDA was requested but torch.cuda.is_available() is false")

    half = bool(args.half and device.type == "cuda")
    channels_last = bool(args.channels_last and device.type == "cuda")
    configure_torch(bool(args.tf32 and device.type == "cuda"))
    checkpoint = resolve_checkpoint(manifest, args.checkpoint)
    model = load_model(manifest, checkpoint, device, half, channels_last)

    if args.input.suffix.lower() in VIDEO_EXTS:
        frames, source = video_source(args.input, args.frames)
    else:
        frames, source = image_source(args.input, args.frames, args.fps, args.width, args.height, args.motion)

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    output_path = args.output or (out_dir / f"{source.name}_span_stream_x{scale}.mp4")

    writer = None
    writer_is_async = False
    cv2 = open_cv2()
    timings = Timings()
    frame_count = 0
    first_lr: Image.Image | None = None
    first_sr: Image.Image | None = None
    first_bicubic: Image.Image | None = None
    start_total = time.perf_counter()

    try:
        iterator = iter(frames)
        while True:
            t0 = time.perf_counter()
            try:
                frame = next(iterator)
            except StopIteration:
                break
            timings.read_s += time.perf_counter() - t0

            t0 = time.perf_counter()
            lr = resize_lr(frame, args.width, args.height)
            tensor = image_to_tensor(lr, device, half, channels_last)
            timings.preprocess_s += time.perf_counter() - t0

            t0 = time.perf_counter()
            with torch.inference_mode():
                out = model(tensor)
            sync(device)
            timings.inference_s += time.perf_counter() - t0

            t0 = time.perf_counter()
            sr_rgb = tensor_to_rgb_u8(out)
            timings.postprocess_s += time.perf_counter() - t0

            if writer is None:
                out_size = (int(sr_rgb.shape[1]), int(sr_rgb.shape[0]))
                if args.async_writer:
                    writer = AsyncVideoWriter(output_path, source.fps or args.fps, out_size, args.writer_queue)
                    writer_is_async = True
                else:
                    writer = make_writer(output_path, source.fps or args.fps, out_size)

            t0 = time.perf_counter()
            if writer_is_async:
                writer.write(sr_rgb)
                timings.encode_enqueue_s += time.perf_counter() - t0
            else:
                writer.write(cv2.cvtColor(sr_rgb, cv2.COLOR_RGB2BGR))
                timings.encode_s += time.perf_counter() - t0

            if first_lr is None:
                first_lr = lr
                first_sr = Image.fromarray(sr_rgb, "RGB")
                first_bicubic = lr.resize(first_sr.size, Image.Resampling.BICUBIC)
            frame_count += 1
    finally:
        if writer is not None:
            if writer_is_async:
                writer.close()
                timings.encode_s = writer.encode_s
            else:
                writer.release()

    elapsed = time.perf_counter() - start_total
    fps = frame_count / elapsed if elapsed > 0 else 0.0
    if frame_count == 0:
        raise SystemExit("no frames were processed")

    metrics = {
        "input": str(args.input),
        "output": str(output_path),
        "source_mode": source.mode,
        "source_fps": source.fps,
        "frames": frame_count,
        "scale": scale,
        "input_width": args.width,
        "input_height": args.height,
        "output_width": args.width * scale,
        "output_height": args.height * scale,
        "device": torch.cuda.get_device_name(device) if device.type == "cuda" else "cpu",
        "dtype": "fp16" if half else "fp32",
        "channels_last": channels_last,
        "tf32": bool(args.tf32 and device.type == "cuda"),
        "async_writer": bool(args.async_writer),
        "writer_queue": int(args.writer_queue),
        "end_to_end_fps": fps,
        "end_to_end_latency_ms": 1000.0 / fps if fps > 0 else 0.0,
        "total_elapsed_s": elapsed,
        "read_s": timings.read_s,
        "preprocess_s": timings.preprocess_s,
        "inference_s": timings.inference_s,
        "postprocess_s": timings.postprocess_s,
        "encode_enqueue_s": timings.encode_enqueue_s,
        "encode_s": timings.encode_s,
        "read_ms_per_frame": timings.read_s / frame_count * 1000.0,
        "preprocess_ms_per_frame": timings.preprocess_s / frame_count * 1000.0,
        "inference_ms_per_frame": timings.inference_s / frame_count * 1000.0,
        "postprocess_ms_per_frame": timings.postprocess_s / frame_count * 1000.0,
        "encode_enqueue_ms_per_frame": timings.encode_enqueue_s / frame_count * 1000.0,
        "encode_ms_per_frame": timings.encode_s / frame_count * 1000.0,
    }
    metrics_path = out_dir / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    assert first_lr is not None and first_bicubic is not None and first_sr is not None
    preview_path = out_dir / f"{source.name}_stream_comparison_x{scale}.png"
    make_comparison(preview_path, f"SPAN stream X{scale}", first_lr, first_bicubic, first_sr, {"device": metrics["device"], "dtype": metrics["dtype"], "fps": fps, "latency_ms": metrics["end_to_end_latency_ms"]}, args.preview_tile)

    print(json.dumps(metrics, indent=2))
    print(f"metrics: {metrics_path}")
    print(f"preview: {preview_path}")
    print(f"video: {output_path}")


if __name__ == "__main__":
    main()
