"""Generate the 1024x1024 AppIcon.png with the Python standard library only.

Run:  python scripts/make_icon.py
The result is written into MaskApp/Assets.xcassets/AppIcon.appiconset/.
Replace this with your own artwork whenever you like; keep the file name and size.
"""

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = (
    Path(__file__).resolve().parent.parent
    / "MaskApp"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon.png"
)


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main() -> None:
    cx = cy = SIZE / 2
    dark = (20, 22, 50)
    mid = (42, 46, 98)
    cyan = (93, 224, 200)
    blue = (122, 168, 255)
    white = (238, 248, 255)
    rings = (
        (338.0, 30.0, cyan, 0.50),
        (258.0, 23.0, blue, 0.68),
        (182.0, 18.0, cyan, 0.82),
    )

    pixels = bytearray(SIZE * SIZE * 4)

    for y in range(SIZE):
        dy = y - cy
        row_offset = y * SIZE * 4
        for x in range(SIZE):
            dx = x - cx
            radius = math.hypot(dx, dy)

            # Radial background
            t = min(1.0, radius / 730.0)
            r = mid[0] + (dark[0] - mid[0]) * t
            g = mid[1] + (dark[1] - mid[1]) * t
            b = mid[2] + (dark[2] - mid[2]) * t

            # Three light-wave rings
            for rad, width, color, strength in rings:
                d = abs(radius - rad) / width
                if d < 1.0:
                    a = (1.0 - d) ** 2 * strength
                    r += (color[0] - r) * a
                    g += (color[1] - g) * a
                    b += (color[2] - b) * a

            # Mask outline: a soft vertical ellipse
            ellipse = (dx / 205.0) ** 2 + (dy / 250.0) ** 2
            edge = abs(ellipse - 1.0)
            if edge < 0.13:
                a = (1.0 - edge / 0.13) ** 2 * 0.92
                r += (white[0] - r) * a
                g += (white[1] - g) * a
                b += (white[2] - b) * a

            # Two eye cut-outs
            for ex in (-86.0, 86.0):
                e = ((dx - ex) / 46.0) ** 2 + ((dy + 42.0) / 25.0) ** 2
                ee = abs(e - 1.0)
                if ee < 0.30:
                    a = (1.0 - ee / 0.30) ** 2 * 0.80
                    r += (cyan[0] - r) * a
                    g += (cyan[1] - g) * a
                    b += (cyan[2] - b) * a

            # Inner core glow
            if radius < 120.0:
                a = (1.0 - radius / 120.0) ** 2 * 0.30
                r += (cyan[0] - r) * a
                g += (cyan[1] - g) * a
                b += (cyan[2] - b) * a

            i = row_offset + x * 4
            pixels[i] = max(0, min(255, int(r)))
            pixels[i + 1] = max(0, min(255, int(g)))
            pixels[i + 2] = max(0, min(255, int(b)))
            pixels[i + 3] = 255

    raw = b"".join(
        b"\x00" + bytes(pixels[y * SIZE * 4 : (y + 1) * SIZE * 4])
        for y in range(SIZE)
    )
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"Wrote {OUT} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
