"""Patch dock.cpp: two fixes.

1) Hover preview title. ThumbPaint() looked up `g_items[g_thumbIndex]`, but g_thumbIndex is a
   *slot* index. Slot -> item goes through g_scroll, so as soon as the strip is scrolled the
   title showed whatever item used to live in that slot ("clash verge" for slot 0 no matter
   what was actually there). The preview picture was always correct - it registers the item's
   own hwnd - which is exactly the asymmetry the user described. Fix: remember the item index.

2) Fully transparent strip: the window keeps a user-chosen width that is wider than the icons,
   so the visible content is only the icon row while the resize band sits on an *invisible*
   window edge - you can no longer find it. The white rim cannot come back (the user likes it
   gone). Instead, when the strip is fully transparent, a finished resize snaps the window
   back to the tight box around the icons (+pad). The 10 px edge band then lands exactly on the
   ring just outside the icons and the 24x24 corner zones land on the outer corners of the two
   end icons - i.e. right where the user can see something - and the icon size / icon count do
   not change because the box is derived from them.
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


# ---------------------------------------------------------------- 1. preview title
sub(
    """static int g_thumbIndex = -1;""",
    """static int g_thumbIndex = -1;
static int g_thumbItem = -1;    // item behind the preview: slot index != item index when scrolled""",
    'thumbnail item index')

sub(
    """    if (g_thumbWnd && IsWindowVisible(g_thumbWnd)) ShowWindow(g_thumbWnd, SW_HIDE);
    g_thumbIndex = -1;""",
    """    if (g_thumbWnd && IsWindowVisible(g_thumbWnd)) ShowWindow(g_thumbWnd, SW_HIDE);
    g_thumbIndex = -1;
    g_thumbItem = -1;""",
    'reset the item index too')

sub(
    """    std::wstring title = (g_thumbIndex >= 0 && g_thumbIndex < (int)g_items.size())
                             ? g_items[g_thumbIndex].title
                             : L"";""",
    """    // g_thumbItem, not g_thumbIndex: the slot index only equals the item index at scroll 0
    std::wstring title = (g_thumbItem >= 0 && g_thumbItem < (int)g_items.size())
                             ? g_items[g_thumbItem].title
                             : L"";""",
    'preview title from the item index')

sub(
    """    g_thumbIndex = index;
    InvalidateRect(g_thumbWnd, nullptr, TRUE);""",
    """    g_thumbIndex = index;
    g_thumbItem = itemIndex;
    InvalidateRect(g_thumbWnd, nullptr, TRUE);""",
    'remember the item index')

# ---------------------------------------------------------------- 2. shrink to icons
sub(
    """static int EdgeAt(POINT p, const RECT& rc) {""",
    """// A fully transparent strip draws nothing over its padding, so a window wider than the
// icons leaves the resize band on an invisible edge. Snap the window back to the box the
// icons actually occupy (+pad) once a resize finishes: the edge band then sits on the ring
// just outside the icons and the corner zones on the end icons' corners, and because the box
// is derived from the icons, neither their size nor their count changes.
static void ShrinkToIcons() {
    if (!g_hwnd) return;
    if (!(g_cfg.glassOpacity == 0 && g_cfg.tintStrength == 0)) return;   // only when invisible
    RECT wr{};
    if (!GetWindowRect(g_hwnd, &wr)) return;
    ComputeButtons();
    int cells = (int)g_slots.size();
    if (cells < 1) return;
    const int pad = g_cfg.pad, gap = g_cfg.gap;
    int span = cells * (g_iconPx + gap) - gap;
    int tw, th;
    if (g_cfg.vertical) { th = span + pad * 2; tw = g_iconPx + pad * 2; }
    else { tw = span + pad * 2; th = g_iconPx + pad * 2; }
    int oldW = wr.right - wr.left, oldH = wr.bottom - wr.top;
    if (tw == oldW && th == oldH) return;
    if (tw <= 0 || th <= 0) return;
    // keep the centre where it was, so the strip settles instead of jumping to one side
    int x = wr.left + (oldW - tw) / 2;
    int y = wr.top + (oldH - th) / 2;
    DLog(L"shrink: %dx%d -> %dx%d at %d,%d (transparent strip hugs its icons)",
         oldW, oldH, tw, th, x, y);
    g_cfg.x = x;
    g_cfg.y = y;
    g_cfg.w = tw;
    g_cfg.h = th;
    SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, tw, th, SWP_NOACTIVATE);
    ComputeButtons();
    g_bakeDirty = true;
    SavePosition();
    SaveSize();
    PaintAndPresent();
}

static int EdgeAt(POINT p, const RECT& rc) {""",
    'shrink-to-icons helper')

sub(
    """            if (g_resizeEdge) {
                g_resizeEdge = 0;
                ReleaseCapture();
                SavePosition();
                SaveSize();
                PaintAndPresent();
                return 0;
            }""",
    """            if (g_resizeEdge) {
                g_resizeEdge = 0;
                ReleaseCapture();
                SavePosition();
                SaveSize();
                PaintAndPresent();
                ShrinkToIcons();     // transparent strip only: snap back to the icon box
                return 0;
            }""",
    'call it when a resize ends')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak23')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
