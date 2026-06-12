"""Tiny SPAN model for REDS super-resolution training.

This is a compact, dependency-light PyTorch implementation inspired by the
SPAN paper and official repository. It keeps the architecture blocks explicit
so the trained model can later be quantized and translated into FPGA kernels.
"""

from __future__ import annotations

import torch
from torch import nn
from torch.nn import functional as F


class Conv3XC(nn.Module):
    """3-layer over-parameterized 3x3 convolution block.

    During training it uses 1x1 -> 3x3 -> 1x1 plus a direct 1x1 skip branch.
    For FPGA deployment this block should be fused offline into one 3x3 kernel.
    """

    def __init__(self, channels: int, expansion: int = 2) -> None:
        super().__init__()
        hidden = channels * expansion
        self.conv1 = nn.Conv2d(channels, hidden, 1, 1, 0)
        self.conv2 = nn.Conv2d(hidden, hidden, 3, 1, 1)
        self.conv3 = nn.Conv2d(hidden, channels, 1, 1, 0)
        self.skip = nn.Conv2d(channels, channels, 1, 1, 0)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.conv3(self.conv2(self.conv1(x))) + self.skip(x)


class SPAB(nn.Module):
    """Swift Parameter-free Attention Block.

    The attention map is generated from extracted features by a symmetric-ish
    activation expression without extra trainable attention layers.
    """

    def __init__(self, channels: int, expansion: int = 2) -> None:
        super().__init__()
        self.c1 = Conv3XC(channels, expansion)
        self.c2 = Conv3XC(channels, expansion)
        self.c3 = Conv3XC(channels, expansion)
        self.act = nn.SiLU(inplace=True)

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        out1 = self.act(self.c1(x))
        out2 = self.act(self.c2(out1))
        h = self.c3(out2)
        u = h + x
        att = torch.sigmoid(h) - 0.5
        out = u * att
        return out, out1, att


class TinySPAN(nn.Module):
    """SPAN-style x2/x4 super-resolution model.

    Default width/depth follows the efficient SPAN baseline direction while
    remaining small enough for quantization and FPGA translation experiments.
    """

    def __init__(
        self,
        scale: int = 4,
        in_channels: int = 3,
        out_channels: int = 3,
        channels: int = 48,
        num_blocks: int = 6,
        expansion: int = 2,
    ) -> None:
        super().__init__()
        if scale not in (2, 4):
            raise ValueError("scale must be 2 or 4")
        if num_blocks < 1:
            raise ValueError("num_blocks must be at least 1")

        self.scale = scale
        self.head = nn.Conv2d(in_channels, channels, 3, 1, 1)
        self.blocks = nn.ModuleList([SPAB(channels, expansion) for _ in range(num_blocks)])
        self.fuse_tail = nn.Conv2d(channels, channels, 3, 1, 1)
        self.reconstruct = nn.Conv2d(channels * 4, out_channels * scale * scale, 3, 1, 1)
        self.upsample = nn.PixelShuffle(scale)
        nn.init.zeros_(self.reconstruct.weight)
        nn.init.zeros_(self.reconstruct.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        base = F.interpolate(x, scale_factor=self.scale, mode="bicubic", align_corners=False)
        feat0 = self.head(x)
        feats: list[torch.Tensor] = []
        out = feat0
        for block in self.blocks:
            out, _, _ = block(out)
            feats.append(out)

        early = feats[0]
        deep_index = min(4, len(feats) - 1)
        deep = feats[deep_index]
        fused_tail = self.fuse_tail(feats[-1])
        concat = torch.cat([feat0, early, deep, fused_tail], dim=1)
        sr = self.upsample(self.reconstruct(concat))
        return base + sr


def build_model(scale: int, channels: int = 48, num_blocks: int = 6) -> TinySPAN:
    return TinySPAN(scale=scale, channels=channels, num_blocks=num_blocks)
