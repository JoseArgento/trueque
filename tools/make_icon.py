#!/usr/bin/env python3
"""Draws Trueque/Media/icon.tga: two crossed ink arrows (a swap) on a parchment disc with a gold rim,
64x64, like the other addons' icons (the addon compartment and the minimap button use it). Own art."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Trueque" / "Media" / "icon.tga"

S = 512  # drawn big, scaled down
PARCHMENT, PARCHMENT_DARK = (242, 227, 192, 255), (222, 201, 158, 255)
GOLD, GOLD_DEEP = (216, 168, 69, 255), (148, 112, 31, 255)
INK = (58, 35, 19, 255)
CRIMSON = (143, 42, 29, 255)


def arrow(d: ImageDraw.ImageDraw, x0: float, y0: float, x1: float, y1: float, color, width=38, head=70) -> None:
    d.line([(x0, y0), (x1, y1)], fill=color, width=width)
    ang = math.atan2(y1 - y0, x1 - x0)
    for side in (-1, 1):
        a = ang + side * math.radians(150)
        d.line([(x1, y1), (x1 + head * math.cos(a), y1 + head * math.sin(a))], fill=color, width=width)
    r = width / 2
    d.ellipse((x1 - r, y1 - r, x1 + r, y1 + r), fill=color)


def main() -> None:
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((8, 8, S - 8, S - 8), fill=GOLD_DEEP)
    d.ellipse((22, 22, S - 22, S - 22), fill=GOLD)
    d.ellipse((38, 38, S - 38, S - 38), fill=PARCHMENT_DARK)
    d.ellipse((50, 50, S - 50, S - 50), fill=PARCHMENT)
    # one arrow going right on top (ink), one coming back below (crimson): a swap
    arrow(d, 130, 200, 390, 200, INK)
    arrow(d, 382, 312, 122, 312, CRIMSON)
    small = im.resize((64, 64), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    small.save(OUT, format="TGA", orientation=-1)
    (ROOT / "docs").mkdir(exist_ok=True)
    small.save(ROOT / "docs" / "icon.png")  # a look at it outside the game; not shipped
    print(OUT, small.size)


if __name__ == "__main__":
    main()
