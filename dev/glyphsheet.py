"""Render Segoe Fluent Icons / Segoe MDL2 Assets glyphs with their codepoints."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

FONTS = [
    r"C:\Windows\Fonts\SegoeIcons.ttf",   # Segoe Fluent Icons (Win11)
    r"C:\Windows\Fonts\segmdl2.ttf",      # Segoe MDL2 Assets
]

def pick_font(size):
    for path in FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size), os.path.basename(path)
    return None, None

def render(out, size, ranges):
    codes = []
    for a, b in ranges:
        codes.extend(range(a, b + 1))
    icon, name = pick_font(size)
    if icon is None:
        print("no icon font found")
        return
    label = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 12)
    cols, cell = 8, size + 40
    rows = (len(codes) + cols - 1) // cols
    img = Image.new("RGB", (cols * cell, rows * cell), (24, 24, 24))
    d = ImageDraw.Draw(img)
    for i, code in enumerate(codes):
        cx, cy = (i % cols) * cell, (i // cols) * cell
        try:
            d.text((cx + 8, cy + 2), chr(code), font=icon, fill=(255, 214, 96))
        except Exception:
            pass
        d.text((cx + 8, cy + size + 10), f"{code:04X}", font=label, fill=(230, 230, 230))
    img.save(out)
    print(f"{name} -> {out}  ({len(codes)} glyphs)")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "glyph_sheet.png"
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 44
    render(out, size, [
        (0xE700, 0xE70F),   # wifi / signal
        (0xE720, 0xE72F),
        (0xE740, 0xE74F),   # mute
        (0xE990, 0xE99F),   # volume levels
        (0xE838, 0xE85F),   # ethernet / battery
        (0xEBA0, 0xEBAF),   # charging
    ])
