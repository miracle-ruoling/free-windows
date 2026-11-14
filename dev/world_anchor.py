"""Is the glass content anchored to the world on this frame?  (no assumptions, no rect)

Per composed frame there are two competing correlations between the resting frame A and the
moving frame B, both taken in *screen* coordinates:

  * the glass content  -> has to stay put in world coordinates -> peak at sx = 0
  * the icons          -> sit at fixed client coords, so they travel with the body
                          -> peak at sx = -delta, where delta comes from the debug beacon

So: find the best peak near 0 (that is the world-anchoring of the glass) and check that the
icon peak really sits at -delta (a sanity check that the beacon reading is right). Reading
delta off the beacon instead of GetWindowRect removes the "frame is older than the rect"
confusion entirely.

usage: python dev/world_anchor.py <dir> [--all]
"""
import json
import os
import sys

import numpy as np

EDGE = 8
CONTENT_WIN = 34     # +-px around 0 where the content peak may live
ICON_WIN = 28        # +-px around -delta for the icon peak
BEACON_CLIENT_X = 24  # mask out the debug marker


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def ncc_at(A, B, sx):
    va, vb = [], []
    for (y0, y1, x0, x1) in A['segs']:
        a0 = max(x0, x0 + sx); a1 = min(x1, x1 + sx)
        if a1 - a0 < 40:
            continue
        va.append(A['img'][y0:y1, a0:a1].ravel())
        vb.append(B[y0:y1, a0 - sx:a1 - sx].ravel())
    if not va:
        return None
    a = np.concatenate(va); b = np.concatenate(vb)
    a = a - a.mean(); b = b - b.mean()
    na = np.linalg.norm(a); nb = np.linalg.norm(b)
    if na < 1e-6 or nb < 1e-6:
        return None
    return float(a @ b / (na * nb))


def best_in(A, B, lo, hi):
    best = (-9.0, None)
    for sx in range(lo, hi + 1):
        c = ncc_at(A, B, sx)
        if c is not None and c > best[0]:
            best = (c, sx)
    return best


def find_beacon(img, gx, gy):
    a = img.astype(np.int16)
    m = (a[:, :, 0] > 200) & (a[:, :, 1] < 80) & (a[:, :, 2] > 200)
    ys, xs = np.where(m)
    if xs.size < 20:
        return None
    return float(np.median(xs)) + gx, float(np.median(ys)) + gy


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
    b0 = find_beacon(ref_img, gx, gy)
    if not b0:
        print('no beacon in the resting frame - is debugBeacon=1?')
        return
    print('rest rect', r0, ' beacon at', b0)

    T = r0[1] + EDGE
    B = r0[3] - EDGE
    segs = [(T - gy, B - gy, r0[0] + BEACON_CLIENT_X - gx, r0[2] - EDGE - gx)]
    A = {'img': ref, 'segs': segs}

    print('%4s %6s %8s %8s   %-16s %-16s' % ('idx', 'dX', 'v', 'delta', 'content', 'icons'))
    prev = None
    rows = []
    for k in range(len(frames)):
        if tags[k] == 'rest':
            continue
        img_raw = np.asarray(frames[k])
        bk = find_beacon(img_raw, gx, gy)
        if not bk:
            continue
        delta = bk[0] - b0[0]
        rect = rects[k]
        v = 0.0
        if prev is not None and times[k] > times[prev]:
            v = (rect[0] - rects[prev][0]) / (times[k] - times[prev])
        prev = k
        if abs(delta) < 45:
            continue
        img = gray(img_raw)
        cc, cs = best_in(A, img, -CONTENT_WIN, CONTENT_WIN)
        ic, isx = best_in(A, img, int(-delta) - ICON_WIN, int(-delta) + ICON_WIN)
        rows.append((k, rect[0] - r0[0], v, delta, cs, cc, isx, ic))
        print('%4d %6d %8.0f %8.0f   sx=%+4d ncc=%.3f   sx=%+4d ncc=%.3f'
              % (k, rows[-1][1], v, delta, cs, cc, isx, ic))

    if not rows:
        print('no usable frames'); return
    A2 = np.array([[r[2], r[3], r[4], r[5], r[7]] for r in rows], dtype=np.float64)
    print('\nframes %d' % len(A2))
    good = A2[:, 3] > 0.45
    print('icon peak at -delta (+-%d): %d/%d frames' % (ICON_WIN, int(good.sum()), len(A2)))
    print('content sx: median %+5.1f  mean %+5.2f  range %+d..%+d'
          % (np.median(A2[:, 2]), A2[:, 2].mean(), int(A2[:, 2].min()), int(A2[:, 2].max())))
    print('content sx == 0 on %d/%d frames' % (int((np.abs(A2[:, 2]) <= 1).sum()), len(A2)))
    mv = np.abs(A2[:, 0]) > 200
    if mv.sum() > 3:
        print('corr(|v|, |content sx|) = %+.3f'
              % np.corrcoef(np.abs(A2[mv, 0]), np.abs(A2[mv, 2]))[0, 1])
        print('implied lag of a displaced frame: median %+.1f ms'
              % (np.median(A2[mv, 2] / A2[mv, 0]) * 1000))


if __name__ == '__main__':
    main()
