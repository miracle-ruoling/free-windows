import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
box = [int(v) for v in sys.argv[3].split(',')]
scale = float(sys.argv[4]) if len(sys.argv) > 4 else 2.0
im = Image.open(src).crop(box)
im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
im.save(out)
print(out, im.width, im.height)
