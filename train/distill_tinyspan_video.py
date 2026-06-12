"""Distill TinySPAN with paired video-frame temporal consistency.

The image distiller teaches per-frame quality. This script adds a lightweight
video-specific signal: adjacent student SR frame differences should match the
official SPAN teacher's adjacent-frame differences. It is intended for REDS or
other extracted video-frame folders, with a synthetic single-image motion mode
kept for smoke tests.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import random
import time
from pathlib import Path

os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import torch
from PIL import Image, ImageDraw
from torch import nn
from torch.amp import GradScaler, autocast
from torch.utils.data import DataLoader, Dataset
from torchvision.transforms.functional import to_tensor
from tqdm import tqdm

from distill_tinyspan_from_official import default_manifest, load_manifest, load_teacher, resolve_checkpoint
from reds_dataset import IMAGE_EXTS, bicubic_downsample, psnr, sobel_edges
from span_model import build_model


def list_sequence_images(root: Path) -> list[list[Path]]:
    if root.is_file() and root.suffix.lower() in IMAGE_EXTS:
        return [[root]]
    if not root.is_dir():
        raise FileNotFoundError(root)

    direct = sorted(p for p in root.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    if direct:
        return [direct]

    sequences: list[list[Path]] = []
    for child in sorted(p for p in root.iterdir() if p.is_dir()):
        frames = sorted(p for p in child.rglob("*") if p.suffix.lower() in IMAGE_EXTS)
        if frames:
            sequences.append(frames)
    if not sequences:
        frames = sorted(p for p in root.rglob("*") if p.suffix.lower() in IMAGE_EXTS)
        if frames:
            sequences.append(frames)
    return sequences


def synthetic_motion_frames(base: Image.Image, count: int) -> list[Image.Image]:
    """Create a deterministic pan/zoom sequence from one image for smoke tests."""
    count = max(2, count)
    crop_w = max(1, round(base.width * 0.88))
    crop_h = max(1, round(base.height * 0.88))
    travel_x = max(0, base.width - crop_w)
    travel_y = max(0, base.height - crop_h)
    denom = max(count - 1, 1)
    frames: list[Image.Image] = []
    for idx in range(count):
        phase = idx / denom
        x_phase = 0.5 - 0.5 * math.cos(2.0 * math.pi * phase)
        y_phase = 0.5 - 0.5 * math.cos(2.0 * math.pi * ((phase + 0.25) % 1.0))
        left = round(travel_x * x_phase)
        top = round(travel_y * y_phase)
        crop = base.crop((left, top, left + crop_w, top + crop_h))
        frames.append(crop.resize(base.size, Image.Resampling.BICUBIC))
    return frames


class VideoPairDistillDataset(Dataset):
    """Return adjacent HR/LR crop pairs for video distillation."""

    def __init__(
        self,
        root: str | Path,
        scale: int,
        patch_size: int,
        augment: bool,
        synthetic_frames: int,
        max_pairs: int | None,
        seed: int,
    ) -> None:
        self.root = Path(root)
        self.scale = scale
        self.patch_size = patch_size
        self.augment = augment
        self.synthetic_frames = synthetic_frames
        self.rng = random.Random(seed)
        self.synthetic: list[Image.Image] | None = None

        if patch_size % scale != 0:
            raise ValueError("patch_size must be divisible by scale")

        sequences = list_sequence_images(self.root)
        if len(sequences) == 1 and len(sequences[0]) == 1:
            base = Image.open(sequences[0][0]).convert("RGB")
            self.synthetic = synthetic_motion_frames(base, synthetic_frames)
            self.pairs = [(idx, idx + 1) for idx in range(len(self.synthetic) - 1)]
        else:
            self.frames: list[Path] = []
            self.pairs: list[tuple[int, int]] = []
            for sequence in sequences:
                if len(sequence) < 2:
                    continue
                offset = len(self.frames)
                self.frames.extend(sequence)
                self.pairs.extend((offset + idx, offset + idx + 1) for idx in range(len(sequence) - 1))

        if max_pairs is not None:
            self.pairs = self.pairs[:max_pairs]
        if not self.pairs:
            raise FileNotFoundError(f"No adjacent frame pairs found under {self.root}")

    def __len__(self) -> int:
        return len(self.pairs)

    def load_hr(self, index: int) -> Image.Image:
        if self.synthetic is not None:
            return self.synthetic[index].copy()
        return Image.open(self.frames[index]).convert("RGB")

    def paired_crop(self, hr0: Image.Image, hr1: Image.Image) -> tuple[Image.Image, Image.Image]:
        w = min(hr0.width, hr1.width)
        h = min(hr0.height, hr1.height)
        hr0 = hr0.crop((0, 0, w, h))
        hr1 = hr1.crop((0, 0, w, h))
        crop = min(self.patch_size, w - (w % self.scale), h - (h % self.scale))
        if crop < self.scale:
            raise ValueError(f"Frame pair too small for scale {self.scale}: {w}x{h}")
        if self.augment:
            x = self.rng.randint(0, w - crop)
            y = self.rng.randint(0, h - crop)
        else:
            x = max(0, (w - crop) // 2)
            y = max(0, (h - crop) // 2)
        hr0 = hr0.crop((x, y, x + crop, y + crop))
        hr1 = hr1.crop((x, y, x + crop, y + crop))

        if self.augment and self.rng.random() < 0.5:
            hr0 = hr0.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            hr1 = hr1.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if self.augment and self.rng.random() < 0.5:
            hr0 = hr0.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            hr1 = hr1.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        if self.augment:
            rot = self.rng.randint(0, 3)
            if rot:
                hr0 = hr0.rotate(90 * rot, expand=True)
                hr1 = hr1.rotate(90 * rot, expand=True)
        return hr0, hr1

    def __getitem__(self, index: int) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        idx0, idx1 = self.pairs[index]
        hr0, hr1 = self.paired_crop(self.load_hr(idx0), self.load_hr(idx1))
        lr0 = bicubic_downsample(hr0, self.scale)
        lr1 = bicubic_downsample(hr1, self.scale)
        return to_tensor(lr0), to_tensor(hr0), to_tensor(lr1), to_tensor(hr1)


def append_csv(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    exists = path.exists()
    fieldnames = [
        "epoch",
        "step",
        "loss",
        "distill_loss",
        "hr_loss",
        "edge_loss",
        "temporal_loss",
        "teacher_psnr",
        "student_psnr",
        "seconds",
        "steps_per_second",
    ]
    with path.open("a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if not exists:
            writer.writeheader()
        writer.writerow({k: row.get(k, "") for k in fieldnames})


def tensor_to_image(x: torch.Tensor) -> Image.Image:
    img = x.detach().float().clamp(0, 1).squeeze(0).permute(1, 2, 0).cpu()
    data = (img * 255.0).round().to(torch.uint8).numpy()
    return Image.fromarray(data, "RGB")


def fit_tile(img: Image.Image, tile: int) -> Image.Image:
    out = img.copy()
    out.thumbnail((tile, tile), Image.Resampling.BICUBIC)
    canvas = Image.new("RGB", (tile, tile), (18, 22, 28))
    canvas.paste(out, ((tile - out.width) // 2, (tile - out.height) // 2))
    return canvas


def make_preview(
    path: Path,
    lr0: torch.Tensor,
    teacher0: torch.Tensor,
    student0: torch.Tensor,
    teacher_delta: torch.Tensor,
    student_delta: torch.Tensor,
    title: str,
) -> None:
    panels = [
        ("LR frame", fit_tile(tensor_to_image(lr0), 170)),
        ("Teacher", fit_tile(tensor_to_image(teacher0), 170)),
        ("Student", fit_tile(tensor_to_image(student0), 170)),
        ("Teacher delta", fit_tile(tensor_to_image(teacher_delta.abs() * 4.0), 170)),
        ("Student delta", fit_tile(tensor_to_image(student_delta.abs() * 4.0), 170)),
    ]
    gap = 12
    label_h = 28
    title_h = 40
    width = len(panels) * 170 + (len(panels) + 1) * gap
    height = title_h + label_h + 170 + gap
    canvas = Image.new("RGB", (width, height), (246, 248, 250))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 12), title, fill=(20, 24, 31))
    x = gap
    for label, img in panels:
        draw.text((x, title_h), label, fill=(32, 37, 45))
        canvas.paste(img, (x, title_h + label_h))
        x += 170 + gap
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def load_student_checkpoint(student: nn.Module, checkpoint: Path) -> None:
    ckpt = torch.load(checkpoint, map_location="cpu")
    state = ckpt["model"] if isinstance(ckpt, dict) and "model" in ckpt else ckpt
    student.load_state_dict(state, strict=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Video-frame distillation for realtime TinySPAN.")
    parser.add_argument("--train-frames", default="external/SPAN/test_scripts/data/baboon.png")
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--channels", type=int, default=16)
    parser.add_argument("--num-blocks", type=int, default=3)
    parser.add_argument("--patch-size", type=int, default=128)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--epochs", type=int, default=1)
    parser.add_argument("--max-steps", type=int, default=20)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--max-pairs", type=int, default=None)
    parser.add_argument("--synthetic-frames", type=int, default=16)
    parser.add_argument("--teacher-manifest", type=Path)
    parser.add_argument("--teacher-checkpoint", default=None)
    parser.add_argument("--resume-student", type=Path)
    parser.add_argument("--distill-weight", type=float, default=1.0)
    parser.add_argument("--hr-weight", type=float, default=0.2)
    parser.add_argument("--edge-weight", type=float, default=0.02)
    parser.add_argument("--temporal-weight", type=float, default=0.2)
    parser.add_argument("--amp", action="store_true")
    parser.add_argument("--output", default="runs/tinyspan_distill/video_smoke_x4_c16_b3")
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    random.seed(args.seed)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "args.json").write_text(json.dumps(vars(args), indent=2, default=str), encoding="utf-8")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    teacher_manifest = load_manifest(args.teacher_manifest or default_manifest(args.scale))
    teacher_checkpoint = resolve_checkpoint(teacher_manifest, args.teacher_checkpoint)
    teacher = load_teacher(teacher_manifest, teacher_checkpoint, device, args.amp and device.type == "cuda")
    student = build_model(scale=args.scale, channels=args.channels, num_blocks=args.num_blocks).to(device)
    if args.resume_student is not None:
        load_student_checkpoint(student, args.resume_student)
    optimizer = torch.optim.AdamW(student.parameters(), lr=args.lr, betas=(0.9, 0.99))
    scaler = GradScaler("cuda", enabled=args.amp and device.type == "cuda")
    l1 = nn.L1Loss()

    dataset = VideoPairDistillDataset(
        args.train_frames,
        scale=args.scale,
        patch_size=args.patch_size,
        augment=True,
        synthetic_frames=args.synthetic_frames,
        max_pairs=args.max_pairs,
        seed=args.seed,
    )
    loader = DataLoader(
        dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.num_workers,
        pin_memory=device.type == "cuda",
        drop_last=False,
    )

    start = time.perf_counter()
    step = 0
    last_batch = None
    for epoch in range(args.epochs):
        progress = tqdm(loader, desc=f"video distill epoch {epoch + 1}/{args.epochs}")
        for lr0, hr0, lr1, hr1 in progress:
            step += 1
            lr0 = lr0.to(device, non_blocking=True)
            hr0 = hr0.to(device, non_blocking=True)
            lr1 = lr1.to(device, non_blocking=True)
            hr1 = hr1.to(device, non_blocking=True)
            teacher_lr0 = lr0.half() if args.amp and device.type == "cuda" else lr0
            teacher_lr1 = lr1.half() if args.amp and device.type == "cuda" else lr1
            with torch.no_grad():
                teacher0 = teacher(teacher_lr0).float().clamp(0, 1)
                teacher1 = teacher(teacher_lr1).float().clamp(0, 1)

            optimizer.zero_grad(set_to_none=True)
            with autocast("cuda", enabled=args.amp and device.type == "cuda"):
                student0 = student(lr0).clamp(0, 1)
                student1 = student(lr1).clamp(0, 1)
                distill_loss = 0.5 * (l1(student0, teacher0) + l1(student1, teacher1))
                hr_loss = 0.5 * (l1(student0, hr0) + l1(student1, hr1))
                edge_loss = 0.5 * (
                    l1(sobel_edges(student0), sobel_edges(teacher0))
                    + l1(sobel_edges(student1), sobel_edges(teacher1))
                )
                temporal_loss = l1(student1 - student0, teacher1 - teacher0)
                loss = (
                    args.distill_weight * distill_loss
                    + args.hr_weight * hr_loss
                    + args.edge_weight * edge_loss
                    + args.temporal_weight * temporal_loss
                )
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()

            with torch.no_grad():
                teacher_score = 0.5 * (psnr(teacher0, hr0, border=args.scale) + psnr(teacher1, hr1, border=args.scale))
                student_score = 0.5 * (psnr(student0, hr0, border=args.scale) + psnr(student1, hr1, border=args.scale))
            elapsed = time.perf_counter() - start
            row = {
                "epoch": epoch + 1,
                "step": step,
                "loss": f"{float(loss.item()):.8f}",
                "distill_loss": f"{float(distill_loss.item()):.8f}",
                "hr_loss": f"{float(hr_loss.item()):.8f}",
                "edge_loss": f"{float(edge_loss.item()):.8f}",
                "temporal_loss": f"{float(temporal_loss.item()):.8f}",
                "teacher_psnr": f"{teacher_score:.6f}",
                "student_psnr": f"{student_score:.6f}",
                "seconds": f"{elapsed:.3f}",
                "steps_per_second": f"{step / max(elapsed, 1e-9):.4f}",
            }
            append_csv(output / "metrics.csv", row)
            progress.set_postfix(loss=row["loss"], temporal=row["temporal_loss"], student_psnr=row["student_psnr"])
            last_batch = (
                lr0.detach().cpu(),
                teacher0.detach().cpu(),
                student0.detach().cpu(),
                (teacher1 - teacher0).detach().cpu(),
                (student1 - student0).detach().cpu(),
            )
            if args.max_steps and step >= args.max_steps:
                break
        if args.max_steps and step >= args.max_steps:
            break

    ckpt = {
        "model": student.state_dict(),
        "scale": args.scale,
        "channels": args.channels,
        "num_blocks": args.num_blocks,
        "steps": step,
        "teacher_checkpoint": str(teacher_checkpoint),
        "resume_student": str(args.resume_student) if args.resume_student else "",
        "temporal_weight": args.temporal_weight,
    }
    torch.save(ckpt, output / "student_last.pt")
    if last_batch is not None:
        lr0, teacher0, student0, teacher_delta, student_delta = last_batch
        make_preview(
            output / "video_distill_preview.png",
            lr0[:1],
            teacher0[:1],
            student0[:1],
            teacher_delta[:1],
            student_delta[:1],
            f"TinySPAN C{args.channels}/B{args.num_blocks} video distill",
        )
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
