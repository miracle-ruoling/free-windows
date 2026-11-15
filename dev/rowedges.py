"""Print hard vertical edges along a row (to locate the Start panel's left/right border)."""
import sys
import numpy as np
from PIL import Image

path = sys.argv[1]
rows = [int(v) for v in sys.argv[2].split(",")]
thr = int(sys.argv[3]) if len(sys.argv) > 3 else 18
im = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
for y in rows:
    row = im[y]
    d = np.abs(np.diff(row, axis=0)).max(axis=1)
    xs = np.nonzero(d > thr)[0]
    # collapse neighbouring hits
    groups = []
    for x in xs:
        if groups and x - groups[-1][-1] <= 2:
            groups[-1].append(int(x))
        else:
            groups.append([int(x)])
    print(f"y={y}: edges at " + ", ".join(str(g[0]) for g in groups[:40]))
