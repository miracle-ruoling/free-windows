"""Patch dock.cpp: shrink the padded bake when nothing can move it.

The glass can only be as fresh as the backdrop read-back allows, and the read-back is the
ceiling the user is hitting with an animated wallpaper: 16-20 snapshots/s against a 60 fps
background always looks "shifted".

A capture currently reads `strip + 2*256 px` on every side - 2082x633 for this strip - and
most of that area only exists so a *drag* can re-crop the same bake while it moves. When the
strip is not being dragged nothing can move it, so that padding is pure cost: it is ~5.3 MB
per capture on this machine, and the pipeline copies it twice.

So: keep the wide margin while dragging (a drag re-crops instead of re-grabbing), and grab
just the strip itself at rest. Same freshness for ~45% less per capture, which is what lets
captureHz go up without eating the frame loop.
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
    """static int g_bakeMargin = 256;   // TEMP experiment: fewer re-bakes while dragging""",
    """static int g_bakeMargin = 256;   // TEMP experiment: fewer re-bakes while dragging
// Margin actually baked into the current picture. A drag needs the padding (it re-crops the
// same bake instead of re-grabbing); at rest nothing can move the strip, so only the strip
// itself is grabbed - which is ~45% cheaper per capture and directly buys snapshot rate.
static int g_bakeMarginUsed = 0;""",
    'margin-used global')

sub(
    """    const int M = g_bakeMargin;
    int w = cw + 2 * M, h = ch + 2 * M;
""",
    """    // wide margin while dragging, tight otherwise (see g_bakeMarginUsed)
    const int M = (g_dragging || g_resizeEdge) ? g_bakeMargin
                                              : (g_cfg.blurRadius > 0 ? 64 : 0);
    g_bakeMarginUsed = M;
    int w = cw + 2 * M, h = ch + 2 * M;
""",
    'capture margin depends on the drag state')

sub(
    """    if (g_cfg.material == 1 && g_bakeBits && g_bakeW == w + 2 * g_bakeMargin &&
        g_bakeH == h + 2 * g_bakeMargin) {""",
    """    if (g_cfg.material == 1 && g_bakeBits && g_bakeW == w + 2 * g_bakeMarginUsed &&
        g_bakeH == h + 2 * g_bakeMarginUsed) {""",
    'Paint: verify against the margin actually used')

sub(
    """            const int M = g_bakeMargin;""",
    """            const int M = g_bakeMarginUsed;""",
    'RenderTick: covered-check against the margin actually used')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak20')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
