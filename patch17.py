"""Patch dock.cpp: `presentSync` knob - wait for the compositor after each present.

The evidence (dev/glass_lag.py / dev/skew_check.py) says the glass content is occasionally
one frame *ahead* of the window geometry: on a fraction of frames the interior is displaced
by exactly the distance travelled in ~12-18 ms, and the sign follows the drag direction.
That asymmetry - content ahead, never behind - is what you get when the compositor samples
the layered bitmap lazily: our next frame is already rendered into the same DIB when DWM
composes the previous frame's window rectangle.

DwmFlush() returns after the next composition, so no frame can ever be composed while the
DIB already holds the frame after it. It costs the sync with the compositor (at most one
refresh), and the knob makes it easy to A/B the effect with dev/motion_probe.py +
dev/glass_lag.py, without needing anyone's eyes.
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
    """    int debugBeacon = 0;         // diagnostic: magenta marker at a fixed client position""",
    """    int debugBeacon = 0;         // diagnostic: magenta marker at a fixed client position
    int presentSync = 0;         // 1 = DwmFlush() after each present (see Present())""",
    'config field')

sub(
    """    g_cfg.debugBeacon = GetInt(L"dock", L"debugBeacon", 0);""",
    """    g_cfg.debugBeacon = GetInt(L"dock", L"debugBeacon", 0);
    g_cfg.presentSync = GetInt(L"dock", L"presentSync", 0);""",
    'config read')

sub(
    """    QueryPerformanceCounter(&p1);
    g_statPresent += QpcMs(p0, p1);
    g_statPresents++;
}""",
    """    if (g_cfg.presentSync) {
        // Return only after the compositor has taken this frame. Without it our next frame
        // can be drawn into the same DIB while DWM is still composing the previous window
        // rectangle, and the composite then shows new content at old geometry - a content
        // offset of "one frame's travel", jittering at the beat between our paint rate and
        // the compositor's rate.
        DwmFlush();
    }
    QueryPerformanceCounter(&p1);
    g_statPresent += QpcMs(p0, p1);
    g_statPresents++;
}""",
    'DwmFlush after present')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak17')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
