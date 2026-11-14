"""Patch dock.cpp: get the drag frame rate back to a steady ~60/s.

Measured on the user's own drag frames: the glass content is world-anchored on 122/122
frames (sx = 0), so nothing is mis-cropped. What is left is that the strip's *body* only
moves 17-44 times a second, in uneven steps - each step drags the frame forward while the
picture inside stays put, which reads as "the backdrop slides backwards" and is more
obvious the bigger the step.

Two costs eat that budget:
  1. a backdrop capture (~15 ms) inside Paint(), every ~90 ms while dragging - added last
     round, and the user reports it made no difference to the artefact;
  2. the per-pixel rounded-corner SDF over the whole strip, ~3.4 ms for 190k px, although
     only a band of ~radius px along the edges ever needs it.

Fix 1: dragging keeps a slow refresh (250 ms) instead of ~90 ms.
Fix 2: the interior of the rounded rect is fully covered - skip the SDF and the rim light
there and take the straight tint path.
"""
import io
import os
import shutil
import sys

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dock.cpp')
src = io.open(P, 'r', encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in src else '\n'
orig = src


def sub(old, new, why):
    global src
    o = old.replace('\n', nl)
    n = new.replace('\n', nl)
    if src.count(o) != 1:
        print('FAIL [%s]: found %d matches' % (why, src.count(o)))
        sys.exit(1)
    src = src.replace(o, n)
    print('ok   %s' % why)


sub(
    """                if (busy && capMs < 90) capMs = 90;    // mid-drag: fresh, but not frantic""",
    """                // Mid-drag keep a slow refresh only: a capture is ~15 ms and blocks the
                // frame, which costs more (a coarser, jitterier step) than a stale snapshot
                // costs in fidelity. 250 ms still keeps video / animated wallpaper moving.
                if (busy && capMs < 250) capMs = 250;""",
    'slower refresh while dragging')

# ---------------------------------------------------------------- interior fast path
sub(
    """        const uint32_t* bake = (const uint32_t*)g_bakeBits + (size_t)oy * pw + ox;
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                double rr = CornerRadiusAt(x, y, w, h, baseRadius);""",
    """        const uint32_t* bake = (const uint32_t*)g_bakeBits + (size_t)oy * pw + ox;
        // Anything further than the largest corner radius from every edge is fully covered:
        // cov = 1, no rim light, alpha 255. That is the vast majority of the strip, and it
        // does not need sqrt/fabs per pixel.
        int rm = 0;
        for (int i = 0; i < 4; i++) {
            int c = (int)(baseRadius * (g_cornerAnim[i] < 0 ? 0 : (g_cornerAnim[i] > 1 ? 1
                                                                                    : g_cornerAnim[i])) + 0.5f);
            if (c > rm) rm = c;
        }
        for (int y = 0; y < h; y++) {
            const bool rowIn = (y >= rm + 2 && y < h - rm - 2);
            for (int x = 0; x < w; x++) {
                if (rowIn && x >= rm + 2 && x < w - rm - 2) {
                    uint32_t v = bake[(size_t)y * pw + x];
                    double bl = v & 0xFF, gn = (v >> 8) & 0xFF, rd = (v >> 16) & 0xFF;
                    double lum = rd * 0.2126 + gn * 0.7152 + bl * 0.0722;
                    double lift = (128.0 - lum) * 0.16;
                    rd += lift; gn += lift; bl += lift;
                    if (rd < 0) rd = 0; if (rd > 255) rd = 255;
                    if (gn < 0) gn = 0; if (gn > 255) gn = 255;
                    if (bl < 0) bl = 0; if (bl > 255) bl = 255;
                    double gr2 = rd * (1 - t) + tr * t;
                    double gg2 = gn * (1 - t) + tg * t;
                    double gb2 = bl * (1 - t) + tb * t;
                    gr2 = gr2 * a + rd * (1 - a);
                    gg2 = gg2 * a + gn * (1 - a);
                    gb2 = gb2 * a + bl * (1 - a);
                    ((uint32_t*)g_paintBits)[(size_t)y * g_paintW + x] =
                        (255u << 24) | ((DWORD)gr2 << 16) | ((DWORD)gg2 << 8) | (DWORD)gb2;
                    continue;
                }
                double rr = CornerRadiusAt(x, y, w, h, baseRadius);""",
    'interior fast path in the glass composite')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak19')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
