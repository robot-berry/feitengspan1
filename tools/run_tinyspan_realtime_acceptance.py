"""Run the TinySPAN realtime acceptance gate.

This wraps the two checks that matter for video SR:

1. end-to-end stream throughput and encoded-video readback
2. official-SPAN teacher quality and temporal consistency

The output is a compact PASS/FAIL summary for a TinySPAN checkpoint.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def run_command(cmd: list[str], cwd: Path) -> None:
    print(" ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def video_readback(path: Path) -> dict[str, Any]:
    try:
        import cv2
    except ImportError:
        return {"available": False, "reason": "opencv not available"}

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        return {"available": True, "opened": False}
    try:
        return {
            "available": True,
            "opened": True,
            "frames": int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0),
            "fps": float(cap.get(cv2.CAP_PROP_FPS) or 0.0),
            "width": int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0),
            "height": int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0),
        }
    finally:
        cap.release()


def pass_fail_summary(args: argparse.Namespace, stream: dict[str, Any], quality: dict[str, Any], readback: dict[str, Any]) -> dict[str, Any]:
    expected_w = args.width * args.scale
    expected_h = args.height * args.scale
    checks: dict[str, dict[str, Any]] = {
        "stream_fps": {
            "pass": float(stream["end_to_end_fps"]) >= args.min_fps,
            "value": float(stream["end_to_end_fps"]),
            "target": f">= {args.min_fps}",
        },
        "stream_output_size": {
            "pass": int(stream["output_width"]) == expected_w and int(stream["output_height"]) == expected_h,
            "value": f"{stream['output_width']}x{stream['output_height']}",
            "target": f"{expected_w}x{expected_h}",
        },
        "stream_frame_count": {
            "pass": int(stream["frames"]) == args.stream_frames,
            "value": int(stream["frames"]),
            "target": args.stream_frames,
        },
        "quality_output_size": {
            "pass": int(quality["output_width"]) == expected_w and int(quality["output_height"]) == expected_h,
            "value": f"{quality['output_width']}x{quality['output_height']}",
            "target": f"{expected_w}x{expected_h}",
        },
    }

    if readback.get("available") and readback.get("opened"):
        checks["video_readback"] = {
            "pass": (
                int(readback.get("frames", 0)) == args.stream_frames
                and int(readback.get("width", 0)) == expected_w
                and int(readback.get("height", 0)) == expected_h
            ),
            "value": f"{readback.get('frames')} frames, {readback.get('fps'):.3f} fps, {readback.get('width')}x{readback.get('height')}",
            "target": f"{args.stream_frames} frames, {expected_w}x{expected_h}",
        }
    else:
        checks["video_readback"] = {
            "pass": False,
            "value": readback,
            "target": "OpenCV-readable encoded video",
        }

    if args.min_psnr > 0:
        checks["quality_psnr"] = {
            "pass": float(quality["psnr_db_mean"]) >= args.min_psnr,
            "value": float(quality["psnr_db_mean"]),
            "target": f">= {args.min_psnr}",
        }
    if args.max_temporal_mae >= 0:
        checks["temporal_mae"] = {
            "pass": float(quality["temporal_mae_mean"]) <= args.max_temporal_mae,
            "value": float(quality["temporal_mae_mean"]),
            "target": f"<= {args.max_temporal_mae}",
        }

    return {
        "checkpoint": str(args.checkpoint),
        "scale": args.scale,
        "student_channels": args.student_channels,
        "student_blocks": args.student_blocks,
        "input": str(args.input),
        "target": {
            "input_width": args.width,
            "input_height": args.height,
            "output_width": expected_w,
            "output_height": expected_h,
            "fps": args.min_fps,
        },
        "checks": checks,
        "passed": all(item["pass"] for item in checks.values()),
        "stream_metrics": {
            "end_to_end_fps": stream["end_to_end_fps"],
            "end_to_end_latency_ms": stream["end_to_end_latency_ms"],
            "inference_ms_per_frame": stream["inference_ms_per_frame"],
            "preprocess_ms_per_frame": stream["preprocess_ms_per_frame"],
            "postprocess_ms_per_frame": stream["postprocess_ms_per_frame"],
            "encode_ms_per_frame": stream["encode_ms_per_frame"],
            "metrics": str(args.out_dir / "stream" / "metrics.json"),
            "preview": str(next((args.out_dir / "stream").glob("*_comparison_x*.png"), "")),
            "video": stream["output"],
            "readback": readback,
        },
        "quality_metrics": {
            "psnr_db_mean": quality["psnr_db_mean"],
            "mae_mean": quality["mae_mean"],
            "temporal_mae_mean": quality["temporal_mae_mean"],
            "temporal_psnr_db_mean": quality["temporal_psnr_db_mean"],
            "teacher_ms_per_frame": quality["teacher_ms_per_frame"],
            "student_ms_per_frame": quality["student_ms_per_frame"],
            "metrics": str(args.out_dir / "quality" / "metrics.json"),
            "preview": str(next((args.out_dir / "quality").glob("*_quality_x*.png"), "")),
        },
    }


def write_markdown(path: Path, summary: dict[str, Any]) -> None:
    checks = summary["checks"]
    lines = [
        "# TinySPAN realtime acceptance",
        "",
        f"Checkpoint: `{summary['checkpoint']}`",
        f"Target: X{summary['scale']} `{summary['target']['input_width']}x{summary['target']['input_height']} -> {summary['target']['output_width']}x{summary['target']['output_height']}` at `{summary['target']['fps']} fps`",
        f"Result: `{'PASS' if summary['passed'] else 'FAIL'}`",
        "",
        "## Checks",
        "",
        "| Check | Result | Value | Target |",
        "| --- | --- | ---: | ---: |",
    ]
    for name, item in checks.items():
        result = "PASS" if item["pass"] else "FAIL"
        lines.append(f"| `{name}` | `{result}` | `{item['value']}` | `{item['target']}` |")
    lines.extend(
        [
            "",
            "## Stream",
            "",
            f"- end-to-end FPS: `{summary['stream_metrics']['end_to_end_fps']:.3f}`",
            f"- end-to-end latency: `{summary['stream_metrics']['end_to_end_latency_ms']:.3f} ms/frame`",
            f"- inference: `{summary['stream_metrics']['inference_ms_per_frame']:.3f} ms/frame`",
            f"- video: `{summary['stream_metrics']['video']}`",
            f"- preview: `{summary['stream_metrics']['preview']}`",
            "",
            "## Quality",
            "",
            f"- PSNR vs teacher: `{summary['quality_metrics']['psnr_db_mean']:.3f} dB`",
            f"- MAE vs teacher: `{summary['quality_metrics']['mae_mean']:.6f}`",
            f"- temporal MAE vs teacher delta: `{summary['quality_metrics']['temporal_mae_mean']:.6f}`",
            f"- temporal PSNR: `{summary['quality_metrics']['temporal_psnr_db_mean']:.3f} dB`",
            f"- preview: `{summary['quality_metrics']['preview']}`",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run TinySPAN realtime speed and quality acceptance checks.")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--input", type=Path, default=Path("external/SPAN/test_scripts/data/baboon.png"))
    parser.add_argument("--out-dir", type=Path, default=Path("runs/tinyspan_acceptance/latest"))
    parser.add_argument("--scale", type=int, choices=(2, 4), default=4)
    parser.add_argument("--student-channels", type=int, default=16)
    parser.add_argument("--student-blocks", type=int, default=3)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=180)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--stream-frames", type=int, default=60)
    parser.add_argument("--quality-frames", type=int, default=30)
    parser.add_argument("--min-fps", type=float, default=30.0)
    parser.add_argument("--min-psnr", type=float, default=0.0, help="Disabled when <= 0.")
    parser.add_argument("--max-temporal-mae", type=float, default=-1.0, help="Disabled when < 0.")
    parser.add_argument("--device", default="cuda", choices=("auto", "cuda", "cpu"))
    parser.add_argument("--half", action="store_true")
    parser.add_argument("--async-writer", action="store_true")
    parser.add_argument("--writer-queue", type=int, default=4)
    parser.add_argument("--motion", action="store_true")
    parser.add_argument("--preview-tile", type=int, default=180)
    parser.add_argument("--diff-gain", type=float, default=8.0)
    parser.add_argument("--no-fail-exit", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = repo_root()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    stream_dir = args.out_dir / "stream"
    quality_dir = args.out_dir / "quality"
    stream_dir.mkdir(parents=True, exist_ok=True)
    quality_dir.mkdir(parents=True, exist_ok=True)

    common_model = [
        "--scale",
        str(args.scale),
        "--student-channels",
        str(args.student_channels),
        "--student-blocks",
        str(args.student_blocks),
        "--checkpoint",
        str(args.checkpoint),
        "--input",
        str(args.input),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--fps",
        str(args.fps),
        "--device",
        args.device,
    ]
    if args.half:
        common_model.append("--half")
    if args.motion:
        common_model.append("--motion")

    stream_cmd = [
        sys.executable,
        "tools/run_span_video_stream.py",
        "--model",
        "tinyspan",
        *common_model,
        "--frames",
        str(args.stream_frames),
        "--out-dir",
        str(stream_dir),
        "--preview-tile",
        str(args.preview_tile),
        "--writer-queue",
        str(args.writer_queue),
    ]
    if args.async_writer:
        stream_cmd.append("--async-writer")
    run_command(stream_cmd, root)

    quality_cmd = [
        sys.executable,
        "tools/evaluate_tinyspan_video_quality.py",
        "--student-checkpoint",
        str(args.checkpoint),
        "--scale",
        str(args.scale),
        "--student-channels",
        str(args.student_channels),
        "--student-blocks",
        str(args.student_blocks),
        "--input",
        str(args.input),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--frames",
        str(args.quality_frames),
        "--fps",
        str(args.fps),
        "--device",
        args.device,
        "--out-dir",
        str(quality_dir),
        "--preview-tile",
        str(args.preview_tile),
        "--diff-gain",
        str(args.diff_gain),
    ]
    if args.half:
        quality_cmd.append("--half")
    if args.motion:
        quality_cmd.append("--motion")
    run_command(quality_cmd, root)

    stream_metrics = load_json(stream_dir / "metrics.json")
    quality_metrics = load_json(quality_dir / "metrics.json")
    readback = video_readback(root / stream_metrics["output"])
    summary = pass_fail_summary(args, stream_metrics, quality_metrics, readback)

    summary_json = args.out_dir / "summary.json"
    summary_md = args.out_dir / "summary.md"
    summary_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    write_markdown(summary_md, summary)
    print(json.dumps(summary, indent=2))
    print(f"summary: {summary_json}")
    print(f"report: {summary_md}")
    if not summary["passed"] and not args.no_fail_exit:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
