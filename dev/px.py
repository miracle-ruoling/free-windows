import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
y = int(sys.argv[2])
xs = [int(v) for v in sys.argv[3:]]
for x in xs:
    print(x, im.getpixel((x, y)))
