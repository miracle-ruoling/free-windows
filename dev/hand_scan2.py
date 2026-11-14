"""Consecutive-frame test on the user's own drag: is the glass glued to the window?

Comparing against a reference from a minute ago is useless here - the window behind the
strip keeps changing. Consecutive frames are 5-20 ms apart, so the world is stable, and the
two candidate answers are far apart:

  glass anchored to the world  -> the content does not move on screen: sx ~ 0
  glass glued to the strip     -> the content moves with the body:    sx ~ -delta

delta comes from the debug beacon (drawn into the strip's own surface), so it is exactly
where the compositor put the window. Icon-free band only: the icons travel with the body and
would fake the "glued" answer.

usage: python dev/hand_scan2.py <dir> <clientX0> <clientX1> [search]
"""
import json
import os
import sys

import numpy as np
from PIL import Image

EDGE = 8


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def beacon(img):
    a = img.astype(np.int16)
    m = (a[:, :, 0] > 200) & (a[:, :, 1] < 80) & (a[:, :, 2] > 200)
    ys, xs = np.where(m)
    if xs.size < 20:
        return None
    return float(np.median(xs)), float(np.median(ys))


def ncc(a, b):
    a = a - a.mean(); b = b - b.mean()
    na = float(np.sqrt((a * a).sum())); nb = float(np.sqrt((b * b).sum()))
    if na < 1e-6 or nb < 1e-6:
        return -9.0
    return float((a * b).sum() / (na * nb))


def main():
    d = sys.argv[1]
    cx0, cx1 = int(sys.argv[2]), int(sys.argv[3])
    wide = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    meta = json.load(open(os.path.join(d, 'meta.json')))
    fr = meta['frames']
    print('%d frames' % len(fr))

    def load(f):
        return np.asarray(Image.open(os.path.join(d, 'f%04d.png' % f['i'])).convert('RGB'))

    rows = []
    prev = None
    prev_img = prev_b = None
    for f in fr:
        img = load(f)
        b = beacon(img)
        if b is None:
            continue
        if prev is not None:
            ox0, oy0 = prev['crop'][0], prev['crop'][1]
            ox1, oy1 = f['crop'][0], f['crop'][1]
            # band in screen coordinates, clipped to both crops
            L = prev['rect'][0] + cx0; R = prev['rect'][0] + cx1
            T = prev['rect'][1] + EDGE; B = prev['rect'][3] - EDGE
            sl = (L - ox0, R - ox0, T - oy0, B - oy0)
            # same screen rect in the newer crop
            L1, R1, T1, B1 = L - ox1, R - ox1, T - oy1, B - oy1
            if (L1 < 0 or T1 < 0 or R1 > img.shape[1] or B1 > img.shape[0]):
                prev, prev_img, prev_b = f, img, b
                continue
            A = gray(prev_img)[sl[2]:sl[3], sl[0]:sl[1]]
            Bp = gray(img)[T1:T1 + (sl[3] - sl[2]), L1:L1 + (sl[1] - sl[0])]
            if A.shape != Bp.shape or A.shape[0] < 40 or A.shape[1] < 80:
                prev, prev_img, prev_b = f, img, b
                continue
            best = (-9.0, 0)
            for sx in range(-wide, wide + 1):
                x0 = max(0, sx); x1 = min(A.shape[1], A.shape[1] + sx)
                if x1 - x0 < 60:
                    continue
                c = ncc(A[:, x0:x1], Bp[:, x0 - sx:x1 - sx])
                if c > best[0]:
                    best = (c, sx)
            # body motion from the beacon, in screen coordinates
            delta = (b[0] + ox1) - (prev_b[0] + ox0)
            rows.append((f['i'], delta, best[1], best[0]))
        prev, prev_img, prev_b = f, img, b

    if not rows:
        print('no pairs'); return
    A = np.array([[r[1], r[2], r[3]] for r in rows], dtype=np.float64)
    sharp = A[:, 2] > 0.85
    print('pairs %d, sharp %d' % (len(A), int(sharp.sum())))
    mv = sharp & (np.abs(A[:, 0]) >= 2)
    print('moving pairs %d' % int(mv.sum()))
    if mv.sum():
        d, sx = A[mv, 0], A[mv, 1]
        print('|sx|<=1 : %d   sx ~ 0 means world-anchored' % int((np.abs(sx) <= 1).sum()))
        print('corr(delta, sx) = %+.3f   (glued glass would be about -1)' % np.corrcoef(d, sx)[0, 1])
        print('median sx/delta = %+.2f   (-1 = glued, 0 = world-anchored)'
              % np.median(sx / d))
        for lo, hi in ((2, 5), (5, 15), (15, 40), (40, 999)):
            m = mv & (np.abs(A[:, 0]) >= lo) & (np.abs(A[:, 0]) < hi)
            if m.sum():
                print('  |delta| %3d-%-3d : n=%3d  median sx %+5.1f  median sx/delta %+.2f'
                      % (lo, hi, int(m.sum()), np.median(A[m, 1]), np.median(A[m, 1] / A[m, 0])))


if __name__ == '__main__':
    main()
