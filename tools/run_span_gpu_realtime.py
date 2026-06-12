"""Run official SPAN on GPU for image/video realtime prototyping.

The FPGA RTL remains the hardware target. This tool gives us a fast software
reference: run the same official SPAN checkpoint on CUDA, measure throughput,
and emit a visual comparison for every test run.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Iterable

os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import numpy as np
import torch
from PIL import Image, ImageDraw


IMAGE_EXTS = {".bmp", ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"}
VIDEO_EXTS = {".avi", ".mkv", ".mov", ".mp4", ".webm"}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def import_span() -> type[torch.nn.Module]:
    span_root = repo_root() / "external" / "SPAN"
    sys.path.insert(0, str(span_root))
    from basicsr.archs.span_arch import SPAN

    return SPAN


def default_manifest(scale: int) -> Path:
    return repo_root() / "rtl" / "generated" / f"official_span_x{scale}" / "official_span_manifest.json"


def load_manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_checkpoint(manifest: dict, override: Path | None) -> Path:
    if override is not None:
        return override
    ckpt = Path(manifest["source_checkpoint"])
    if ckpt.exists():
        return ckpt
    return repo_root() / ckpt


def configure_torch(tf32: bool) -> None:
    torch.backends.cudnn.benchmark = True
    if hasattr(torch.backends, "cuda"):
        torch.backends.cuda.matmul.allow_tf32 = tf32
    torch.backends.cudnn.allow_tf32 = tf32


def load_model(
    manifest: dict,
    checkpoint: Path,
    device: torch.device,
    half: bool,
    channels_last: bool,
) -> torch.nn.Module:
    SPAN = import_span()
    model = SPAN(
        3,
        3,
        feature_channels=int(manifest.get("channels", 48)),
        upscale=int(manifest["scale"]),
        img_range=float(manifest.get("img_range", 255.0)),
        rgb_mean=tuple(manifest.get("rgb_mean", (0.4488, 0.4371, 0.4040))),
    )
    state = torch.load(checkpoint, map_location="cpu")
    key = manifest.get("checkpoint_state_key", "params_ema")
    if isinstance(state, dict) and key in state:
        state = state[key]
    elif isinstance(state, dict) and "params" in state:
        state = state["params"]
    model.load_state_dict(state, strict=True)
    model.eval().to(device)
    if half:
        model.half()
    if channels_last:
        model.to(memory_format=torch.channels_last)
    return model


def image_to_tensor(img: Image.Image, device: torch.device, half: bool, channels_last: bool) -> torch.Tensor:
    arr = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    tensor = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).to(device)
    if half:
        tensor = tensor.half()
    if channels_last:
        tensor = tensor.contiguous(memory_format=torch.channels_last)
    return tensor


def tensor_to_image(tensor: torch.Tensor) -> Image.Image:
    arr = tensor.detach().float().clamp(0, 1).squeeze(0).permute(1, 2, 0).cpu().numpy()
    arr = np.rint(arr * 255.0).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def run_model(model: torch.nn.Module, tensor: torch.Tensor) -> torch.Tensor:
    with torch.inference_mode():
        return model(tensor)


def sync(device: torch.device) -> None:
    if device.type == "cuda":
        torch.cuda.synchronize(device)


def resize_lr(img: Image.Image, width: int | None, height: int | None) -> Image.Image:
    if width is None and height is None:
        return img.convert("RGB")
    if width is None:
        width = round(img.width * (height / img.height))
    if height is None:
        height = round(img.height * (width / img.width))
    return img.convert("RGB").resize((int(width), int(height)), Image.Resampling.BICUBIC)


def fit_tile(img: Image.Image, tile: int) -> Image.Image:
    fitted = img.copy()
    fitted.thumbnail((tile, tile), Image.Resampling.BICUBIC)
    canvas = Image.new("RGB", (tile, tile), (18, 22, 28))
    canvas.paste(fitted, ((tile - fitted.width) // 2, (tile - fitted.height) // 2))
    return canvas


def mse(a: Image.Image, b: Image.Image) -> float:
    if a.size != b.size:
        b = b.resize(a.size, Image.Resampling.BICUBIC)
    diff = np.asarray(a, dtype=np.float32) - np.asarray(b, dtype=np.float32)
    return float(np.mean(diff * diff))


def make_comparison(
    path: Path,
    title: str,
    lr: Image.Image,
    bicubic: Image.Image,
    span: Image.Image,
    metrics: dict,
    tile: int,
) -> None:
    panels = [
        (f"Input {lr.width}x{lr.height}", fit_tile(lr, tile)),
        (f"Bicubic {bicubic.width}x{bicubic.height}", fit_tile(bicubic, tile)),
        (f"SPAN GPU {span.width}x{span.height}", fit_tile(span, tile)),
    ]
    label_h = 28
    title_h = 42
    summary_h = 32
    gap = 12
    width = len(panels) * tile + (len(panels) + 1) * gap
    height = title_h + label_h + tile + summary_h + 2 * gap
    canvas = Image.new("RGB", (width, height), (246, 248, 250))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 12), title, fill=(20, 24, 31))
    summary = (
        f"device: {metrics['device']}, dtype: {metrics['dtype']}, "
        f"fps: {metrics['fps']:.2f}, latency: {metrics['latency_ms']:.2f} ms"
    )
    draw.text((gap, height - summary_h + 5), summary, fill=(64, 72, 84))
    x = gap
    for label, img in panels:
        draw.text((x, title_h), label, fill=(32, 37, 45))
        canvas.paste(img, (x, title_h + label_h))
        x += tile + gap
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def collect_image_paths(input_path: Path, max_frames: int) -> list[Path]:
    if input_path.is_file():
        return [input_path]
    paths = sorted(p for p in input_path.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    return paths[:max_frames] if max_frames > 0 else paths


def read_video_frames(path: Path, max_frames: int) -> tuple[list[Image.Image], float]:
    try:
        import cv2
    except ImportError as exc:
        raise SystemExit("OpenCV is required for video input. Install opencv-python or pass an image/frames directory.") from exc

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise SystemExit(f"failed to open video: {path}")
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    frames: list[Image.Image] = []
    while max_frames <= 0 or len(frames) < max_frames:
        ok, frame_bgr = cap.read()
        if not ok:
            break
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        frames.append(Image.fromarray(frame_rgb, "RGB"))
    cap.release()
    return frames, fps


def write_video(path: Path, frames: Iterable[Image.Image], fps: float) -> None:
    try:
        import cv2
    except ImportError:
        return

    frames = list(frames)
    if not frames:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps if fps > 0 else 30.0, frames[0].size)
    for img in frames:
        writer.write(cv2.cvtColor(np.asarray(img.convert("RGB")), cv2.COLOR_RGB2BGR))
    writer.release()


def benchmark_frames(
    model: torch.nn.Module,
    frames: list[Image.Image],
    device: torch.device,
    half: bool,
    channels_last: bool,
    scale: int,
    warmup: int,
    repeat: int,
) -> tuple[list[Image.Image], float, float]:
    tensors = [image_to_tensor(frame, device, half, channels_last) for frame in frames]
    if not tensors:
        raise SystemExit("no input frames found")

    with torch.inference_mode():
        for _ in range(warmup):
            _ = model(tensors[0])
        sync(device)

        outputs: list[torch.Tensor] = []
        start = time.perf_counter()
        for _ in range(repeat):
            for tensor in tensors:
                outputs.append(model(tensor))
        sync(device)
        elapsed = time.perf_counter() - start

    count = len(tensors) * repeat
    fps = count / elapsed if elapsed > 0 else 0.0
    latency_ms = elapsed / count * 1000.0 if count else 0.0
    last_outputs = outputs[-len(tensors) :]
    images = [tensor_to_image(out) for out in last_outputs]
    for frame, out in zip(frames, images):
        expected = (frame.width * scale, frame.height * scale)
        if out.size != expected:
            raise RuntimeError(f"model output size mismatch: got {out.size}, expected {expected}")
    return images, fps, latency_ms


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="GPU SPAN image/video benchmark with comparison previews.")
    parser.add_argument("--input", type=Path, default=Path("external/SPAN/test_scripts/data/baboon.png"))
    parser.add_argument("--out-dir", type=Path, default=Path("runs/span_gpu_realtime/latest"))
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--device", default="cuda", choices=("auto", "cuda", "cpu"))
    parser.add_argument("--half", action="store_true", help="Use FP16 on CUDA.")
    parser.add_argument("--channels-last", action="store_true", help="Use NHWC/channels-last tensors and model weights.")
    parser.add_argument("--tf32", action="store_true", help="Allow TF32 kernels for FP32 CUDA inference.")
    parser.add_argument("--compile", action="store_true", help="Try torch.compile(..., mode='reduce-overhead') before benchmarking.")
    parser.add_argument("--width", type=int, help="Resize low-resolution input width before inference.")
    parser.add_argument("--height", type=int, help="Resize low-resolution input height before inference.")
    parser.add_argument("--max-frames", type=int, default=60)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--repeat", type=int, default=20)
    parser.add_argument("--tile", type=int, default=220)
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
    compile_status = "disabled"
    if args.compile:
        if not hasattr(torch, "compile"):
            compile_status = "unavailable"
        else:
            try:
                model = torch.compile(model, mode="reduce-overhead")
                compile_status = "enabled"
            except Exception as exc:
                compile_status = f"failed: {exc}"

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    input_path = args.input
    source_video_fps = 0.0
    if input_path.is_file() and input_path.suffix.lower() in VIDEO_EXTS:
        raw_frames, source_video_fps = read_video_frames(input_path, args.max_frames)
        source_name = input_path.stem
    else:
        image_paths = collect_image_paths(input_path, args.max_frames)
        raw_frames = [Image.open(path).convert("RGB") for path in image_paths]
        source_name = input_path.stem if input_path.is_file() else input_path.name

    lr_frames = [resize_lr(frame, args.width, args.height) for frame in raw_frames]
    sr_frames, fps, latency_ms = benchmark_frames(
        model, lr_frames, device, half, channels_last, scale, args.warmup, max(args.repeat, 1)
    )
    bicubic_frames = [
        frame.resize((frame.width * scale, frame.height * scale), Image.Resampling.BICUBIC) for frame in lr_frames
    ]

    for idx, (lr, bicubic, span) in enumerate(zip(lr_frames, bicubic_frames, sr_frames)):
        stem = f"{source_name}_{idx:04d}" if len(lr_frames) > 1 else source_name
        lr.save(out_dir / f"{stem}_input.png")
        bicubic.save(out_dir / f"{stem}_bicubic_x{scale}.png")
        span.save(out_dir / f"{stem}_span_gpu_x{scale}.png")

    metrics = {
        "input": str(input_path),
        "manifest": str(manifest_path),
        "checkpoint": str(checkpoint),
        "scale": scale,
        "frames": len(lr_frames),
        "input_width": lr_frames[0].width,
        "input_height": lr_frames[0].height,
        "output_width": sr_frames[0].width,
        "output_height": sr_frames[0].height,
        "source_video_fps": source_video_fps,
        "device": torch.cuda.get_device_name(device) if device.type == "cuda" else "cpu",
        "dtype": "fp16" if half else "fp32",
        "channels_last": channels_last,
        "tf32": bool(args.tf32 and device.type == "cuda"),
        "torch_compile": compile_status,
        "fps": fps,
        "latency_ms": latency_ms,
        "span_vs_bicubic_mse_first_frame": mse(sr_frames[0], bicubic_frames[0]),
    }
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    preview_path = out_dir / f"{source_name}_comparison_x{scale}.png"
    make_comparison(preview_path, f"Official SPAN GPU X{scale}", lr_frames[0], bicubic_frames[0], sr_frames[0], metrics, args.tile)
    write_video(out_dir / f"{source_name}_span_gpu_x{scale}.mp4", sr_frames, source_video_fps or fps)

    print(json.dumps(metrics, indent=2))
    print(f"comparison: {preview_path}")


if __name__ == "__main__":
    main()
