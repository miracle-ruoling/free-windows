"""Patch dock.cpp: mix the glass once per capture instead of once per frame.

Today every frame does, per pixel: read the bake at the offset, "background lighten" lift,
tint mix, glassOpacity mix, rounded-corner SDF (sqrt/fabs), rim light, write. Only the blur
is precomputed. That is why a repaint costs ~1.9 ms for a 1570x121 strip, and why the strip
can only follow the cursor ~100 times a second.

The lift/tint/opacity part is a pure function of the *bake* pixel - it does not care where
the strip is - so it belongs in CaptureBackdrop(), which already walks that buffer (and
already hitches). What is left per frame is a copy of the cropped block plus the *strip-local*
parts: the rounded-corner coverage and the rim light. Those only change when the size, the
radius or the corner animation changes, so they get cached as two byte arrays.

Net effect: per frame the expensive maths disappears and the frame rate goes up; per capture
a bit of extra work lands in the hitch that already exists (user's own suggestion).
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


# ---------------------------------------------------------------- 1. per-strip-pixel masks
sub(
    """static int g_bakeMarginUsed = 0;""",
    """static int g_bakeMarginUsed = 0;

// Per *strip* pixel masks for the glass body: rounded-corner coverage and the rim light.
// They depend only on the size, the radius and the corner animation, so they are built once
// and reused - the per-frame pass then needs no sqrt/fabs at all.
static std::vector<BYTE> g_covMask;      // 0..255 coverage
static std::vector<BYTE> g_rimMask;      // 0..255 extra white for the rim
static int g_maskW = 0, g_maskH = 0, g_maskRadius = -1;
static float g_maskAnim[4] = {-2, -2, -2, -2};

