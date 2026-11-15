"""Render the tray glyph candidates the way the dock does it (font 72 -> ink scaled to 56)."""
from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\SegoeIcons.ttf"
LABEL = r"C:\Windows\Fonts\consola.ttf"

codes = [
    (0xE871, "no-signal"), (0xE874, "wifi"), (0xE839, "eth"),
    (0xE74F, "mute"), (0xE992, "vol0"), (0xE993, "vol1"), (0xE994, "vol2"), (0xE995, "vol3"),
    (0xE850, "bat0"), (0xE855, "bat5"), (0xE859, "bat9"),
    (0xE85A, "chg0"), (0xE85F, "chg5"), (0xE863, "chg9"),
    (0xEBB0, "x-b0"), (0xEBB5, "x-b5"), (0xEBBA, "x-ba"), (0xEBBF, "x-bf"),
]

size = 72
ink = 56
font = ImageFont.truetype(FONT, size)
label = ImageFont.truetype(LABEL, 12)

cells = []
for code, name in codes:
    box = size * 2
    img = Image.new("L", (box, box), 0)
    d = ImageDraw.Draw(img)
    d.text((box // 2, 0), chr(code), font=font, fill=255, anchor="ma")
    bbox = img.getbbox()
    if not bbox:
        cells.append((name, None))
        continue
    glyph = img.crop(bbox)
    w, h = glyph.size
    nh = ink
    nw = max(1, int(round(w * nh / h)))
    glyph = glyph.resize((nw, nh), Image.LANCZOS)
    cells.append((name, glyph))

cw, ch = ink + 30, ink + 40
cols = 9
rows = (len(cells) + cols - 1) // cols
out = Image.new("RGB", (cols * cw, rows * ch), (28, 28, 28))
d = ImageDraw.Draw(out)
for i, (name, glyph) in enumerate(cells):
    cx, cy = (i % cols) * cw, (i // cols) * ch
    if glyph:
        out.paste((255, 214, 96), (cx + (cw - glyph.size[0]) // 2, cy + 6), glyph)
    d.text((cx + 4, cy + ch - 16), name, font=label, fill=(220, 220, 220))
out = out.resize((out.size[0] * 2, out.size[1] * 2), Image.LANCZOS)
out.save("glyph_tray_check.png")
print("ok")
