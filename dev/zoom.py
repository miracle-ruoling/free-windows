import sys
from PIL import Image
name = sys.argv[1]
box = tuple(int(v) for v in sys.argv[2:6])
scale = int(sys.argv[6]) if len(sys.argv) > 6 else 3
im = Image.open(name).convert("RGB").crop(box)
im = im.resize((im.width * scale, im.height * scale), Image.LANCZOS)
out = name.replace(".png", "_crop.png")
im.save(out)
print(out, im.size)
