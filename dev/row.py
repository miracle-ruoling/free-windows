import sys
from PIL import Image

im = Image.open(sys.argv[1] if len(sys.argv) > 1 else "shot_light2.png").convert("RGB")
w, h = im.size
# find the panel edge on the horizontal line through the middle of the pill
y = 132 - 50   # screenshot was taken from screen y=50
y = min(max(y, 0), h - 1)
row = [im.getpixel((x, y)) for x in range(w)]
print("size", im.size, "row y=", y)
prev = None
for x in range(0, w, 1):
    p = row[x]
    lum = sum(p) // 3
    if prev is None:
        prev = lum
    if abs(lum - prev) > 25:
        print("  jump at x=%d %s -> %s" % (x, row[max(0, x - 1)], p))
    prev = lum
print("samples:", [(x, row[x]) for x in range(0, w, 100)])
