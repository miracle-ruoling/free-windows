import sys
from PIL import Image, ImageDraw

# Two crops per shot: over the lettering (blur of text is the clearest signal)
# and over empty glass at the right end of the pill.
LEFT = (240, 20, 540, 120)     # over "BLUR TEST"
RIGHT = (1180, 20, 1360, 120)  # empty glass, no icons
names = sys.argv[1:] or ["shot_r0.png", "shot_r8.png", "shot_r16.png",
                         "shot_r24.png", "shot_r32.png", "shot_r48.png", "shot_r64.png"]
scale = 2
rows = []
for f in names:
    im = Image.open(f).convert("RGB")
    a = im.crop(LEFT)
    b = im.crop(RIGHT)
    gap = 8
    row = Image.new("RGB", (a.width + gap + b.width, a.height), (40, 40, 40))
    row.paste(a, (0, 0))
    row.paste(b, (a.width + gap, 0))
    row = row.resize((row.width * scale, row.height * scale), Image.LANCZOS)
    d = ImageDraw.Draw(row)
    d.rectangle((0, 0, 90, 16), fill=(0, 0, 0))
    d.text((4, 3), f.replace("shot_", "").replace(".png", ""), fill=(255, 60, 60))
    rows.append(row)
w = max(r.width for r in rows)
h = sum(r.height for r in rows) + 4 * (len(rows) - 1)
out = Image.new("RGB", (w, h), (20, 20, 20))
y = 0
for r in rows:
    out.paste(r, (0, y))
    y += r.height + 4
out.save("compare_crops.png")
print("ok", out.size, names)
