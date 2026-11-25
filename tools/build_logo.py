#!/usr/bin/env python3
"""Generate Media/EditTimeLogo.tga - the icon shown in the addon list.

The source is a 1254x1254 RGB PNG with no alpha: a circular emblem on a solid
black square. Two things have to happen before the client can use it.

First the black has to go. Keying on darkness would punch holes in the emblem,
which is itself dark in places, so the mask is geometric instead: the emblem
ends sharply at r = 0.835 of the half-width (measured off the source -- peak
luminance is 255 at r = 0.83 and 30 by r = 0.84, the rest is glow falloff),
so everything past that is padding and can be cut.

Second it has to be a power-of-two TGA. It is cropped to the emblem, so the
texture is not mostly wasted on padding, then box-downscaled to 128x128 to
match the sibling addons' logos.

Usage:  python tools/build_logo.py [source.png]
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import texio

OUT_SIZE = 128

# Fraction of the source half-width to keep. Slightly beyond the emblem's
# 0.835 edge, to leave a hair of margin for the feather to work in.
CROP = 0.88

# Alpha ramp, as a fraction of the *cropped* half-width. The emblem edge lands
# at 0.835 / 0.88 = 0.949, so hold solid to just past it and fade out by the
# corner-most pixel the circle touches.
SOLID_TO, FADE_TO = 0.95, 0.99


def build(src):
    h, w = len(src), len(src[0])
    half = min(w, h) / 2
    cx, cy = (w - 1) / 2, (h - 1) / 2

    crop_half = half * CROP
    x0, y0 = cx - crop_half, cy - crop_half
    span = crop_half * 2
    step = span / OUT_SIZE

    out = []
    for oy in range(OUT_SIZE):
        row = []
        for ox in range(OUT_SIZE):
            # Box filter: average the source pixels this output pixel covers.
            sy0 = int(y0 + oy * step)
            sy1 = max(sy0 + 1, int(y0 + (oy + 1) * step))
            sx0 = int(x0 + ox * step)
            sx1 = max(sx0 + 1, int(x0 + (ox + 1) * step))

            r = g = b = n = 0
            for sy in range(max(sy0, 0), min(sy1, h)):
                line = src[sy]
                for sx in range(max(sx0, 0), min(sx1, w)):
                    p = line[sx]
                    r += p[0]; g += p[1]; b += p[2]; n += 1
            if n == 0:
                row.append((0, 0, 0, 0))
                continue

            # Radial alpha, measured from the output centre.
            d = math.hypot(ox - (OUT_SIZE - 1) / 2, oy - (OUT_SIZE - 1) / 2)
            t = d / ((OUT_SIZE - 1) / 2)
            if t <= SOLID_TO:
                a = 255
            elif t >= FADE_TO:
                a = 0
            else:
                a = int(255 * (FADE_TO - t) / (FADE_TO - SOLID_TO))

            row.append((r // n, g // n, b // n, a))
        out.append(row)
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(
        os.path.join(here, os.pardir, "Gallery", "EditTimeLogo.png"))
    if not os.path.exists(source):
        raise SystemExit(f"source logo not found: {source}")

    out = build(texio.read_image(source))
    dest = os.path.normpath(os.path.join(here, os.pardir, "Media", "EditTimeLogo.tga"))
    texio.write_tga(dest, out)
    print(f"wrote {dest} ({OUT_SIZE}x{OUT_SIZE}, 32-bit)")


if __name__ == "__main__":
    main()
