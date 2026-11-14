import sys
from PIL import Image, ImageDraw

# stack the same strip region from several runs for a side-by-side look
names = sys.argv[1:]
box = (0, 20, 1320, 140)
tiles = []
for n in names:
    im = Image.open(n).convert("RGB").crop(box)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 150, 16), fill=(0, 0, 0))
    d.text((4, 3), n.replace("shot_", "").replace(".png", "")[:22], fill=(255, 70, 70))
    tiles.append(im)
w = tiles[0].width
h = sum(t.height for t in tiles) + 6 * (len(tiles) - 1)
out = Image.new("RGB", (w, h), (25, 25, 25))
y = 0
for t in tiles:
    out.paste(t, (0, y))
    y += t.height + 6
out.save("compare_glass.png")
print("ok", out.size)
