"""Content anchoring measured on one client-x band that sits over *static* texture.

The dialog behind the strip keeps changing while work is going on (streaming text, spinner),
and a changing backdrop decorrelates the glass from the reference frame, which made the
earlier numbers useless. This script measures one explicit band instead, so it can be put
over a static part of the screen.

  sx == 0  -> the glass content is exactly where the world is (correct)
  sx != 0  -> the glass is displaced by sx pixels

usage: python dev/content_anchor.py <dir> <clientX0> <clientX1>
"""
import json
import os
import sys

import numpy as np

EDGE = 8


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def beacon(img, gx, gy):
    a = img.astype(np.int16)
    m = (a[:, :, 0] > 200) & (a[:, :, 1] < 80) & (a[:, :, 2] > 200)
    xs = np.where(m)[1]
    if xs.size < 20:
        return None
    return float(np.median(xs)) + gx


def ncc(a, b):
    a = a.ravel().astype(np.float64); b = b.ravel().astype(np.float64)
    a = a - a.mean(); b = b - b.mean()
    na = np.linalg.norm(a); nb = np.linalg.norm(b)
    if na < 1e-6 or nb < 1e-6:
        return -9.0
    return float(a @ b / (na * nb))


def main():
    d = sys.argv[1]
    cx0, cx1 = int(sys.argv[2]), int(sys.argv[3])
    wide = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    frames = np.load(os.path.join(d, 'frames.npy'), mmap_mode='r')
    blob = json.load(open(os.path.join(d, 'meta.json')))
    meta, tags = blob['meta'], blob['tags']
    gx, gy = meta['grab'][0], meta['grab'][1]
    rects = [tuple(r['rect']) for r in meta['rects']]
    times = [r['t'] for r in meta['rects']]
    rest = [i for i, t in enumerate(tags) if t == 'rest'][0]
    r0 = rects[rest]
    A0 = np.asarray(frames[rest])
    ref = gray(A0)
    b0 = beacon(A0, gx, gy)
    L = r0[0] + cx0
    R = r0[0] + cx1
    T = r0[1] + EDGE
    B = r0[3] - EDGE
    print('rest rect', r0, ' band screen x=%d..%d y=%d..%d  beacon %s' % (L, R, T, B, b0))
    refband = ref[T - gy:B - gy, L - gx:R - gx]
    if refband.std() < 3:
        print('WARNING: band has almost no texture (std %.1f) - move the strip over something' % refband.std())

    print('%4s %6s %8s %8s  %7s %7s' % ('idx', 'dX', 'v', 'delta', 'sx', 'ncc'))
    prev = None
    rows = []
    for k in range(len(frames)):
        if tags[k] == 'rest':
            continue
        img_raw = np.asarray(frames[k])
        bk = beacon(img_raw, gx, gy)
        if bk is None and b0 is not None:
            continue
        if b0 is None:
            bk = 0.0
        img = gray(img_raw)
        best = (-9.0, 0)
        for sx in range(-wide, wide + 1):
            a0 = max(L, L + sx); a1 = min(R, R + sx)
            if a1 - a0 < 50:
                continue
            c = ncc(ref[T - gy:B - gy, a0 - gx:a1 - gx],
                    img[T - gy:B - gy, a0 - sx - gx:a1 - sx - gx])
            if c > best[0]:
                best = (c, sx)
        rect = rects[k]
        v = 0.0
        if prev is not None and times[k] > times[prev]:
            v = (rect[0] - rects[prev][0]) / (times[k] - times[prev])
        prev = k
        rows.append((k, rect[0] - r0[0], v, (bk - b0) if b0 is not None else float('nan'), best[1], best[0]))
        print('%4d %6d %8.0f %8.0f  %+7d %7.3f'
              % (k, rows[-1][1], v, (bk - b0) if b0 is not None else 0.0, best[1], best[0]))

    if rows:
        A = np.array([[r[2], r[4], r[5]] for r in rows], dtype=np.float64)
        sharp = A[:, 2] > 0.7
        print('\nframes %d, sharp (ncc>0.7) %d' % (len(A), int(sharp.sum())))
        if sharp.sum():
            print('sx on sharp frames: median %+5.1f  mean %+5.2f  range %+d..%+d  |sx|<=1: %d/%d'
                  % (np.median(A[sharp, 1]), A[sharp, 1].mean(), int(A[sharp, 1].min()),
                     int(A[sharp, 1].max()), int((np.abs(A[sharp, 1]) <= 1).sum()), int(sharp.sum())))
            mv = sharp & (np.abs(A[:, 0]) > 200)
            if mv.sum() > 3:
                print('corr(v, sx) = %+.3f   lag sx/v: median %+.1f ms'
                      % (np.corrcoef(A[mv, 0], A[mv, 1])[0, 1],
                         np.median(A[mv, 1] / A[mv, 0]) * 1000))


if __name__ == '__main__':
    main()
