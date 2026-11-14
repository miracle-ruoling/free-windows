"""Per-frame check: is the strip's glass content still nailed to the world while moving?

Each frame is compared, *in screen coordinates*, against a frame taken while the strip
was at rest (that one is pixel-exact by construction).  Both the strip position and its
content come out of the same composed frame, so the answer never depends on guessing
when the frame was composed.

Only the areas left and right of the icon row are used - the icons travel with the strip
and would drag the correlation peak along with the window, which is the opposite of what
we are asking.

usage: python dev/frame_scan.py [dir] [--sweep]
"""
import json
import os
import sys

import numpy as np

EDGE = 8


def gray(img):
    return img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


def ncc(pa, pb, sx, sy):
    """pa[y, x] vs pb[y - sy, x - sx], over the overlap."""
    y0 = max(0, sy); y1 = min(pa.shape[0], pa.shape[0] + sy)
    x0 = max(0, sx); x1 = min(pa.shape[1], pa.shape[1] + sx)
    if y1 - y0 < 30 or x1 - x0 < 120:
        return -2.0
    a = pa[y0:y1, x0:x1]
    b = pb[y0 - sy:y1 - sy, x0 - sx:x1 - sx]
    a = a - a.mean(); b = b - b.mean()
    na = np.linalg.norm(a); nb = np.linalg.norm(b)
    if na < 1e-6 or nb < 1e-6:
        return -2.0
    return float(a.ravel() @ b.ravel() / (na * nb))


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else 'dev/motion1'
    frames = np.load(os.path.join(d, 'frames.npy'), mmap_mode='r')
    blob = json.load(open(os.path.join(d, 'meta.json')))
    meta, tags = blob['meta'], blob['tags']
    gx, gy, gw, gh = meta['grab']
    rects = [tuple(r['rect']) for r in meta['rects']]
    times = [r['t'] for r in meta['rects']]
    rest = [i for i, t in enumerate(tags) if t == 'rest']
    r0 = rects[rest[0]]
    ref = gray(np.asarray(frames[rest[0]]))
    h, w = ref.shape
    print('rest rect', r0, 'grab', (gx, gy, gw, gh), 'frames', len(frames))

    def bands(rect):
        """screen-x spans inside the strip that are not the icon row"""
        icon = (392, 1220)
        L = max(rect[0] + EDGE, r0[0] + EDGE)
        R = min(rect[2] - EDGE, r0[2] - EDGE)
        out = []
        if L < min(R, icon[0]):
            out.append((L, min(R, icon[0])))
        if max(L, icon[1]) < R:
            out.append((max(L, icon[1]), R))
        return out

    def patches(img, rect, band):
        L, R = band
        T = max(rect[1] + EDGE, r0[1] + EDGE)
        B = min(rect[3] - EDGE, r0[3] - EDGE)
        return (img[T - gy:B - gy, L - gx:R - gx],
                img[T - gy:B - gy, L - gx:R - gx])

    print('%4s %-5s %6s %8s  %s' % ('idx', 'tag', 'dX', 'v', 'per-band best shift (ncc)'))
    prev = None
    for k in range(len(frames)):
        if tags[k] == 'rest':
            continue
        rect = rects[k]
        img = gray(np.asarray(frames[k]))
        dX = rect[0] - r0[0]
        v = 0.0
        if prev is not None and times[k] > times[prev]:
            v = (rect[0] - rects[prev][0]) / (times[k] - times[prev])
        prev = k
        cells = []
        for (L, R) in bands(rect):
            pa = ref[max(rects[k][1] + EDGE, r0[1] + EDGE) - gy:min(rects[k][3] - EDGE, r0[3] - EDGE) - gy,
                     L - gx:R - gx]
            pb = img[max(rect[1] + EDGE, r0[1] + EDGE) - gy:min(rect[3] - EDGE, r0[3] - EDGE) - gy,
                     L - gx:R - gx]
            best = (-9, 0, 0)
            for sx in range(-8, 9):
                for sy in range(-4, 5):
                    c = ncc(pa, pb, sx, sy)
                    if c > best[0]:
                        best = (c, sx, sy)
            cells.append('%s:(%+d,%+d)%.3f' % ('L' if L == rect[0] + EDGE else 'R',
                                              best[1], best[2], best[0]))
        print('%4d %-5s %6d %8.0f  %s' % (k, tags[k], dX, v, '  '.join(cells)))


if __name__ == '__main__':
    main()
