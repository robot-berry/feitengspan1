import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat


def load_rgb_raw(path: Path, width: int, height: int) -> Image.Image:
    data = path.read_bytes()
    expected = width * height * 3
    if len(data) != expected:
        raise SystemExit(f"raw size mismatch for {path}: got {len(data)}, expected {expected}")
    return Image.frombytes("RGB", (width, height), data)


def load_image(path: Path, raw_width: int | None = None, raw_height: int | None = None) -> Image.Image:
    if path.suffix.lower() == ".rgb":
        if raw_width is None or raw_height is None:
            raise SystemExit(f"raw dimensions are required for {path}")
        return load_rgb_raw(path, raw_width, raw_height)
    return Image.open(path).convert("RGB")


def fit_tile(img: Image.Image, tile: int) -> Image.Image:
    return img.resize((tile, tile), Image.Resampling.NEAREST)


def diff_image(ref: Image.Image, actual: Image.Image, gain: int) -> tuple[Image.Image, int, int]:
    if ref.size != actual.size:
        raise SystemExit(f"diff size mismatch: ref={ref.size}, actual={actual.size}")
    diff = ImageChops.difference(ref, actual)
    stat = ImageStat.Stat(diff)
    max_diff = max(int(v) for v in stat.extrema[0] + stat.extrema[1] + stat.extrema[2])
    data = diff.tobytes()
    mismatch_bytes = sum(1 for b in data if b != 0)
    if gain != 1:
        diff = diff.point(lambda v: min(255, v * gain))
    return diff, max_diff, mismatch_bytes


def main() -> None:
    parser = argparse.ArgumentParser(description="Create an input/reference/actual/diff validation preview.")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--input-width", type=int, required=True)
    parser.add_argument("--input-height", type=int, required=True)
    parser.add_argument("--ref", type=Path, required=True)
    parser.add_argument("--actual", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--title", default="SPAN validation")
    parser.add_argument("--actual-label", default="Actual")
    parser.add_argument("--tile", type=int, default=192)
    parser.add_argument("--diff-gain", type=int, default=16)
    args = parser.parse_args()

    inp = load_image(args.input, args.input_width, args.input_height)
    ref = Image.open(args.ref).convert("RGB")

    panels: list[tuple[str, Image.Image]] = [
        (f"Input {inp.width}x{inp.height}", fit_tile(inp, args.tile)),
        (f"Reference {ref.width}x{ref.height}", fit_tile(ref, args.tile)),
    ]

    summary = "actual: not available"
    if args.actual:
        actual = Image.open(args.actual).convert("RGB")
        diff, max_diff, mismatch_bytes = diff_image(ref, actual, args.diff_gain)
        panels.append((f"{args.actual_label} {actual.width}x{actual.height}", fit_tile(actual, args.tile)))
        panels.append((f"Diff x{args.diff_gain}", fit_tile(diff, args.tile)))
        total_bytes = actual.width * actual.height * 3
        summary = f"mismatch bytes: {mismatch_bytes}/{total_bytes}, max channel diff: {max_diff}"

    label_h = 28
    title_h = 42
    summary_h = 28
    gap = 12
    width = len(panels) * args.tile + (len(panels) + 1) * gap
    height = title_h + label_h + args.tile + summary_h + 2 * gap
    canvas = Image.new("RGB", (width, height), (246, 248, 250))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 12), args.title, fill=(20, 24, 31))
    draw.text((gap, height - summary_h + 4), summary, fill=(64, 72, 84))

    x = gap
    y_label = title_h
    y_img = title_h + label_h
    for label, img in panels:
        draw.text((x, y_label), label, fill=(32, 37, 45))
        canvas.paste(img, (x, y_img))
        x += args.tile + gap

    args.out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.out)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
