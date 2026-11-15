"""Diff two screenshots: how many pixels changed, and where."""
import sys
import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=np.int16)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB"), dtype=np.int16)
if a.shape != b.shape:
    print(f"size mismatch {a.shape} vs {b.shape}")
    raise SystemExit(1)
d = np.abs(a - b).max(axis=2)
mask = d > 8
n = int(mask.sum())
print(f"{sys.argv[1]} vs {sys.argv[2]}: changed={n} of {mask.size}")
if n:
    ys, xs = np.nonzero(mask)
    print(f"  bbox x={xs.min()}..{xs.max()} y={ys.min()}..{ys.max()}")
    # per-band report: rows with the most changes
    rowsum = mask.sum(axis=1)
    top = np.argsort(rowsum)[-5:][::-1]
    print("  busiest rows:", [(int(y), int(rowsum[y])) for y in top])
