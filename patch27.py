"""Patch dock.cpp: the dragged icon must be scaled with the bilinear path, not point sampling.

Symptom the user reported: while dragging an icon it keeps the hover size but looks "blurred" -
a round icon (Clash Verge) turns into a faceted polygon with jagged edges and jagged inside
lines. Cause: Paint() draws the dragged icon with a hand-written loop that picks one source
pixel per destination pixel (nearest neighbour) at 1.34x, while the normal hover zoom goes
through BlendScaled(), which interpolates.

Fix: give BlendScaled() an optional horizontal clip (the dragged icon is clipped at the
container edge on the left and at the grid button on the right) and use it for the dragged
icon as well.
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


# 1) declaration gets an optional clip
sub(
    """static void BlendScaled(int x0, int y0, int dw, int dh, const uint32_t* src, int sw, int sh);""",
    """static void BlendScaled(int x0, int y0, int dw, int dh, const uint32_t* src, int sw, int sh,
                        int clipL = INT_MIN, int clipR = INT_MAX);""",
    'BlendScaled declaration')

# 2) definition: same signature + the clip test
sub(
    """static void BlendScaled(int x0, int y0, int dw, int dh, const uint32_t* src, int sw, int sh) {""",
    """static void BlendScaled(int x0, int y0, int dw, int dh, const uint32_t* src, int sw, int sh,
                        int clipL, int clipR) {""",
    'BlendScaled definition')

sub(
    """            int a = ch(24);
            if (!a) continue;
            int dx = x0 + x, dy = y0 + y;
            if (dx < 0 || dy < 0 || dx >= g_dibW || dy >= g_dibH) continue;
            BYTE* dst = (BYTE*)g_bits + ((size_t)dy * g_dibW + dx) * 4;""",
    """            int a = ch(24);
            if (!a) continue;
            int dx = x0 + x, dy = y0 + y;
            if (dx < 0 || dy < 0 || dx >= g_dibW || dy >= g_dibH) continue;
            if (dx < clipL || dx >= clipR) continue;      // horizontal clip for the drag icon
            BYTE* dst = (BYTE*)g_bits + ((size_t)dy * g_dibW + dx) * 4;""",
    'BlendScaled honours the clip')

# 3) the dragged icon goes through it instead of the nearest-neighbour loop
sub(
    """        if (!it.px.empty() && it.cachedPx > 0) {
            const uint32_t* sp = it.px.data();
            const int sdim = it.cachedPx;
            for (int y = 0; y < sz; y++) {
                int dy = top + y;
                if (dy < 0 || dy >= h) continue;
                int sy = (int)((y + 0.5f) * sdim / sz);
                if (sy >= sdim) sy = sdim - 1;
                for (int x = 0; x < sz; x++) {
                    int dx = left + x;
                    if (dx < clipL || dx >= clipR) continue;
                    int sx = (int)((x + 0.5f) * sdim / sz);
                    if (sx >= sdim) sx = sdim - 1;
                    uint32_t c = sp[(size_t)sy * sdim + sx];
                    if (c >> 24) SetPixelPremul(dx, dy, c);
                }
            }
        }""",
    """        if (!it.px.empty() && it.cachedPx > 0) {
            // bilinear, like the normal hover zoom: point sampling at 1.34x turned a round
            // icon into a faceted polygon with jagged edges
            BlendScaled(left, top, sz, sz, it.px.data(), it.cachedPx, it.cachedPx, clipL, clipR);
        }""",
    'dragged icon uses the bilinear path')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak27')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
