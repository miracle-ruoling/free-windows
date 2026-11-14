"""Self-consistency of a single composed frame: body vs content.

The strip's bitmap holds two kinds of pixels:
  * the icons, drawn at fixed *client* coordinates -> they travel with the body, so they say
    where the compositor actually put the window;
  * the glass, which is a crop of the world -> it says which position the content was
    cropped for.
Both live in the same composed frame, so comparing them needs no assumption about *when*
the frame was composed and never touches GetWindowRect (which is read a few ms later and is
therefore always "newer" than the frame).

  skew = content shift - icon shift
  0     -> the frame is self-consistent; what the eye sees is not a per-frame offset
  != 0  -> the glass is displaced relative to its own body

usage: python dev/skew_check.py <dir>
"""
import json
import os
import sys

import numpy as np

WIDE = 90
EDGE = 8
MINW = 60


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def ncc(a, b):
    a = a - a.mean(); b = b - b.mean()
    na = np.linalg.norm(a); nb = np.linalg.norm(b)
    if na < 1e-6 or nb < 1e-6:
        return -9.0
    return float(a @ b / (na * nb))


def shift_of(ref, img, T, B, segs, wide, gx, gy, minw=MINW):
    best = (-9.0, 0)
    for sx in range(-wide, wide + 1):
        va, vb = [], []
        for (x0, x1) in segs:
            a0 = max(x0, x0 + sx); a1 = min(x1, x1 + sx)
            if a1 - a0 < minw:
                continue
            va.append(ref[T - gy:B - gy, a0 - gx:a1 - gx].ravel())
            vb.append(img[T - gy:B - gy, a0 - sx - gx:a1 - sx - gx].ravel())
        if not va:
            continue
        c = ncc(np.concatenate(va), np.concatenate(vb))
        if c > best[0]:
            best = (c, sx)
    return best[1], best[0]


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
    ref_img = np.asarray(frames[rest])
    ref = gray(ref_img)

    # icon row, found inside the resting strip
    L, T, R, B = r0[0] + EDGE, r0[1] + 2 * EDGE, r0[2] - EDGE, r0[3] - 2 * EDGE
    band = ref_img[T - gy:B - gy, L - gx:R - gx].astype(np.int16)
    sat = (band.max(2) - band.min(2)).mean(0)
    hot = np.where(sat > 18)[0]
    if hot.size < 20:
        print('cannot find the icon row'); return
    iconL, iconR = L + hot.min() - 6, L + hot.max() + 6
    print('rest rect', r0, ' icon band x=%d..%d (width %d)' % (iconL, iconR, iconR - iconL))

    print('%4s %6s %8s %7s %8s %6s' % ('idx', 'dX', 'v', 'icons', 'content', 'skew'))
    prev = None
    rows = []
    for k in range(len(frames)):
        if tags[k] == 'rest':
            continue
        rect = rects[k]
        Ti = max(rect[1] + 2 * EDGE, r0[1] + 2 * EDGE)
        Bi = min(rect[3] - 2 * EDGE, r0[3] - 2 * EDGE)
        if Bi - Ti < 40:
            continue
        # only the part of the strip that exists in BOTH frames (screen coords)
        aL = max(rect[0] + EDGE, r0[0] + EDGE)
        aR = min(rect[2] - EDGE, r0[2] - EDGE)
        if aR - aL < 200:
            continue
        img = gray(np.asarray(frames[k]))
        si, ci = shift_of(ref, img, Ti, Bi, [(iconL, iconR)], WIDE, gx, gy)
        segs = []
        if iconL - aL > 80:
            segs.append((aL, iconL - 6))
        if aR - iconR > 80:
            segs.append((iconR + 6, aR))
        sc, cc = (-999, 0.0)
        if segs:
            sc, cc = shift_of(ref, img, Ti, Bi, segs, WIDE, gx, gy)
        v = 0.0
        if prev is not None and times[k] > times[prev]:
            v = (rect[0] - rects[prev][0]) / (times[k] - times[prev])
        prev = k
        rows.append((k, rect[0] - r0[0], v, si, sc, ci, cc))
        print('%4d %6d %8.0f %+7d %+8d %+6d   (ncc %5.2f / %5.2f)'
              % (k, rows[-1][1], v, si, sc, sc - si, ci, cc))

    if rows:
        A = [(r[2], r[3], r[4], r[5], r[6]) for r in rows if r[4] > -900]
        if not A:
            return
        A = np.array(A, dtype=np.float64)
        sk = A[:, 2] - A[:, 1]
        print('\nframes %d' % len(A))
        print('icons:   median %+5.1f  range %+d..%+d' % (np.median(A[:, 1]), A[:, 1].min(), A[:, 1].max()))
        print('content: median %+5.1f  range %+d..%+d' % (np.median(A[:, 2]), A[:, 2].min(), A[:, 2].max()))
        print('skew:    median %+5.1f  mean %+5.2f  range %+d..%+d  |skew|<1.5 on %d/%d'
              % (np.median(sk), sk.mean(), sk.min(), sk.max(), int((np.abs(sk) < 1.5).sum()), len(sk)))


if __name__ == '__main__':
    main()
