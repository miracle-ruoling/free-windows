"""Patch dock.cpp: `presentOrder` knob - three ways to commit position + pixels.

The glass content is occasionally one frame of travel *behind* the world (measured:
skew = v * 12-14 ms on ~20% of frames, NCC 1.000). Since content and position are handed to
the OS in a single UpdateLayeredWindow, the only way that happens is that the two land in
different compositions. This knob tries the three orderings so the effect can be A/B'd with
dev/motion_probe.py + dev/content_anchor.py instead of argued about:

  0 = UpdateLayeredWindow(pptDst)            - today
  1 = SetWindowPos first, then ULW without a destination (pixels only)
  2 = ULW without a destination first, then SetWindowPos
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
    """    int presentSync = 0;         // 1 = DwmFlush() after each present (see Present())""",
    """    int presentSync = 0;         // 1 = DwmFlush() after each present (see Present())
    int presentOrder = 0;        // 0 = ULW+pptDst, 1 = SetWindowPos then ULW, 2 = ULW then SWP""",
    'config field')

sub(
    """    g_cfg.presentSync = GetInt(L"dock", L"presentSync", 0);""",
    """    g_cfg.presentSync = GetInt(L"dock", L"presentSync", 0);
    g_cfg.presentOrder = GetInt(L"dock", L"presentOrder", 0);""",
    'config read')

sub(
    """    LARGE_INTEGER p0{}, p1{};
    QueryPerformanceCounter(&p0);
    UpdateLayeredWindow(g_hwnd, nullptr, pdst, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
""",
    """    LARGE_INTEGER p0{}, p1{};
    QueryPerformanceCounter(&p0);
    if (pdst && g_cfg.presentOrder == 1) {
        // position first, pixels second
        SetWindowPos(g_hwnd, HWND_TOPMOST, dst.x, dst.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
        UpdateLayeredWindow(g_hwnd, nullptr, nullptr, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
    } else if (pdst && g_cfg.presentOrder == 2) {
        // pixels first, position second
        UpdateLayeredWindow(g_hwnd, nullptr, nullptr, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
        SetWindowPos(g_hwnd, HWND_TOPMOST, dst.x, dst.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
    } else {
        UpdateLayeredWindow(g_hwnd, nullptr, pdst, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
    }
""",
    'present ordering')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak18')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
