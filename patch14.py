"""Patch dock.cpp (2/2): the cached screen grab must expire while dragging too.

ScreenCacheTtl() deliberately returned 1500 ms while dragging ("never grab mid-drag").
That was right when a grab cost 20-25 ms and dragging was a no-grab zone anyway; now it
would hand the very same stale snapshot back for 1.5 s during the drag, which is the bug
this whole change is about.
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
    """static DWORD ScreenCacheTtl() {
    DWORD t;
    if (g_dragging || g_resizeEdge) t = 1500;          // never grab mid-drag
    else if (g_cfg.captureHz > 0) t = (DWORD)(1000 / g_cfg.captureHz);
    else t = 3600000;
    return t < 50 ? 50 : t;
}""",
    """static DWORD ScreenCacheTtl() {
    // This used to be 1500 ms while dragging, on the assumption that dragging never
    // re-grabs. It does now, and a 1.5 s cached snapshot in the middle of a drag is
    // exactly the frozen backdrop the glass was being blamed for.
    DWORD t;
    if (g_cfg.captureHz > 0) t = (DWORD)(1000 / g_cfg.captureHz);
    else t = 3600000;
    return t < 50 ? 50 : t;
}""",
    'screen cache TTL follows captureHz while dragging')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak14')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
