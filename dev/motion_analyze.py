"""Measure how far the strip's *content* is displaced from the world, per frame.

Both the strip's own rect and its content come out of the same composed frame, so this
never has to guess *when* a frame was composed - which is what made the earlier
"stop, sleep 25 ms, then screenshot" test report zero.

For each frame we take the screen rectangle that both the resting strip and the moving
strip cover, and ask: at which integer shift does the moving frame's texture best match
the resting frame's?  The resting frame is pixel-exact by construction (nothing moves, so
there is nothing to lag), so any shift s != 0 is the artefact, in pixels.

usage: python dev/motion_analyze.py [dir]
"""
import json
import os
import sys

import numpy as np
from scipy.signal import fftconvolve

SHIFT = 42          # search window (px)
EDGE = 6            # skip the rounded corners / rim light


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], dtype=np.float32)


def peak_shift(A, B):
    """A, B: same-size grayscale patches. Returns (sx, sy, ncc, ncc0)."""
    a = A - A.mean()
    b = B - B.mean()
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na < 1e-3 or nb < 1e-3:
        return 0, 0, 0.0, 0.0
    a /= na
    b /= nb
    h, w = a.shape
    # full correlation: corr[sy, sx] = sum B[y, x] * A[y - sy, x - sx]
    corr = fftconvolve(b, a[::-1, ::-1], mode='full')
    cy, cx = h - 1, w - 1
    y0, y1 = max(0, cy - SHIFT), min(corr.shape[0], cy + SHIFT + 1)
    x0, x1 = max(0, cx - SHIFT), min(corr.shape[1], cx + SHIFT + 1)
    sub = corr[y0:y1, x0:x1]
    # cheap overlap compensation: fewer pixels = less correlation mass
    oy = np.arange(y0, y1)[:, None] - cy
    ox = np.arange(x0, x1)[None, :] - cx
    overlap = (h - np.abs(oy)) * (w - np.abs(ox))
    sub = sub / np.maximum(overlap, 1)
    idx = np.unravel_index(np.argmax(sub), sub.shape)
    return int(ox[0, idx[1]]), int(oy[idx[0], 0]), float(sub[idx]), float(sub[SHIFT, SHIFT])


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else 'dev/motion'
    frames = np.load(os.path.join(d, 'frames.npy'), mmap_mode='r')
    with open(os.path.join(d, 'meta.json')) as f:
        blob = json.load(f)
    meta, tags = blob['meta'], blob['tags']
    gx, gy, gw, gh = meta['grab']
    rects = [tuple(r['rect']) for r in meta['rects']]
    times = [r['t'] for r in meta['rects']]

    rest_i = [i for i, t in enumerate(tags) if t == 'rest']
    ri = rest_i[0]
    r0 = rects[ri]
    print('rest rect', r0, ' (copies at', rest_i, ')')
    print('frames', len(frames), 'tags', {t: tags.count(t) for t in set(tags)})

    def inner(rect, shrink=EDGE):
        L, T, R, B = rect
        return (L + shrink, T + shrink, R - shrink, B - shrink)

    ref_big = gray(np.asarray(frames[ri]))
    i0 = inner(r0)

    # sanity: the two rest frames must agree exactly
    if len(rest_i) > 1:
        j = rest_i[1]
        ij = inner(rects[j])
        L = max(i0[0], ij[0]); T = max(i0[1], ij[1])
        R = min(i0[2], ij[2]); B = min(i0[3], ij[3])
        A = ref_big[T - gy:B - gy, L - gx:R - gx]
        Bj = gray(np.asarray(frames[j]))[T - gy:B - gy, L - gx:R - gx]
        sx, sy, ncc, ncc0 = peak_shift(A, Bj)
        print('sanity rest-vs-rest: shift=(%d,%d) ncc=%.4f ncc@0=%.4f' % (sx, sy, ncc, ncc0))

    print()
    print(' idx tag    rectX  dX     v(px/s)  shift     ncc    ncc@0')
    prev = None
    for k in range(len(frames)):
        if tags[k] == 'rest':
            continue
        rk = rects[k]
        ik = inner(rk)
        L = max(i0[0], ik[0]); T = max(i0[1], ik[1])
        R = min(i0[2], ik[2]); B = min(i0[3], ik[3])
        if R - L < 200 or B - T < 40:
            print('%4d %-6s no overlap' % (k, tags[k]))
            continue
        A = ref_big[T - gy:B - gy, L - gx:R - gx]
        Bk = gray(np.asarray(frames[k]))[T - gy:B - gy, L - gx:R - gx]
        sx, sy, ncc, ncc0 = peak_shift(A, Bk)
        dx = rk[0] - r0[0]
        v = ''
        if prev:
            dt = times[k] - times[prev]
            if dt > 1e-4:
                v = '%7.0f' % ((rects[k][0] - rects[prev][0]) / dt)
        prev = k
        print('%4d %-6s %6d %5d %8s  (%3d,%3d) %6.3f %6.3f'
              % (k, tags[k], rk[0], dx, v, sx, sy, ncc, ncc0))


if __name__ == '__main__':
    main()
