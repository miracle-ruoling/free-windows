import sys
from PIL import Image
name = sys.argv[1]
box = tuple(int(v) for v in sys.argv[2:6])
im = Image.open(name).convert("L").crop(box)
px = list(im.getdata())
mi, ma = min(px), max(px)
mean = sum(px) / len(px)
print(name, "box", box, "min", mi, "max", ma, "mean", round(mean, 1), "range", ma - mi)
