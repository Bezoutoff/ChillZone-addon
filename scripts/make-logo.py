#!/usr/bin/env python3
"""Builds ChillZone's logo textures from the guild's picture.

The picture (media/logo/src/chillzone.png, black on white, from the guild's VK group) becomes the
addon's gold (ns.COLOR, e6c35c) on transparency, its white parts (the face, the "M") clear:
  ChillZone/media/emblem128.tga   the emblem alone, 128 x 128
  ChillZone/media/logo128.tga     the emblem on the dark square of Olympus's logo, 128 x 128
  ChillZone/media/logo64.tga      the same, 64 x 64
  docs/logo.png                   logo128, for the README (built, never checked: PNG bytes vary)
The TGA files as scripts/make-borders.py writes them (type 2, 32 bits, bottom-left origin).

Usage (needs Pillow):
  python3 scripts/make-logo.py          build them
  python3 scripts/make-logo.py --check  fail unless the .tga files are what it would build
"""
import importlib.util
import io
import os
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SOURCE = os.path.join(ROOT, "media", "logo", "src", "chillzone.png")
GOLD = (0xE6, 0xC3, 0x5C)
GROUND = (4, 37, 44, 255)  # Olympus's logo square, kept
INK, PAPER = 40, 215       # source grey at or below INK: solid; at or above PAPER: clear (JPEG noise)
FILL = 108 / 128           # the emblem's share of the canvas, as Olympus's (10 to 118 of 128)

_spec = importlib.util.spec_from_file_location("make_borders", os.path.join(ROOT, "scripts", "make-borders.py"))
_borders = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_borders)


def emblem(size):
    grey = Image.open(SOURCE).convert("L")
    alpha = grey.point(lambda v: 255 if v <= INK else 0 if v >= PAPER else (PAPER - v) * 255 // (PAPER - INK))
    x0, y0, x1, y1 = alpha.getbbox()
    side = max(x1 - x0, y1 - y0)
    left, top = (x0 + x1) // 2 - side // 2, (y0 + y1) // 2 - side // 2
    square = alpha.crop((left, top, left + side, top + side))
    inner = round(size * FILL)
    mark = Image.new("RGBA", (inner, inner), GOLD + (0,))
    mark.putalpha(square.resize((inner, inner), Image.LANCZOS))
    out = Image.new("RGBA", (size, size), GOLD + (0,))
    out.alpha_composite(mark, ((size - inner) // 2, (size - inner) // 2))
    return out


def logo(size):
    out = Image.new("RGBA", (size, size), GROUND)
    out.alpha_composite(emblem(size))
    return out


def tga(image):
    w, h = image.size
    raw = image.tobytes()
    return _borders.tga(w, h, [raw[y * w * 4:(y + 1) * w * 4] for y in range(h)])


def png(image):
    buf = io.BytesIO()
    image.save(buf, "PNG")
    return buf.getvalue()


CHECKED = {
    "ChillZone/media/emblem128.tga": lambda: tga(emblem(128)),
    "ChillZone/media/logo128.tga": lambda: tga(logo(128)),
    "ChillZone/media/logo64.tga": lambda: tga(logo(64)),
}
BUILT_ONLY = {"docs/logo.png": lambda: png(logo(128))}


def main(argv):
    check = argv[1:] == ["--check"]
    if argv[1:] and not check:
        raise SystemExit(__doc__)
    stale = []
    for rel, build in sorted(CHECKED.items()) + ([] if check else sorted(BUILT_ONLY.items())):
        data, target = build(), os.path.join(ROOT, rel)
        if check:
            try:
                with open(target, "rb") as f:
                    same = f.read() == data
            except OSError:
                same = False
            if not same:
                stale.append(rel)
        else:
            with open(target, "wb") as f:
                f.write(data)
            print(rel)
    if stale:
        sys.stderr.write("Not what scripts/make-logo.py builds (run it): %s\n" % ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
