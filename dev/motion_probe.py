"""Grab real frames of the screen *while the strip is moving under a held button*.

The old dragshot.ps1 stopped the mouse, waited 25 ms and only then captured - by then the
strip had settled, so a motion-only artefact could never show up. Here the mouse is
driven from a second thread and frames are grabbed from the main thread, so every capture
lands in the middle of a real, held drag. The strip is swung horizontally: the strip is
1428 px wide, so the overlap between a resting frame and a moving frame stays >1000 px,
which is what makes a pixel-exact correlation possible.

usage: python dev/motion_probe.py [outdir]
"""
import ctypes
import ctypes.wintypes as wt
import json
import os
import sys
import threading
import time

import numpy as np

user32 = ctypes.WinDLL('user32', use_last_error=True)
gdi32 = ctypes.WinDLL('gdi32', use_last_error=True)
user32.SetProcessDPIAware()

CLASS = 'DockStripWindow'
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004


class RECT(ctypes.Structure):
    _fields_ = [('left', ctypes.c_long), ('top', ctypes.c_long),
                ('right', ctypes.c_long), ('bottom', ctypes.c_long)]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [('biSize', ctypes.c_uint32), ('biWidth', ctypes.c_long),
                ('biHeight', ctypes.c_long), ('biPlanes', ctypes.c_uint16),
                ('biBitCount', ctypes.c_uint16), ('biCompression', ctypes.c_uint32),
                ('biSizeImage', ctypes.c_uint32), ('biXPelsPerMeter', ctypes.c_long),
                ('biYPelsPerMeter', ctypes.c_long), ('biClrUsed', ctypes.c_uint32),
                ('biClrImportant', ctypes.c_uint32)]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [('bmiHeader', BITMAPINFOHEADER), ('bmiColors', ctypes.c_uint32 * 3)]


ENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)


def find_strip():
    found = []

    def cb(h, lp):
        buf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(h, buf, 256)
        if buf.value == CLASS:
            found.append(h)
            return False
        return True

    user32.EnumWindows(ENUMPROC(cb), 0)
    return found[0] if found else None


def rect_of(h):
    r = RECT()
    user32.GetWindowRect(h, ctypes.byref(r))
    return (r.left, r.top, r.right, r.bottom)


class Grabber:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h
        screen = user32.GetDC(None)
        self.mdc = gdi32.CreateCompatibleDC(screen)
        bi = BITMAPINFO()
        bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bi.bmiHeader.biWidth = w
        bi.bmiHeader.biHeight = -h
        bi.bmiHeader.biPlanes = 1
        bi.bmiHeader.biBitCount = 32
        bi.bmiHeader.biCompression = 0
        self.bits = ctypes.c_void_p()
        self.bmp = gdi32.CreateDIBSection(screen, ctypes.byref(bi), 0,
                                          ctypes.byref(self.bits), None, 0)
        gdi32.SelectObject(self.mdc, self.bmp)
        user32.ReleaseDC(None, screen)

    def grab(self):
        src = user32.GetDC(None)
        ok = gdi32.BitBlt(self.mdc, 0, 0, self.w, self.h, src, self.x, self.y, 0x00CC0020)
        user32.ReleaseDC(None, src)
        if not ok:
            raise RuntimeError('BitBlt failed')
        buf = ctypes.string_at(self.bits, self.w * self.h * 4)
        a = np.frombuffer(buf, dtype=np.uint8).reshape(self.h, self.w, 4)
        return a[:, :, :3].copy()


