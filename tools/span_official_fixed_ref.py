"""Fixed-point reference for the RTL official SPAN frame engine.

This script intentionally mirrors rtl/span/span_official_frame_engine.v rather
than the floating-point PyTorch model. It is used to compare Vivado simulation
outputs byte-for-byte against the current INT8 RTL datapath.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="rtl/generated/official_span_x2/official_span_manifest.json")
    parser.add_argument("--width", type=int, default=1)
    parser.add_argument("--height", type=int, default=1)
    parser.add_argument("--pixel", default="406080", help="RGB hex pixel used when --input-png is omitted")
    parser.add_argument("--input-png", default=None)
    parser.add_argument("--out-rgb", default="build/span_fixed_ref.rgb")
    parser.add_argument("--out-png", default="build/span_fixed_ref.png")
    parser.add_argument("--debug-txt", default=None)
    parser.add_argument("--scale-shift", type=int, default=8)
    return parser.parse_args()


def read_mem_i8(path: Path) -> list[int]:
    values: list[int] = []
    for line in path.read_text(encoding="ascii").splitlines():
        line = line.strip()
        if not line:
            continue
        v = int(line, 16) & 0xFF
        if v >= 128:
            v -= 256
        values.append(v)
    return values


def sat8(value: int) -> int:
    if value > 127:
        return 127
    if value < -128:
        return -128
    return value


def u8(value: int) -> int:
    return value & 0xFF


def requant8(value: int, shift: int) -> int:
    return sat8(value >> shift)


def sigmoid_u8_approx(x: int) -> int:
    gate = (x >> 1) + 128
    return max(0, min(255, gate))


def silu8(x: int) -> int:
    return sat8((x * sigmoid_u8_approx(x)) >> 8)


def spab_attention8(out3: int, residual: int) -> int:
    gate = sigmoid_u8_approx(out3) - 128
    return sat8(((out3 + residual) * gate) >> 8)


def load_weights(manifest_path: Path) -> tuple[dict[str, list[int]], dict]:
    info = json.loads(manifest_path.read_text(encoding="utf-8"))
    root = manifest_path.parent
    weights = {item["name"]: read_mem_i8(root / item["file"]) for item in info["weights"]}
    return weights, info


def get_input(args: argparse.Namespace) -> list[list[list[int]]]:
    if args.input_png:
        if Image is None:
            raise RuntimeError("Pillow is required for --input-png")
        img = Image.open(args.input_png).convert("RGB").resize((args.width, args.height))
        pixels = list(img.getdata())
    else:
        pix = int(args.pixel, 16)
        rgb = ((pix >> 16) & 0xFF, (pix >> 8) & 0xFF, pix & 0xFF)
        pixels = [rgb for _ in range(args.width * args.height)]

    out: list[list[list[int]]] = []
    for y in range(args.height):
        row: list[list[int]] = []
        for x in range(args.width):
            row.append(list(pixels[y * args.width + x]))
        out.append(row)
    return out


class SpanFixedRef:
    def __init__(self, weights: dict[str, list[int]], width: int, height: int, scale: int, ch: int, shift: int) -> None:
        self.w = weights
        self.width = width
        self.height = height
        self.scale = scale
        self.ch = ch
        self.up_ch = 3 * scale * scale
        self.shift = shift

    def conv3x3_rgb(self, img: list[list[list[int]]], weight_name: str, bias_name: str) -> list[list[list[int]]]:
        weight = self.w[weight_name]
        bias = self.w[bias_name]
        out = self.zero_feature(self.ch)
        for y in range(self.height):
            for x in range(self.width):
                for oc in range(self.ch):
                    acc = bias[oc]
                    for ic in range(3):
                        for ky in range(3):
                            for kx in range(3):
                                sy = y + ky - 1
                                sx = x + kx - 1
                                act = 0
                                if 0 <= sx < self.width and 0 <= sy < self.height:
                                    act = img[sy][sx][ic]
                                    if act >= 128:
                                        act -= 256
                                tap = ic * 9 + ky * 3 + kx
                                acc += act * weight[oc * 27 + tap]
                    out[y][x][oc] = requant8(acc, self.shift)
        return out

    def conv3x3_feat(
        self,
        feat: list[list[list[int]]],
        weight_name: str,
        bias_name: str,
        out_ch: int | None = None,
    ) -> list[list[list[int]]]:
        out_channels = out_ch or self.ch
        weight = self.w[weight_name]
        bias = self.w[bias_name]
        out = self.zero_feature(out_channels)
        in_ch = len(feat[0][0])
        for y in range(self.height):
            for x in range(self.width):
                for oc in range(out_channels):
                    acc = bias[oc]
                    for ic in range(in_ch):
                        for ky in range(3):
                            for kx in range(3):
                                sy = y + ky - 1
                                sx = x + kx - 1
                                act = 0
                                if 0 <= sx < self.width and 0 <= sy < self.height:
                                    act = feat[sy][sx][ic]
                                tap = ic * 9 + ky * 3 + kx
                                acc += act * weight[oc * (in_ch * 9) + tap]
                    out[y][x][oc] = requant8(acc, self.shift)
        return out

    def conv1x1_cat(self, feat: list[list[list[int]]], weight_name: str, bias_name: str) -> list[list[list[int]]]:
        weight = self.w[weight_name]
        bias = self.w[bias_name]
        in_ch = len(feat[0][0])
        out = self.zero_feature(self.ch)
        for y in range(self.height):
            for x in range(self.width):
                for oc in range(self.ch):
                    acc = bias[oc]
                    for ic in range(in_ch):
                        acc += feat[y][x][ic] * weight[oc * in_ch + ic]
                    out[y][x][oc] = requant8(acc, self.shift)
        return out

    def spab(self, x: list[list[list[int]]], block: int) -> tuple[list[list[list[int]]], list[list[list[int]]]]:
        out1 = self.conv3x3_feat(x, f"block_{block}.c1_r.eval_conv.weight", f"block_{block}.c1_r.eval_conv.bias")
        out1_act = self.map_feature(out1, silu8)
        out2 = self.conv3x3_feat(out1_act, f"block_{block}.c2_r.eval_conv.weight", f"block_{block}.c2_r.eval_conv.bias")
        out2_act = self.map_feature(out2, silu8)
        out3 = self.conv3x3_feat(out2_act, f"block_{block}.c3_r.eval_conv.weight", f"block_{block}.c3_r.eval_conv.bias")
        if block == 1:
            self.dbg_b1_c1_raw = out1
            self.dbg_b1_c1_act = out1_act
            self.dbg_b1_c2_raw = out2
            self.dbg_b1_c2_act = out2_act
            self.dbg_b1_c3_raw = out3
        out = self.zero_feature(self.ch)
        for y in range(self.height):
            for xpix in range(self.width):
                for c in range(self.ch):
                    out[y][xpix][c] = spab_attention8(out3[y][xpix][c], x[y][xpix][c])
        return out, out1

    def forward(self, img: list[list[list[int]]]) -> list[list[list[int]]]:
        feat0 = self.conv3x3_rgb(img, "conv_1.eval_conv.weight", "conv_1.eval_conv.bias")
        out_b1, _ = self.spab(feat0, 1)
        out_b2, _ = self.spab(out_b1, 2)
        out_b3, _ = self.spab(out_b2, 3)
        out_b4, _ = self.spab(out_b3, 4)
        out_b5, _ = self.spab(out_b4, 5)
        out_b6, out_b5_2 = self.spab(out_b5, 6)
        out_b6_conv = self.conv3x3_feat(out_b6, "conv_2.eval_conv.weight", "conv_2.eval_conv.bias")
        cat = self.concat_features([feat0, out_b6_conv, out_b1, out_b5_2])
        fused = self.conv1x1_cat(cat, "conv_cat.weight", "conv_cat.bias")
        up = self.conv3x3_feat(fused, "upsampler.0.weight", "upsampler.0.bias", out_ch=self.up_ch)
        self.last_feat0 = feat0
        self.last_b1 = out_b1
        self.last_b5_2 = out_b5_2
        self.last_b6conv = out_b6_conv
        self.last_fused = fused
        self.last_up = up
        return self.pixelshuffle(up)

    def pixelshuffle(self, feat: list[list[list[int]]]) -> list[list[list[int]]]:
        out_h = self.height * self.scale
        out_w = self.width * self.scale
        out = [[[0, 0, 0] for _ in range(out_w)] for _ in range(out_h)]
        for y in range(self.height):
            for x in range(self.width):
                for sy in range(self.scale):
                    for sx in range(self.scale):
                        sub = sy * self.scale + sx
                        # PyTorch PixelShuffle orders channels as C * r^2 + subpixel.
                        out[y * self.scale + sy][x * self.scale + sx] = [
                            u8(feat[y][x][0 * self.scale * self.scale + sub]),
                            u8(feat[y][x][1 * self.scale * self.scale + sub]),
                            u8(feat[y][x][2 * self.scale * self.scale + sub]),
                        ]
        return out

    def zero_feature(self, channels: int) -> list[list[list[int]]]:
        return [[[0 for _ in range(channels)] for _ in range(self.width)] for _ in range(self.height)]

    def map_feature(self, feat: list[list[list[int]]], fn) -> list[list[list[int]]]:
        return [[[fn(v) for v in pix] for pix in row] for row in feat]

    def concat_features(self, items: list[list[list[list[int]]]]) -> list[list[list[int]]]:
        out = []
        for y in range(self.height):
            row = []
            for x in range(self.width):
                pix: list[int] = []
                for item in items:
                    pix.extend(item[y][x])
                row.append(pix)
            out.append(row)
        return out


def save_outputs(out: list[list[list[int]]], rgb_path: Path, png_path: Path) -> None:
    rgb_path.parent.mkdir(parents=True, exist_ok=True)
    data = bytes(v for row in out for pix in row for v in pix)
    rgb_path.write_bytes(data)
    if Image is not None:
        h = len(out)
        w = len(out[0])
        img = Image.frombytes("RGB", (w, h), data)
        img.save(png_path)


def main() -> None:
    args = parse_args()
    weights, info = load_weights(Path(args.manifest))
    img = get_input(args)
    ref = SpanFixedRef(weights, args.width, args.height, info["scale"], info["channels"], args.scale_shift)
    out = ref.forward(img)
    save_outputs(out, Path(args.out_rgb), Path(args.out_png))
    if args.debug_txt:
        dbg = Path(args.debug_txt)
        dbg.parent.mkdir(parents=True, exist_ok=True)
        feat0 = ref.last_feat0[0][0][:12]
        b1 = ref.last_b1[0][0][:12]
        b1_c1_raw = ref.dbg_b1_c1_raw[0][0][:12]
        b1_c1_act = ref.dbg_b1_c1_act[0][0][:12]
        b1_c2_raw = ref.dbg_b1_c2_raw[0][0][:12]
        b1_c2_act = ref.dbg_b1_c2_act[0][0][:12]
        b1_c3_raw = ref.dbg_b1_c3_raw[0][0][:12]
        b5_2 = ref.last_b5_2[0][0][:12]
        b6conv = ref.last_b6conv[0][0][:12]
        fused = ref.last_fused[0][0][:12]
        up = ref.last_up[0][0][:12]
        dbg.write_text(
            "feat0 " + " ".join(str(v) for v in feat0) + "\n" +
            "b1 " + " ".join(str(v) for v in b1) + "\n" +
            "b1_c1_raw " + " ".join(str(v) for v in b1_c1_raw) + "\n" +
            "b1_c1_act " + " ".join(str(v) for v in b1_c1_act) + "\n" +
            "b1_c2_raw " + " ".join(str(v) for v in b1_c2_raw) + "\n" +
            "b1_c2_act " + " ".join(str(v) for v in b1_c2_act) + "\n" +
            "b1_c3_raw " + " ".join(str(v) for v in b1_c3_raw) + "\n" +
            "b5_2 " + " ".join(str(v) for v in b5_2) + "\n" +
            "b6conv " + " ".join(str(v) for v in b6conv) + "\n" +
            "fused " + " ".join(str(v) for v in fused) + "\n" +
            "up " + " ".join(str(v) for v in up) + "\n",
            encoding="ascii",
        )
    print(f"Wrote {args.out_rgb} and {args.out_png} ({args.width}x{args.height} -> {args.width * info['scale']}x{args.height * info['scale']})")


if __name__ == "__main__":
    main()
