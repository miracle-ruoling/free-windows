import time
from PIL import ImageGrab

# burst capture of a point inside the strip: if the hide/show used for the
# backdrop grab were ever composited, some frames would show the wallpaper there
BOX = (575, 300, 585, 310)   # inside the strip, left of the first icon
N = 40
cols = []
for i in range(N):
    im = ImageGrab.grab(bbox=BOX)
    cols.append(im.getpixel((5, 5)))
    time.sleep(0.05)
print("frames:", len(cols))
print(cols)
uniq = {}
for c in cols:
    uniq[c] = uniq.get(c, 0) + 1
print("distinct:", len(uniq))
for c, n in sorted(uniq.items(), key=lambda kv: -kv[1])[:6]:
    print("  ", c, n)
