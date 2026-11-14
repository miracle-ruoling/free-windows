"""Patch dock.cpp: stop re-capturing on every resize step.

Why it flickered: `covered` used to demand an *exact* bake size (`g_bakeW == cr.right + 2*M`).
While the window is being dragged bigger, that is false on every single frame, so every frame
ran a full CaptureBackdrop() - which also free-reallocates the padded DIB (5.3 MB here). A
9-15 ms re-grab plus a DIB reallocation per frame is exactly what the eye sees as flicker.

The user's rule, implemented:
  * while resizing, keep using the snapshot as long as the window still fits inside it;
  * grab once at the moment the window outgrows the snapshot;
  * grab once more when the resize ends (WM_EXITSIZEMOVE already forces g_bakeDirty).

So `covered` becomes a containment test (the bake must be at least as large as the window and
must contain its screen rect) instead of an equality test, and a resize bakes with the wide
margin so one grab buys ~256 px of growth in every direction.
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


# 1) resize bakes with the wide margin (one grab covers ~256 px of growth per side)
sub(
    """    const int M = (g_dragging || g_resizeEdge) ? g_bakeMargin
                                              : (g_cfg.blurRadius > 0 ? 64 : 0);""",
    """    // A resize grows the window, so the bake has to be big enough that the next few
    // hundred pixels of growth are already inside it - otherwise every frame re-grabs.
    const int M = (g_dragging || g_resizeEdge) ? g_bakeMargin
                                              : (g_cfg.blurRadius > 0 ? 64 : 0);""",
    'resize margin comment (behaviour unchanged, wide while resizing)')

# 2) containment instead of exact size in the composite path
sub(
    """    if (g_cfg.material == 1 && g_bakeBits && g_bakeW == w + 2 * g_bakeMarginUsed &&
        g_bakeH == h + 2 * g_bakeMarginUsed) {""",
    """    if (g_cfg.material == 1 && g_bakeBits && g_bakeW >= w && g_bakeH >= h) {""",
    'Paint: accept a bake that is at least window-sized')

# 3) containment instead of exact size for the "do I need a new snapshot" decision
sub(
    """            int ox = curR.left - g_bakeOrigin.x, oy = curR.top - g_bakeOrigin.y;
            bool covered = g_bakeBits && g_bakeW == cr.right + 2 * M &&
                           g_bakeH == cr.bottom + 2 * M && ox >= 0 && oy >= 0 &&
                           ox + cr.right <= g_bakeW && oy + cr.bottom <= g_bakeH;""",
    """            int ox = curR.left - g_bakeOrigin.x, oy = curR.top - g_bakeOrigin.y;
            // Containment, not equality: as long as the window (any size) sits inside the
            // snapshot with its top-left at (ox, oy), the existing picture can be re-cropped
            // and nothing needs grabbing. An equality test re-grabbed on every resize frame.
            bool covered = g_bakeBits && g_bakeW >= cr.right && g_bakeH >= cr.bottom &&
                           ox >= 0 && oy >= 0 && ox + cr.right <= g_bakeW &&
                           oy + cr.bottom <= g_bakeH;""",
    'covered: containment test')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak22')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
