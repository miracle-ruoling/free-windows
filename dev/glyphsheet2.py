"""Second glyph range: signal bars / wifi strength / anything near the tray set."""
from PIL import Image, ImageDraw, ImageFont

icon = ImageFont.truetype(r"C:\Windows\Fonts\SegoeIcons.ttf", 40)
label = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 12)

codes = list(range(0xE860, 0xE890)) + list(range(0xEC00, 0xEC10)) + list(range(0xE9F0, 0xE9FA))
cols, cell = 8, 80
rows = (len(codes) + cols - 1) // cols
img = Image.new("RGB", (cols * cell, rows * cell), (24, 24, 24))
d = ImageDraw.Draw(img)
for i, c in enumerate(codes):
    cx, cy = (i % cols) * cell, (i // cols) * cell
    try:
        d.text((cx + 8, cy + 2), chr(c), font=icon, fill=(255, 214, 96))
    except Exception:
        pass
    d.text((cx + 8, cy + 50), f"{c:04X}", font=label, fill=(230, 230, 230))
img.save("glyph_sheet2.png")
print("ok", len(codes))
