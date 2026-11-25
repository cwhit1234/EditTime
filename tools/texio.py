#!/usr/bin/env python3
"""Read/write the texture formats WoW uses, with no third-party modules.

Supports reading uncompressed TGA and BLP2 (palettized, raw BGRA, and DXT1/3/5),
writing 32-bit TGA, and writing PNG for previewing work in progress.

Images are handled as a list of rows of (r, g, b, a) tuples, top row first.
"""

import struct
import zlib

# ---------------------------------------------------------------------------
#  TGA
# ---------------------------------------------------------------------------


def read_tga(path):
    data = open(path, "rb").read()
    idlen, cmaptype, imgtype = data[0], data[1], data[2]
    if imgtype not in (2, 10):
        raise ValueError(f"{path}: unsupported TGA image type {imgtype}")
    if cmaptype != 0:
        raise ValueError(f"{path}: color-mapped TGA is not supported")

    width, height = struct.unpack_from("<HH", data, 12)
    depth, descriptor = data[16], data[17]
    if depth not in (24, 32):
        raise ValueError(f"{path}: unsupported TGA depth {depth}")

    stride = depth // 8
    pos = 18 + idlen
    count = width * height
    pixels = []

    if imgtype == 2:
        for i in range(count):
            off = pos + i * stride
            b, g, r = data[off], data[off + 1], data[off + 2]
            a = data[off + 3] if stride == 4 else 255
            pixels.append((r, g, b, a))
    else:  # run-length encoded
        while len(pixels) < count:
            packet = data[pos]
            pos += 1
            n = (packet & 0x7F) + 1
            if packet & 0x80:
                b, g, r = data[pos], data[pos + 1], data[pos + 2]
                a = data[pos + 3] if stride == 4 else 255
                pos += stride
                pixels.extend([(r, g, b, a)] * n)
            else:
                for _ in range(n):
                    b, g, r = data[pos], data[pos + 1], data[pos + 2]
                    a = data[pos + 3] if stride == 4 else 255
                    pos += stride
                    pixels.append((r, g, b, a))

    rows = [pixels[y * width:(y + 1) * width] for y in range(height)]
    # Bit 5 of the descriptor set means the file is already top-down.
    if not (descriptor & 0x20):
        rows.reverse()
    return rows


def write_tga(path, rows):
    """Uncompressed 32-bit BGRA TGA. WoW wants power-of-two dimensions."""
    height, width = len(rows), len(rows[0])
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0, 0, 2,        # no ID, no colour map, uncompressed true-colour
        0, 0, 0,        # colour map spec (unused)
        0, 0,           # origin
        width, height,
        32,             # bits per pixel
        8,              # 8 bits of alpha, bottom-left origin
    )
    body = bytearray()
    for y in reversed(range(height)):   # TGA rows run bottom-to-top
        for r, g, b, a in rows[y]:
            body += bytes((b, g, r, a))
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(body)
        fh.write(b"\x00" * 8 + b"TRUEVISION-XFILE." + b"\x00")


# ---------------------------------------------------------------------------
#  BLP2
# ---------------------------------------------------------------------------


def _c565(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)