static void EnsureStripMasks(int w, int h, int baseRadius) {
    bool same = (w == g_maskW && h == g_maskH && baseRadius == g_maskRadius);
    for (int i = 0; same && i < 4; i++)
        if (g_cornerAnim[i] != g_maskAnim[i]) same = false;
    if (same) return;
    g_covMask.assign((size_t)w * h, 0);
    g_rimMask.assign((size_t)w * h, 0);
    double cx = w / 2.0, cy = h / 2.0, hw = w / 2.0, hh = h / 2.0;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            double rr = CornerRadiusAt(x, y, w, h, baseRadius);
            double qx = fabs(x + 0.5 - cx) - (hw - rr);
            double qy = fabs(y + 0.5 - cy) - (hh - rr);
            double ax = qx > 0 ? qx : 0;
            double ay = qy > 0 ? qy : 0;
            double inx = qx > qy ? qx : qy;
            if (inx > 0) inx = 0;
            double d = sqrt(ax * ax + ay * ay) + inx - rr;
            double cov = 0.5 - d;
            if (cov <= 0) continue;
            if (cov > 1) cov = 1;
            g_covMask[(size_t)y * w + x] = (BYTE)(cov * 255);
            if (d > -2.5) {
                double e = 1.0 + d / 2.5;           // 1 at the edge, 0 at 2.5 px in
                if (e > 0) {
                    DWORD ea = (DWORD)(e * cov * 0.22 * 255);
                    if (ea > 255) ea = 255;
                    g_rimMask[(size_t)y * w + x] = (BYTE)ea;
                }
            }
        }
    }
    g_maskW = w; g_maskH = h; g_maskRadius = baseRadius;
    for (int i = 0; i < 4; i++) g_maskAnim[i] = g_cornerAnim[i];
}""",
    'strip-pixel masks')

# ---------------------------------------------------------------- 2. bake the mix
sub(
    """    g_bakeTick = GetTickCount();
    g_lastCaptureMs = GetTickCount() - bakeT0;""",
    """    // Lift + tint + glassOpacity are a pure function of this pixel, so they are applied
    // here - once per capture - instead of once per frame in Paint().
    {
        double a = g_cfg.glassOpacity / 255.0;
        double t = g_cfg.tintStrength / 255.0;
        DWORD tr = (g_cfg.tint >> 16) & 0xFF, tg = (g_cfg.tint >> 8) & 0xFF,
              tb = g_cfg.tint & 0xFF;
        if (g_cfg.lightMode) { tr = tg = tb = 255; }
        uint32_t* px = (uint32_t*)g_bakeBits;
        const size_t n = (size_t)w * h;
        for (size_t i = 0; i < n; i++) {
            uint32_t v = px[i];
            double bl = v & 0xFF, gn = (v >> 8) & 0xFF, rd = (v >> 16) & 0xFF;
            double lum = rd * 0.2126 + gn * 0.7152 + bl * 0.0722;
            double lift = (128.0 - lum) * 0.16;
            rd += lift; gn += lift; bl += lift;
            if (rd < 0) rd = 0; if (rd > 255) rd = 255;
            if (gn < 0) gn = 0; if (gn > 255) gn = 255;
            if (bl < 0) bl = 0; if (bl > 255) bl = 255;
            double gr = rd * (1 - t) + tr * t;
            double gg = gn * (1 - t) + tg * t;
            double gb = bl * (1 - t) + tb * t;
            gr = gr * a + rd * (1 - a);
            gg = gg * a + gn * (1 - a);
            gb = gb * a + bl * (1 - a);
            px[i] = 0xFF000000u | ((DWORD)gr << 16) | ((DWORD)gg << 8) | (DWORD)gb;
        }
    }

    g_bakeTick = GetTickCount();
    g_lastCaptureMs = GetTickCount() - bakeT0;""",
    'bake the tint mix into the backdrop')

# ---------------------------------------------------------------- 3. per frame: copy + masks
sub(
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
                double rr = CornerRadiusAt(x, y, w, h, baseRadius);
                // Proper rounded-box SDF: the old `sqrt(max(qx,0)^2+max(qy,0)^2) - rr`
                // only works while rr > 0 (rr stood in for the "inside" distance). With
                // a snapped corner rr = 0 the whole quadrant read as distance 0 ->
                // coverage 0.5, i.e. half the strip went 50% transparent exactly when
                // it docked against an edge. The min(max(qx,qy),0) term is the inside
                // distance and keeps the body opaque for rr = 0 too.
                double qx = fabs(x + 0.5 - cx) - (hw - rr);
                double qy = fabs(y + 0.5 - cy) - (hh - rr);
                double ax = qx > 0 ? qx : 0;
                double ay = qy > 0 ? qy : 0;
                double inx = qx > qy ? qx : qy;
                if (inx > 0) inx = 0;
                double d = sqrt(ax * ax + ay * ay) + inx - rr;
                double cov = 0.5 - d;
                if (cov <= 0) continue;
                if (cov > 1) cov = 1;
                uint32_t v = bake[(size_t)y * pw + x];
                // BGRA in the DIB: keep the channels straight. The old code mixed the
                // *blue* value with the tint's *red* and wrote it into the red byte (and
                // weighted luminance as if blue were red); invisible with a grey tint,
                // but it turned a saturated blue backdrop pink/salmon.
                double bl = v & 0xFF, gn = (v >> 8) & 0xFF, rd = (v >> 16) & 0xFF;
                // Acrylic's "background lighten": pull the blurred colour a little
                // towards mid grey. Without it a dark glass panel on top of a dark
                // window differs by ~2/255 and the dock looks like it has no body
                // at all; on a bright wallpaper it also stops the panel from
                // vanishing into white.
                {
                    double lum = rd * 0.2126 + gn * 0.7152 + bl * 0.0722;
                    double lift = (128.0 - lum) * 0.16;
                    rd += lift; gn += lift; bl += lift;
                    if (rd < 0) rd = 0; if (rd > 255) rd = 255;
                    if (gn < 0) gn = 0; if (gn > 255) gn = 255;
                    if (bl < 0) bl = 0; if (bl > 255) bl = 255;
                }
                double gr = rd * (1 - t) + tr * t;
                double gg = gn * (1 - t) + tg * t;
                double gb = bl * (1 - t) + tb * t;
                // The glass body is composited *opaque*: the (1 - a) part used to be the
                // live desktop showing through DWM, which also let the real, unblurred
                // window through - that is why text behind the strip stayed readable no
                // matter how big the blur radius was (the blur only ever touched the
                // bake). Screen it with the same blurred bake instead: same look for the
                // eye, but nothing sharp gets through. a still means "how much glass vs
                // how much clear backdrop".
                gr = gr * a + rd * (1 - a);
                gg = gg * a + gn * (1 - a);
                gb = gb * a + bl * (1 - a);
                DWORD alpha = (DWORD)(cov * 255);
                if (!alpha) continue;
                // Interior pixels are fully opaque: skip SetPixelPremul, whose three
                // integer divisions per pixel dominated the frame (this is the hot path -
                // 150k pixels per repaint).
                if (alpha >= 255) {
                    ((uint32_t*)g_paintBits)[(size_t)y * g_paintW + x] =
                        (255u << 24) | ((DWORD)gr << 16) | ((DWORD)gg << 8) | (DWORD)gb;
                } else {
                    SetPixelPremul(x, y,
                                   (alpha << 24) | ((DWORD)gr << 16) | ((DWORD)gg << 8) | (DWORD)gb);
                }
                // Soft rim light: 2.5 px falloff instead of a 1 px line. A hairline
                // on a curved edge is one pixel of aliasing and reads as a bad
                // cut-out; a gradient reads as an edge catching light.
                if (d > -2.5) {
                    double e = 1.0 + d / 2.5;          // 1 at the edge, 0 at 2.5 px in
                    if (e > 0) {
                        DWORD ea = (DWORD)(e * cov * 0.22 * 255);
                        if (ea) SetPixelPremul(x, y, (ea << 24) | 0x00FFFFFF);
                    }
                }
            }
        }
""",
    """        const uint32_t* bake = (const uint32_t*)g_bakeBits + (size_t)oy * pw + ox;
        // The tint/lift/opacity live in the bake already, so this pass is a copy plus the
        // precomputed per-strip-pixel coverage and rim.
        EnsureStripMasks(w, h, baseRadius);
        uint32_t* out = (uint32_t*)g_paintBits;
        for (int y = 0; y < h; y++) {
            const uint32_t* srcRow = bake + (size_t)y * pw;
            uint32_t* dstRow = out + (size_t)y * g_paintW;
            const BYTE* covRow = &g_covMask[(size_t)y * w];
            const BYTE* rimRow = &g_rimMask[(size_t)y * w];
            for (int x = 0; x < w; x++) {
                DWORD alpha = covRow[x];
                if (!alpha) continue;
                uint32_t v = srcRow[x];
                if (alpha >= 255) {
                    dstRow[x] = v;                       // fully opaque: straight copy
                } else {
                    SetPixelPremul(x, y, ((alpha) << 24) | (v & 0x00FFFFFF));
                }
                DWORD ea = rimRow[x];
                if (ea) SetPixelPremul(x, y, (ea << 24) | 0x00FFFFFF);
            }
        }
""",
    'per-frame pass becomes a copy + masks')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak21')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
