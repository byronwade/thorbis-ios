#!/usr/bin/env python3
"""Draws the Thorbis app icon and in-app brand mark from design tokens.

Canvas #0A0A0A (dark canvas), mark #F7F4EE (ink) with an accent #3A6AE0 bar.
The App Store icon is a full-bleed square; iOS applies the corner mask.
Usage: python3 scripts/make-icon.py  (needs Pillow)
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "Thorbis/Resources/Assets.xcassets"
CANVAS, INK, ACCENT = (10, 10, 10, 255), (247, 244, 238, 255), (58, 106, 224, 255)


def mark(draw: ImageDraw.ImageDraw, size: int, ox: int = 0, oy: int = 0, ink=INK):
    s = size / 1024
    r = lambda *v: [ox + v[0] * s, oy + v[1] * s, ox + v[2] * s, oy + v[3] * s]
    draw.rounded_rectangle(r(232, 268, 792, 388), radius=28 * s, fill=ink)   # T bar
    draw.rounded_rectangle(r(452, 268, 572, 756), radius=28 * s, fill=ink)   # T stem
    draw.rounded_rectangle(r(232, 676, 392, 756), radius=24 * s, fill=ACCENT)  # pointer foot


def icon():
    img = Image.new("RGBA", (1024, 1024), CANVAS)
    mark(ImageDraw.Draw(img), 1024)
    out = ROOT / "AppIcon.appiconset"
    out.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out / "AppIcon.png")
    (out / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "AppIcon.png",\n      "idiom" : "universal",\n'
        '      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')


def brand():
    out = ROOT / "BrandMark.imageset"
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for scale in (1, 2, 3):
        px = 64 * scale
        for name, fill, bg in (("BrandMark", INK, CANVAS), ("BrandMarkLight", (32, 27, 20, 255), (253, 252, 250, 255))):
            img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            d.rounded_rectangle([0, 0, px - 1, px - 1], radius=px * 0.225, fill=bg)
            mark(d, px, ink=fill)
            img.save(out / f"{name}@{scale}x.png")
        entries.append(f'    {{ "filename" : "BrandMarkLight@{scale}x.png", "idiom" : "universal", "scale" : "{scale}x" }}')
        entries.append(f'    {{ "appearances" : [ {{ "appearance" : "luminosity", "value" : "dark" }} ], '
                       f'"filename" : "BrandMark@{scale}x.png", "idiom" : "universal", "scale" : "{scale}x" }}')
    (out / "Contents.json").write_text('{\n  "images" : [\n' + ",\n".join(entries) +
                                       '\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')


if __name__ == "__main__":
    icon()
    brand()
    print("wrote", ROOT)
