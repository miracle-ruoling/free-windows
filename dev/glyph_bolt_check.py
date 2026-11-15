"""Candidates for a 'charging' indicator: bolts and battery-with-plug glyphs."""
from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\SegoeIcons.ttf"
LABEL = r"C:\Windows\Fonts\consola.ttf"

codes = [0xE83A, 0xE83B, 0xE83C, 0xE83D, 0xE83E, 0xE83F,
         0xE945, 0xE946, 0xE947, 0xEA6B, 0xEC0A, 0xEC0B, 0xEC0C,
         0xE85A, 0xE85B, 0xE85C, 0xE85D, 0xE85E, 0xE85F, 0xE860, 0xE861, 0xE862, 0xE863]
size = 72
font = ImageFont.truetype(FONT, size)
label = ImageFont.truetype(LABEL, 12)
cw, chh = size + 30, size + 40
cols = 8
rows = (len(codes) + cols - 1) // cols
out = Image.new("RGB", (cols * cw, rows * chh), (28, 28, 28))
d = ImageDraw.Draw(out)
for i, code in enumerate(codes):
    cx, cy = (i % cols) * cw, (i // cols) * chh
    try:
        d.text((cx + 15, cy + 2), chr(code), font=font, fill=(255, 214, 96))
    except Exception:
        pass
    d.text((cx + 4, cy + chh - 16), f"{code:04X}", font=label, fill=(220, 220, 220))
out = out.resize((out.size[0] * 2, out.size[1] * 2), Image.LANCZOS)
out.save("glyph_bolt_check.png")
print("ok")
