"""Patch dock.cpp (3/3): the remaining per-capture overhead.

Profiling after the screen-grab change showed bake=20.3 ms per capture with blurRadius=0.
The BitBlt is only ~7 ms of that; the rest was pure waste:

  * the "downsample" loop still averaged 1x1 blocks over the whole padded bake (1.2 M px)
    when step == 1, i.e. a per-pixel copy through a nested loop with bounds checks;
  * the bake debug line fires whenever the signature changes - and `grabbed` flips between
    1 (fresh) and 2 (cached) on every capture - and each firing runs DetailScore twice over
    that same 1.2 M px.
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


# ---------------------------------------------------------------- 1. skip the 1:1 downsample
sub(
    """    int sw = (w + step - 1) / step, sh = (h + step - 1) / step;
    std::vector<uint32_t> qbuf((size_t)sw * sh, 0xFF202020);
    for (int y = 0; y < sh; y++) {
""",
    """    int sw = (w + step - 1) / step, sh = (h + step - 1) / step;
    std::vector<uint32_t> qbuf;
    if (step == 1) {
        // blur is off, so the "downsample" below would average 1x1 blocks - a copy
        // through a nested loop with bounds checks, over the whole padded bake
        // (1.2 M px at margin 256). ~10 ms per capture for nothing.
        qbuf = fbuf;
    } else {
    qbuf.assign((size_t)sw * sh, 0xFF202020);
    for (int y = 0; y < sh; y++) {
""",
    'skip the 1:1 downsample loop')

sub(
    """            if (n) qbuf[(size_t)y * sw + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n) | 0xFF000000;
        }
    }
""",
    """            if (n) qbuf[(size_t)y * sw + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n) | 0xFF000000;
        }
    }
    }
""",
    'close the new else block')

# ---------------------------------------------------------------- 2. rate-limit the bake log
sub(
    """        DWORD t = GetTickCount();
        if (sig != lastSig || !got || t - lastLog > 5000) {
            lastSig = sig;
            lastLog = t;
""",
    """        DWORD t = GetTickCount();
        // `grabbed` is part of the signature and flips between 1 (fresh grab) and 2
        // (cached), so this line used to fire on every capture - and each firing runs
        // DetailScore twice over the whole padded bake. Rate-limit it.
        if (((sig != lastSig || !got) && t - lastLog > 1500) || t - lastLog > 5000) {
            lastSig = sig;
            lastLog = t;
""",
    'rate-limit the bake debug line')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak15')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
