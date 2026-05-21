#!/usr/bin/env python3
"""Convert a small quantized SR model description into a Verilog include.

The current RTL baseline has fixed arithmetic, so this tool emits the selected
scale and quantization metadata as parameters. It is intentionally simple and
keeps the contest-required model-to-hardware conversion path explicit.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model_json", type=Path)
    parser.add_argument("-o", "--output", type=Path, default=Path("model_params.vh"))
    parser.add_argument("--scale", type=int, choices=(2, 4), default=2)
    args = parser.parse_args()

    model = json.loads(args.model_json.read_text(encoding="utf-8"))
    quant = model.get("quantization", {})
    text = "\n".join(
        [
            "`ifndef MODEL_PARAMS_VH",
            "`define MODEL_PARAMS_VH",
            f"localparam int MODEL_SCALE = {args.scale};",
            f'localparam string MODEL_NAME = "{model.get("name", "sr_model")}";',
            f'localparam string MODEL_ACT_Q = "{quant.get("activation", "uint8")}";',
            f'localparam string MODEL_WGT_Q = "{quant.get("weight", "int8")}";',
            "`endif",
            "",
        ]
    )
    args.output.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
