"""Patch dock.cpp: add a debug beacon (ini `debugBeacon=1`).

Why: to tell "the glass content is misplaced" apart from "the whole window is one
composition late", one has to read *both* the body position and the content position out of
the *same* composed frame. The icons cannot be used - over a colourful backdrop they look
exactly like the backdrop. A 10x10 magenta block drawn into the surface at a fixed client
position is unmistakable and travels with the body, so:

    skew = content shift - beacon shift

0 means the frame is self-consistent (nothing to fix in the pixels); anything else is a real
per-frame displacement of the glass relative to its own body.
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
    """    int dumpBake = 0;            // diagnostic: write the captured backdrop""",
    """    int dumpBake = 0;            // diagnostic: write the captured backdrop
    int debugBeacon = 0;         // diagnostic: magenta marker at a fixed client position""",
    'config field')

sub(
    """    g_cfg.dumpBake = GetInt(L"dock", L"dumpBake", 0);""",
    """    g_cfg.dumpBake = GetInt(L"dock", L"dumpBake", 0);
    g_cfg.debugBeacon = GetInt(L"dock", L"debugBeacon", 0);""",
    'config read')

sub(
    """    QueryPerformanceCounter(&q2);
    g_statGlass += QpcMs(q0, q1);
    g_statIcons += QpcMs(q1, q2);
    g_statPaints++;
}""",
    """    if (g_cfg.debugBeacon) {
        // A marker that is part of the surface: it tells anyone reading a screenshot where
        // the compositor put this window, independently of what the glass content shows.
        int bx = 8, by = h / 2 - 5;
        for (int yy = 0; yy < 10; yy++)
            for (int xx = 0; xx < 10; xx++)
                if (bx + xx < w && by + yy < h)
                    ((uint32_t*)g_paintBits)[(size_t)(by + yy) * g_paintW + bx + xx] =
                        0xFFFF00FFu;      // premultiplied magenta, opaque
    }
    QueryPerformanceCounter(&q2);
    g_statGlass += QpcMs(q0, q1);
    g_statIcons += QpcMs(q1, q2);
    g_statPaints++;
}""",
    'beacon drawing')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak16')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
