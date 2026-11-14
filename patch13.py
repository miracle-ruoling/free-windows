"""Patch dock.cpp: make the backdrop snapshot cheap, and keep it fresh during drags.

Findings behind this patch (2026-11-14):
  * PrintWindow of the window underneath costs 31-39 ms here (it makes that app re-render
    its whole 1938x1098 window for a 1940x631 crop). A plain BitBlt of the composited
    screen with WDA_EXCLUDEFROMCAPTURE costs ~7 ms and is the more truthful source.
  * With blurRadius = 0 the bake still ran a per-pixel "bilinear upscale" over the entire
    padded bake (1.2 M px) that is mathematically an identity - ~10 ms of nothing.
  * Captures were forbidden while dragging, so the glass showed a frozen snapshot for as
    long as the drag lasted. That frozen picture is what reads as "the backdrop inside the
    strip is displaced" as soon as anything behind the strip moves (animated wallpaper,
    video, scrolling page) - and it snaps back on release, when a fresh bake runs.
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
    """Replace once, translating bare \\n in the literals to the file's line ending."""
    global src
    o = old.replace('\n', nl)
    n = new.replace('\n', nl)
    if src.count(o) != 1:
        print('FAIL [%s]: found %d matches' % (why, src.count(o)))
        sys.exit(1)
    src = src.replace(o, n)
    print('ok   %s' % why)


# ---------------------------------------------------------------- 1. cheap source
sub(
    """    // grab our (padded) rect out of whatever we are covering
    std::vector<uint32_t> fbuf((size_t)w * h, 0xFF202020);
    HWND under = WindowUnderUs(wr);
""",
    """    // Grab our (padded) rect out of whatever we are covering.
    // Source order matters for cost: reading the composited screen is one BitBlt of the
    // padded rect (~7 ms measured here), while PrintWindow of the window underneath costs
    // 31-39 ms - it makes that app re-render its *entire* window (1938x1098 here) so we
    // can keep a 1940x631 crop of it. The screen grab is also the more truthful source:
    // it is literally what is on screen now (video, UWP, layered widgets and all).
    // PrintWindow still wins in exactly one case: when one of *our own* popups is over the
    // strip (hover preview, a tray menu, the grid, the settings panel). A screen grab would
    // bake that popup into the glass, while PrintWindow of the window underneath ignores it.
    const bool ownPopup = g_popupOpen || g_menuOpen || g_gridVisible || g_setWnd ||
                          (g_thumbWnd && IsWindowVisible(g_thumbWnd));
    std::vector<uint32_t> fbuf((size_t)w * h, 0xFF202020);
    HWND under = ownPopup ? WindowUnderUs(wr) : nullptr;
""",
    'prefer the composited screen over PrintWindow')

# ---------------------------------------------------------------- 2. no hide/show storm
sub(
    """    BOOL excluded = SetWindowDisplayAffinity(g_hwnd, WDA_EXCLUDEFROMCAPTURE);
    if (!excluded) ShowWindow(g_hwnd, SW_HIDE);
""",
    """    BOOL excluded = SetWindowDisplayAffinity(g_hwnd, WDA_EXCLUDEFROMCAPTURE);
    if (!excluded) {
        // Without the capture-exclusion flag the only way to keep ourselves out of the
        // picture is to hide the window for the grab. That is a visible blink, so it was
        // fine at 3 grabs/s and is not fine now that the snapshot refreshes 25-30x/s:
        // rather than flicker, keep the previous bake until the next slow moment.
        static DWORD lastHideGrab = 0;
        DWORD t = GetTickCount();
        if (lastHideGrab && t - lastHideGrab < 500) return false;
        lastHideGrab = t;
        ShowWindow(g_hwnd, SW_HIDE);
    }
""",
    'rate-limit the hide/show fallback')

# ---------------------------------------------------------------- 3. step == 1 is a copy
sub(
    """    // upscale back into the draw buffer: bilinear, otherwise the 4x4 blocks of
    // the quarter-resolution buffer show up as a visible grid at low radii
    auto* dst = (uint32_t*)g_bakeBits;
    for (int y = 0; y < h; y++) {
""",
    """    // upscale back into the draw buffer: bilinear, otherwise the 4x4 blocks of
    // the quarter-resolution buffer show up as a visible grid at low radii
    auto* dst = (uint32_t*)g_bakeBits;
    if (step == 1) {
        // blur off -> step 1: the downscale above was a 1:1 copy and this "bilinear
        // upscale" is an identity, but it still ran a lambda per pixel over the whole
        // padded bake (1.2 M px at margin 256). That was ~10 ms of pure waste per capture.
        memcpy(dst, fbuf.data(), (size_t)w * h * 4);
    } else
    for (int y = 0; y < h; y++) {
""",
    'skip the identity resample when blur is off')

# ---------------------------------------------------------------- 4. keep it fresh while dragging
sub(
    """            bool captureDue = false;
            if (g_cfg.captureHz > 0) {
                UINT capMs = (UINT)(1000 / g_cfg.captureHz);
                if (capMs < 1) capMs = 1;
                // A capture costs g_lastCaptureMs (20-40ms here). Asking for 65/s used to
                // starve the whole frame loop, so keep at least 2x the measured cost as a
                // gap whatever the setting says.
                DWORD floorMs = g_lastCaptureMs * 2;
                if (floorMs > capMs) capMs = floorMs;
                if (now - lastBake >= capMs) {
                    lastBake = now;
                    captureDue = true;
                }
            }
            bool busy = g_dragging || g_resizeEdge;
            // While the strip is being dragged, never capture: one grab is 20-25ms, which
            // at any useful capture rate would eat the whole loop (and it is exactly what
            // made dragging stutter). The last snapshot is reused until the drag ends.
            if (busy) captureDue = false;
""",
    """            bool captureDue = false;
            // Dragging used to be a no-capture zone ("one grab is 20-25 ms"), which left
            // the glass showing a *frozen* snapshot for as long as the drag lasted. Nothing
            // about that is visible over a still backdrop, but as soon as anything behind
            // the strip moves - an animated wallpaper, a video, a page that scrolls - the
            // frozen copy sits at the wrong place and reads as "the backdrop is displaced",
            // then snaps back the moment the button is released and a fresh bake runs.
            // With the screen-grab source a bake is ~7 ms, so dragging keeps refreshing,
            // just at a calmer rate than at rest.
            bool busy = g_dragging || g_resizeEdge;
            if (g_cfg.captureHz > 0) {
                UINT capMs = (UINT)(1000 / g_cfg.captureHz);
                if (capMs < 1) capMs = 1;
                // A capture costs g_lastCaptureMs. Asking for 65/s used to starve the
                // whole frame loop, so keep at least 2x the measured cost as a gap
                // whatever the setting says.
                DWORD floorMs = g_lastCaptureMs * 2;
                if (floorMs > capMs) capMs = floorMs;
                if (busy && capMs < 90) capMs = 90;    // mid-drag: fresh, but not frantic
                if (now - lastBake >= capMs) {
                    lastBake = now;
                    captureDue = true;
                }
            }
""",
    'let the snapshot refresh while dragging')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak13')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s (%d bytes -> %d bytes)' % (P, len(orig), len(src)))
