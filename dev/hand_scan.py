"""Measure the glass skew on frames captured while *the user* drags by hand.

Reads dev/hand_capture.py output (PNG crops + meta.json) and, per frame:

  * finds the debug beacon (a magenta block drawn into the surface)  -> body position
  * correlates one icon-free band against the resting frame          -> content position

  sx, sy == 0  -> the glass is exactly where the world is on that frame (no defect)
  sx, sy != 0  -> the glass is displaced by that many pixels (that is what the eye sees)

Band and search are given in client coordinates relative to the resting rect, so the same
command works for any window size.

usage: python dev/hand_scan.py <dir> <clientX0> <clientX1> [search]
"""
import json
import os
import sys

import numpy as np
from PIL import Image

EDGE = 8


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def beacon(img, origin):
    a = img.astype(np.int16)
    m = (a[:, :, 0] > 200) & (a[:, :, 1] < 80) & (a[:, :, 2] > 200)
    ys, xs = np.where(m)
    if xs.size < 20:
        return None
    return (float(np.median(xs)) + origin[0], float(np.median(ys)) + origin[1])


def ncc(a, b):
    a = a - a.mean(); b = b - b.mean()
    na = float(np.sqrt((a * a).sum())); nb = float(np.sqrt((b * b).sum()))
    if na < 1e-6 or nb < 1e-6:
        return -9.0
    return float((a * b).sum() / (na * nb))


def main():
    d = sys.argv[1]
    cx0, cx1 = int(sys.argv[2]), int(sys.argv[3])
    wide = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    meta = json.load(open(os.path.join(d, 'meta.json')))
    fr = meta['frames']
    rest = [f for f in fr if f['tag'] == 'rest']
    if not rest:
        print('no rest frame'); return
    r0 = rest[0]['rect']
    imgs = {}

    def load(f):
        if f['i'] not in imgs:
            imgs[f['i']] = np.asarray(Image.open(
                os.path.join(d, 'f%04d.png' % f['i'])).convert('RGB'))
        return imgs[f['i']], f['crop'][:2]

    A0, o0 = load(rest[0])
    ref = gray(A0)
    b0 = beacon(A0, o0)
    # resting strip, in crop-local coordinates
    L0 = r0[0] + cx0 - o0[0]
    R0 = r0[0] + cx1 - o0[0]
    T0 = r0[1] + EDGE - o0[1]
    B0 = r0[3] - EDGE - o0[1]
    print('rest rect', r0, ' beacon', b0, ' crop origin', o0)
    print('band (crop-local) x=%d..%d y=%d..%d' % (L0, R0, T0, B0))
    print('%4s %-4s %8s %6s %6s  %5s %5s %5s' % ('idx', 'tag', 't(s)', 'dX', 'dY', 'sx', 'sy', 'ncc'))
    rows = []
    t0 = rest[0]['t']
    for f in fr:
        if f['tag'] == 'rest':
            continue
        img, o = load(f)
        b = beacon(img, o)
        if b is None or b0 is None:
            continue
        g = gray(img)
        best = (-9.0, 0, 0)
        # coarse then fine: a full +-80 x +-80 sweep at stride 1 is far too slow in python
        for stride in (8, 1):
            lo = -wide if stride > 1 else best[1] - 8
            hi = wide if stride > 1 else best[1] + 8
            lo2 = -wide if stride > 1 else best[2] - 8
            hi2 = wide if stride > 1 else best[2] + 8
            for sy in range(lo2, hi2 + 1, stride):
                for sx in range(lo, hi + 1, stride):
                    x0 = max(L0, L0 + sx); x1 = min(R0, R0 + sx)
                    y0 = max(T0, T0 + sy); y1 = min(B0, B0 + sy)
                    if x1 - x0 < 120 or y1 - y0 < 60:
                        continue
                    c = ncc(ref[y0:y1, x0:x1], g[y0 - sy:y1 - sy, x0 - sx:x1 - sx])
                    if c > best[0]:
                        best = (c, sx, sy)
        if best[1] == 0 and best[2] == 0 and best[0] < -1:
            continue
        rows.append((f['i'], f['t'] - t0, f['rect'][0] - r0[0], f['rect'][1] - r0[1],
                     best[1], best[2], best[0], b[0] - b0[0]))
        print('%4d %-4s %8.2f %6d %6d  %+5d %+5d %5.2f'
              % (rows[-1][0], f['tag'], rows[-1][1], rows[-1][2], rows[-1][3],
                 best[1], best[2], best[0]))
    if not rows:
        print('no usable frames'); return
    A = np.array([[r[2], r[3], r[4], r[5], r[6]] for r in rows], dtype=np.float64)
    sharp = A[:, 4] > 0.7
    print('\nframes %d, sharp %d' % (len(A), int(sharp.sum())))
    if sharp.sum():
        sx, sy = A[sharp, 2], A[sharp, 3]
        print('sx: median %+5.1f  range %+d..%+d   |sx|<=1 on %d/%d'
              % (np.median(sx), int(sx.min()), int(sx.max()), int((np.abs(sx) <= 1).sum()), int(sharp.sum())))
        print('sy: median %+5.1f  range %+d..%+d   |sy|<=1 on %d/%d'
              % (np.median(sy), int(sy.min()), int(sy.max()), int((np.abs(sy) <= 1).sum()), int(sharp.sum())))


if __name__ == '__main__':
    main()
