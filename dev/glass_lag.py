"""Per-frame displacement of the strip's glass content, wide search (no icon contamination).

Why a wide search: the earlier version only looked at +-8 px and many frames came back with
exactly +-8, i.e. pinned to the edge of the search - indistinguishable from a real offset
bigger than 8 px. Here the window is +-WIDE, the icon row is excluded (the icons travel with
the strip and would drag the peak along with the window), and the result is printed next to
the speed so the two can be compared:

  offset ~ speed        -> a lag, tau = offset / speed
  offset constant       -> systematic crop error
  sign flips frame to frame -> position and content out of step

usage: python dev/glass_lag.py <dir>
"""
import json
import os
import sys

import numpy as np

EDGE = 8
WIDE = 60
ICON = (390, 1225)      # screen x band covered by the icon row


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def score(ref, img, T, B, segs, sx, sy, gx, gy):
    """NCC over the concatenation of the icon-free segments, shifted by (sx, sy)."""
    va, vb = [], []
    for (L, R) in segs:
        # ref[y, x]  vs  img[y - sy, x - sx], valid overlap only
        x0 = max(L, L + sx); x1 = min(R, R + sx)
        y0 = max(T, T + sy); y1 = min(B, B + sy)
        if x1 - x0 < 60 or y1 - y0 < 40:
            continue
        va.append(ref[y0 - gy:y1 - gy, x0 - gx:x1 - gx].ravel())
        vb.append(img[y0 - sy - gy:y1 - sy - gy, x0 - sx - gx:x1 - sx - gx].ravel())
    if not va:
        return None
    a = np.concatenate(va); b = np.concatenate(vb)
    a = a - a.mean(); b = b - b.mean()
    na = np.linalg.norm(a); nb = np.linalg.norm(b)
    if na < 1e-6 or nb < 1e-6:
        return None
    return float(a @ b / (na * nb))


def main():
    d = sys.argv[1]
    frames = np.load(os.path.join(d, 'frames.npy'), mmap_mode='r')
    blob = json.load(open(os.path.join(d, 'meta.json')))
    meta, tags = blob['meta'], blob['tags']
    gx, gy = meta['grab'][0], meta['grab'][1]
    rects = [tuple(r['rect']) for r in meta['rects']]
    times = [r['t'] for r in meta['rects']]
    rest = [i for i, t in enumerate(tags) if t == 'rest'][0]
    r0 = rects[rest]
    ref = gray(np.asarray(frames[rest]))
    print('rest rect', r0, ' frames', len(frames))

    def segs_for(rect):
        T = max(rect[1] + EDGE, r0[1] + EDGE)
        B = min(rect[3] - EDGE, r0[3] - EDGE)
        L = max(rect[0] + EDGE, r0[0] + EDGE)
        R = min(rect[2] - EDGE, r0[2] - EDGE)
        out = []
        if min(R, ICON[0]) - L >= 100:
            out.append((L, min(R, ICON[0])))
        if R - max(L, ICON[1]) >= 100:
            out.append((max(L, ICON[1]), R))
        return T, B, out

    print('%4s %6s %8s %8s  %s' % ('idx', 'dX', 'v(px/s)', 'v*16.7ms', 'shift  ncc'))
    prev = None
    rows = []
    for k in range(len(frames)):
        if tags[k] == 'rest':
            continue
        rect = rects[k]
        T, B, segs = segs_for(rect)
        if not segs:
            continue
        img = gray(np.asarray(frames[k]))
        best = (-9, None)
        for sy in range(-12, 13):
            for sx in range(-WIDE, WIDE + 1):
                c = score(ref, img, T, B, segs, sx, sy, gx, gy)
                if c is not None and c > best[0]:
                    best = (c, (sx, sy))
        if best[1] is None:
            continue
        sx, sy = best[1]
        v = 0.0
        if prev is not None and times[k] > times[prev]:
            v = (rect[0] - rects[prev][0]) / (times[k] - times[prev])
        prev = k
        rows.append((k, rect[0] - r0[0], v, sx, sy, best[0]))
        print('%4d %6d %8.0f %8.1f  (%+3d,%+3d) %.3f'
              % (k, rows[-1][1], v, v * 0.0167, sx, sy, best[0]))

    if rows:
        A = np.array([[r[2], r[3], r[4], r[5]] for r in rows], dtype=np.float64)
        mv = np.abs(A[:, 0]) > 150
        print('\nframes %d, moving %d' % (len(rows), int(mv.sum())))
        print('sx: median %+.1f  mean %+.2f  min %+d  max %+d'
              % (np.median(A[:, 1]), A[:, 1].mean(), A[:, 1].min(), A[:, 1].max()))
        print('sy: median %+.1f  mean %+.2f' % (np.median(A[:, 2]), A[:, 2].mean()))
        if mv.sum() > 3:
            print('corr(speed, sx) = %+.3f' % np.corrcoef(A[mv, 0], A[mv, 1])[0, 1])
            with np.errstate(divide='ignore', invalid='ignore'):
                tau = A[mv, 1] / A[mv, 0]
            print('implied lag dx/v: median %+.1f ms' % (np.nanmedian(tau) * 1000))


if __name__ == '__main__':
    main()
