"""Distill a lightweight TinySPAN student from the official SPAN teacher."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from pathlib import Path

os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

import torch
from PIL import Image, ImageDraw
from torch import nn
from torch.amp import GradScaler, autocast
from torch.utils.data import DataLoader
from tqdm import tqdm

from reds_dataset import REDSSISRDataset, psnr, sobel_edges
from span_model import build_model


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_manifest(scale: int) -> Path:
    return repo_root() / "rtl" / "generated" / f"official_span_x{scale}" / "official_span_manifest.json"


def import_official_span(span_root: Path):
    sys.path.insert(0, str(span_root.resolve()))
    from basicsr.archs.span_arch import SPAN

    return SPAN


def load_manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_checkpoint(manifest: dict, checkpoint: str | None) -> Path:
    if checkpoint:
        return Path(checkpoint)
    path = Path(manifest["source_checkpoint"])
    if path.exists():
        return path
    return repo_root() / path


def load_teacher(manifest: dict, checkpoint: Path, device: torch.device, half: bool) -> nn.Module:
    SPAN = import_official_span(repo_root() / "external" / "SPAN")
    teacher = SPAN(
        3,
        3,
        feature_channels=int(manifest.get("channels", 48)),
        upscale=int(manifest["scale"]),
        img_range=float(manifest.get("img_range", 255.0)),
        rgb_mean=tuple(manifest.get("rgb_mean", (0.4488, 0.4371, 0.4040))),
    )
    ckpt = torch.load(checkpoint, map_location="cpu")
    key = manifest.get("checkpoint_state_key", "params_ema")
    state = ckpt[key] if isinstance(ckpt, dict) and key in ckpt else ckpt.get("params", ckpt)
    teacher.load_state_dict(state, strict=True)
    teacher.eval().to(device)
    if half:
        teacher.half()
    for param in teacher.parameters():
        param.requires_grad_(False)
    return teacher


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


def make_preview(path: Path, lr: torch.Tensor, teacher: torch.Tensor, student: torch.Tensor, hr: torch.Tensor, title: str) -> None:
    panels = [
        ("LR input", fit_tile(tensor_to_image(lr), 180)),
        ("Teacher", fit_tile(tensor_to_image(teacher), 180)),
        ("Student", fit_tile(tensor_to_image(student), 180)),
        ("HR", fit_tile(tensor_to_image(hr), 180)),
    ]
    gap = 12
    label_h = 28
    title_h = 40
    width = len(panels) * 180 + (len(panels) + 1) * gap
    height = title_h + label_h + 180 + gap
    canvas = Image.new("RGB", (width, height), (246, 248, 250))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 12), title, fill=(20, 24, 31))
    x = gap
    for label, img in panels:
        draw.text((x, title_h), label, fill=(32, 37, 45))
        canvas.paste(img, (x, title_h + label_h))
        x += 180 + gap
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Distill lightweight TinySPAN from official SPAN.")
    parser.add_argument("--train-hr", default="external/SPAN/test_scripts/data")
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--channels", type=int, default=16)
    parser.add_argument("--num-blocks", type=int, default=3)
    parser.add_argument("--patch-size", type=int, default=128)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--epochs", type=int, default=1)
    parser.add_argument("--max-steps", type=int, default=20)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--train-max-images", type=int, default=None)
    parser.add_argument("--teacher-manifest", type=Path)
    parser.add_argument("--teacher-checkpoint", default=None)
    parser.add_argument("--distill-weight", type=float, default=1.0)
    parser.add_argument("--hr-weight", type=float, default=0.2)
    parser.add_argument("--edge-weight", type=float, default=0.02)
    parser.add_argument("--amp", action="store_true")
    parser.add_argument("--output", default="runs/tinyspan_distill/smoke_x4_c16_b3")
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "args.json").write_text(json.dumps(vars(args), indent=2, default=str), encoding="utf-8")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    teacher_manifest = load_manifest(args.teacher_manifest or default_manifest(args.scale))
    teacher_checkpoint = resolve_checkpoint(teacher_manifest, args.teacher_checkpoint)
    teacher = load_teacher(teacher_manifest, teacher_checkpoint, device, args.amp and device.type == "cuda")
    student = build_model(scale=args.scale, channels=args.channels, num_blocks=args.num_blocks).to(device)
    optimizer = torch.optim.AdamW(student.parameters(), lr=args.lr, betas=(0.9, 0.99))
    scaler = GradScaler("cuda", enabled=args.amp and device.type == "cuda")
    l1 = nn.L1Loss()

    dataset = REDSSISRDataset(
        args.train_hr,
        scale=args.scale,
        patch_size=args.patch_size,
        augment=True,
        jpeg_prob=0.0,
        max_images=args.train_max_images,
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
        progress = tqdm(loader, desc=f"distill epoch {epoch + 1}/{args.epochs}")
        for lr, hr in progress:
            step += 1
            lr = lr.to(device, non_blocking=True)
            hr = hr.to(device, non_blocking=True)
            teacher_lr = lr.half() if args.amp and device.type == "cuda" else lr
            with torch.no_grad():
                teacher_sr = teacher(teacher_lr).float().clamp(0, 1)

            optimizer.zero_grad(set_to_none=True)
            with autocast("cuda", enabled=args.amp and device.type == "cuda"):
                student_sr = student(lr).clamp(0, 1)
                distill_loss = l1(student_sr, teacher_sr)
                hr_loss = l1(student_sr, hr)
                edge_loss = l1(sobel_edges(student_sr), sobel_edges(teacher_sr))
                loss = (
                    args.distill_weight * distill_loss
                    + args.hr_weight * hr_loss
                    + args.edge_weight * edge_loss
                )
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()

            with torch.no_grad():
                teacher_score = psnr(teacher_sr, hr, border=args.scale)
                student_score = psnr(student_sr, hr, border=args.scale)
            elapsed = time.perf_counter() - start
            row = {
                "epoch": epoch + 1,
                "step": step,
                "loss": f"{float(loss.item()):.8f}",
                "distill_loss": f"{float(distill_loss.item()):.8f}",
                "hr_loss": f"{float(hr_loss.item()):.8f}",
                "edge_loss": f"{float(edge_loss.item()):.8f}",
                "teacher_psnr": f"{teacher_score:.6f}",
                "student_psnr": f"{student_score:.6f}",
                "seconds": f"{elapsed:.3f}",
                "steps_per_second": f"{step / max(elapsed, 1e-9):.4f}",
            }
            append_csv(output / "metrics.csv", row)
            progress.set_postfix(loss=row["loss"], student_psnr=row["student_psnr"])
            last_batch = (lr.detach().cpu(), teacher_sr.detach().cpu(), student_sr.detach().cpu(), hr.detach().cpu())
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
    }
    torch.save(ckpt, output / "student_last.pt")
    if last_batch is not None:
        lr, teacher_sr, student_sr, hr = last_batch
        make_preview(output / "distill_preview.png", lr[:1], teacher_sr[:1], student_sr[:1], hr[:1], f"TinySPAN C{args.channels}/B{args.num_blocks} distill")
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