def _dxt_blocks(data, width, height, fmt):
    """Decode DXT1/3/5 into a flat top-down list of (r, g, b, a)."""
    out = [(0, 0, 0, 0)] * (width * height)
    bw, bh = (width + 3) // 4, (height + 3) // 4
    stride = 8 if fmt == 1 else 16
    pos = 0

    for by in range(bh):
        for bx in range(bw):
            block = data[pos:pos + stride]
            pos += stride
            alpha = [255] * 16

            if fmt == 3:                                    # DXT3: 4-bit alpha
                for i in range(8):
                    alpha[i * 2] = (block[i] & 0x0F) * 17
                    alpha[i * 2 + 1] = (block[i] >> 4) * 17
                colour = block[8:]
            elif fmt == 5:                                  # DXT5: interpolated
                a0, a1 = block[0], block[1]
                table = [a0, a1]
                if a0 > a1:
                    table += [((7 - i) * a0 + (i + 1) * a1) // 7 for i in range(6)]
                else:
                    table += [((5 - i) * a0 + (i + 1) * a1) // 5 for i in range(4)]
                    table += [0, 255]
                bits = int.from_bytes(block[2:8], "little")
                alpha = [table[(bits >> (3 * i)) & 7] for i in range(16)]
                colour = block[8:]
            else:
                colour = block

            c0, c1 = struct.unpack_from("<HH", colour, 0)
            r0, g0, b0 = _c565(c0)
            r1, g1, b1 = _c565(c1)
            if c0 > c1 or fmt != 1:
                palette = [
                    (r0, g0, b0), (r1, g1, b1),
                    ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
                    ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3),
                ]
                punch = False
            else:
                palette = [
                    (r0, g0, b0), (r1, g1, b1),
                    ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2),
                    (0, 0, 0),
                ]
                punch = True

            idx = struct.unpack_from("<I", colour, 4)[0]
            for i in range(16):
                px, py = bx * 4 + (i % 4), by * 4 + (i // 4)
                if px >= width or py >= height:
                    continue
                sel = (idx >> (2 * i)) & 3
                r, g, b = palette[sel]
                a = 0 if (punch and sel == 3) else alpha[i]
                out[py * width + px] = (r, g, b, a)
    return out


def read_blp(path):
    data = open(path, "rb").read()
    if data[:4] != b"BLP2":
        raise ValueError(f"{path}: not a BLP2 file")

    encoding, alpha_depth, alpha_encoding = data[8], data[9], data[10]
    width, height = struct.unpack_from("<II", data, 12)
    offsets = struct.unpack_from("<16I", data, 20)
    sizes = struct.unpack_from("<16I", data, 84)

    pos = 148
    palette = None
    if encoding == 1:
        palette = [
            (data[pos + i * 4 + 2], data[pos + i * 4 + 1], data[pos + i * 4])
            for i in range(256)
        ]
        pos += 1024

    mip = data[offsets[0]:offsets[0] + sizes[0]]
    count = width * height

    if encoding == 1:
        flat = []
        for i in range(count):
            r, g, b = palette[mip[i]]
            flat.append((r, g, b, 255))
        if alpha_depth == 8:
            base = count
            flat = [(p[0], p[1], p[2], mip[base + i]) for i, p in enumerate(flat)]
        elif alpha_depth == 1:
            base = count
            flat = [
                (p[0], p[1], p[2], 255 if (mip[base + i // 8] >> (i % 8)) & 1 else 0)
                for i, p in enumerate(flat)
            ]
    elif encoding == 2:
        fmt = {0: 1, 1: 3, 7: 5}.get(alpha_encoding, 1)
        flat = _dxt_blocks(mip, width, height, fmt)
    elif encoding == 3:
        flat = [
            (mip[i * 4 + 2], mip[i * 4 + 1], mip[i * 4], mip[i * 4 + 3])
            for i in range(count)
        ]
    else:
        raise ValueError(f"{path}: unsupported BLP encoding {encoding}")

    return [flat[y * width:(y + 1) * width] for y in range(height)]


def read_image(path):
    lower = path.lower()
    if lower.endswith(".blp"):
        return read_blp(path)
    if lower.endswith(".png"):
        return read_png(path)
    return read_tga(path)


# ---------------------------------------------------------------------------
#  PNG
# ---------------------------------------------------------------------------


def read_png(path):
    """8-bit non-interlaced RGB/RGBA PNG. Enough for addon art assets."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    pos = 8
    idat = bytearray()
    width = height = depth = colour = interlace = None

    while pos < len(data):
        length = struct.unpack_from(">I", data, pos)[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length          # length + tag + body + crc

        if tag == b"IHDR":
            width, height, depth, colour = struct.unpack_from(">IIBB", body, 0)
            interlace = body[12]
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break

    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise ValueError(
            f"{path}: only 8-bit non-interlaced RGB/RGBA is supported "
            f"(depth={depth} colour={colour} interlace={interlace})"
        )

    channels = 4 if colour == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = width * channels

    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride

        # Undo the per-scanline filter. `a` is the pixel to the left, `b` the
        # one above, `c` above-left -- all zero outside the image.
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            if ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif ftype == 4:
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
            elif ftype != 0:
                raise ValueError(f"{path}: bad filter type {ftype}")

        rows.append([
            (line[x * channels], line[x * channels + 1], line[x * channels + 2],
             line[x * channels + 3] if channels == 4 else 255)
            for x in range(width)
        ])
        prev = line

    return rows


def write_png(path, rows, checker=False):
    """Write RGB PNG. `checker` composites alpha over a checkerboard so
    transparent regions are visible when eyeballing the result."""
    height, width = len(rows), len(rows[0])
    raw = bytearray()
    for y, row in enumerate(rows):
        raw.append(0)
        for x, (r, g, b, a) in enumerate(row):
            if checker and a < 255:
                bg = 150 if ((x // 8) + (y // 8)) % 2 else 100
                f = a / 255
                r = int(r * f + bg * (1 - f))
                g = int(g * f + bg * (1 - f))
                b = int(b * f + bg * (1 - f))
            raw += bytes((r, g, b))

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw)))
        + chunk(b"IEND", b"")
    )
    open(path, "wb").write(png)


def scale(rows, factor):
    return [
        [rows[y // factor][x // factor] for x in range(len(rows[0]) * factor)]
        for y in range(len(rows) * factor)
    ]