class Mover(threading.Thread):
    """Holds the button and sweeps the cursor left<->right at a constant speed."""

    def __init__(self, x0, y, span, speed, seconds):
        super().__init__(daemon=True)
        self.x0, self.y, self.span, self.speed, self.seconds = x0, y, span, speed, seconds
        self.stop = False
        self.steps = 0
        self.error = None

    def run(self):
        t0 = time.perf_counter()
        phase = 0.0          # 0..1 along the sweep
        direction = 1
        step = self.speed * 0.004        # 4 ms of travel per iteration
        while not self.stop and time.perf_counter() - t0 < self.seconds:
            phase += direction * step / self.span
            if phase >= 1.0:
                phase = 1.0
                direction = -1
            elif phase <= 0.0:
                phase = 0.0
                direction = 1
            if not user32.SetCursorPos(int(round(self.x0 + phase * self.span)), self.y):
                self.error = ctypes.get_last_error()
                return
            self.steps += 1
            time.sleep(0.004)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else 'dev/motion'
    hwnd = find_strip()
    if not hwnd:
        print('no strip window')
        return 1
    L0, T0, R0, B0 = rect_of(hwnd)
    w, h = R0 - L0, B0 - T0
    print('strip', (L0, T0, R0, B0), 'size', w, h)

    sw = user32.GetSystemMetrics(0)
    sh = user32.GetSystemMetrics(1)
    span = int(sys.argv[2]) if len(sys.argv) > 2 else 330
    # optional: grab only one narrow band (small BitBlt = no tearing while the strip moves)
    band = None
    if len(sys.argv) > 5:
        band = (int(sys.argv[4]), int(sys.argv[5]))
    gx = max(0, L0 - 10)
    gy = max(0, T0 - 8)
    gw = min(sw, R0 + span + 12) - gx
    gh = min(sh, B0 + 8) - gy
    print('grab region', gx, gy, gw, gh)
    grab = Grabber(gx, gy, gw, gh)
    os.makedirs(outdir, exist_ok=True)

    frames, tags = [], []
    meta = {'strip0': [L0, T0, R0, B0], 'grab': [gx, gy, gw, gh], 'rects': []}

    def has_beacon(img):
        a = img.astype('int16')
        return int(((a[:, :, 0] > 200) & (a[:, :, 1] < 80) & (a[:, :, 2] > 200)).sum()) > 20

    def snap(tag, need_beacon=False):
        # The dock sets WDA_EXCLUDEFROMCAPTURE while it takes its own backdrop snapshot, so
        # roughly a quarter of grabs *miss the strip entirely*. A reference frame without
        # the strip would poise the whole measurement as "aligned", so wait for one that has
        # the debug beacon in it.
        for _ in range(30 if need_beacon else 1):
            img = grab.grab()
            if not need_beacon or has_beacon(img):
                break
            time.sleep(0.01)
        t = time.perf_counter()
        frames.append(img)
        tags.append(tag)
        meta['rects'].append({'tag': tag, 't': t, 'rect': list(rect_of(hwnd))})
        return img

    cx, cy = L0 + 24, T0 + h // 2
    user32.SetCursorPos(cx, cy)
    time.sleep(0.7)              # fade settles with the cursor on the strip
    snap('rest', need_beacon=True)
    time.sleep(0.12)
    snap('rest', need_beacon=True)

    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, None)
    time.sleep(0.04)
    user32.SetCursorPos(cx + 8, cy)          # past the 4 px drag threshold
    time.sleep(0.06)
    snap('drag0')

    speed = float(sys.argv[3]) if len(sys.argv) > 3 else 1500.0
    print('sweep span', span, 'speed', speed)
    mover = Mover(cx + 8, cy, span, speed=speed, seconds=2.4)
    mover.start()
    fast = len(sys.argv) > 6 and sys.argv[6] == 'fast'
    t_end = time.time() + 2.4
    while time.time() < t_end:
        snap('move')
        if not fast:
            time.sleep(0.02)
    mover.stop = True
    mover.join(timeout=1.0)

    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, None)
    time.sleep(0.5)
    snap('after')

    # walk the strip home again so the user's layout is untouched
    Ln, Tn, _, _ = rect_of(hwnd)
    dx, dy = Ln - L0, Tn - T0
    if dx or dy:
        user32.SetCursorPos(Ln + 24, Tn + h // 2)
        time.sleep(0.2)
        user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, None)
        time.sleep(0.05)
        for i in range(1, 26):
            user32.SetCursorPos(Ln + 24 - int(dx * i / 25), Tn + h // 2 - int(dy * i / 25))
            time.sleep(0.02)
        user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, None)
        time.sleep(0.4)
    meta['restored'] = list(rect_of(hwnd))

    np.save(os.path.join(outdir, 'frames.npy'), np.stack(frames))
    with open(os.path.join(outdir, 'meta.json'), 'w') as f:
        json.dump({'meta': meta, 'tags': tags}, f, indent=1)
    print('saved', len(frames), 'frames to', outdir)
    print('mover steps', mover.steps, 'err', mover.error)
    print('restored to', meta['restored'], 'from', meta['strip0'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
