"""Drag a companion window and measure what the *screen* actually shows.

Why: the drag handler itself is fine - with 144 injected steps/s the window's rect changes
145 times/s (dev/t_dragfps.ps1), so "it looks like 30 fps" cannot be explained by our message
handling. The remaining variable is what the compositor puts on screen, and that can only be
measured by grabbing frames while the window is being dragged.

How: a band covering the whole drag path is BitBlt'ed from a second thread (a small band does
not tear, and ~200 grabs/s is enough for a 144 Hz screen). For every frame the script records
the window's *reported* rect, the cursor and the pixels. Afterwards the bar is located in the
pixels by correlating it against a template cut from the first frame, so we get two series:
  reported position (what the window says)   vs   displayed position (what is on the screen)
and the difference is the lag, in pixels and in frames.

usage:
  python dev/tray_drag_shots.py -dy 400 -seconds 2.0 -speed 900
  python dev/tray_drag_shots.py -dx 250 -dy 250 -target strip
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import json
import os
import threading
import time

import numpy as np

user32 = ctypes.WinDLL('user32', use_last_error=True)
gdi32 = ctypes.WinDLL('gdi32', use_last_error=True)
user32.SetProcessDPIAware()

CLASSES = {'tray': 'DockTrayBarWindow', 'strip': 'DockStripWindow'}
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004


class RECT(ctypes.Structure):
    _fields_ = [('left', ctypes.c_long), ('top', ctypes.c_long),
                ('right', ctypes.c_long), ('bottom', ctypes.c_long)]


class POINT(ctypes.Structure):
    _fields_ = [('x', ctypes.c_long), ('y', ctypes.c_long)]


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


def find_window(cls):
    found = []

    def cb(h, lp):
        buf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(h, buf, 256)
        if buf.value == cls:
            found.append(h)
            return False
        return True

    user32.EnumWindows(ENUMPROC(cb), 0)
    return found[0] if found else None


def rect_of(h):
    r = RECT()
    user32.GetWindowRect(h, ctypes.byref(r))
    return (r.left, r.top, r.right, r.bottom)


def cursor():
    p = POINT()
    user32.GetCursorPos(ctypes.byref(p))
    return (p.x, p.y)


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
        gdi32.BitBlt(self.mdc, 0, 0, self.w, self.h, src, self.x, self.y, 0x00CC0020)
        user32.ReleaseDC(None, src)
        buf = ctypes.string_at(self.bits, self.w * self.h * 4)
        a = np.frombuffer(buf, dtype=np.uint8).reshape(self.h, self.w, 4)
        return a[:, :, :3].copy()


class Mover(threading.Thread):
    """Holds the button and walks the cursor along the path at a constant speed."""

    def __init__(self, start, dx, dy, speed, seconds):
        super().__init__(daemon=True)
        self.start, self.dx, self.dy = start, dx, dy
        self.speed, self.seconds = speed, seconds
        self.stop = False
        self.steps = 0

    def run(self):
        t0 = time.perf_counter()
        length = max(1.0, (self.dx ** 2 + self.dy ** 2) ** 0.5)
        phase = 0.0
        direction = 1
        step = self.speed * 0.003 / length
        while not self.stop and time.perf_counter() - t0 < self.seconds:
            phase += direction * step
            if phase >= 1.0:
                phase, direction = 1.0, -1
            elif phase <= 0.0:
                phase, direction = 0.0, 1
            user32.SetCursorPos(int(round(self.start[0] + self.dx * phase)),
                               int(round(self.start[1] + self.dy * phase)))
            self.steps += 1
            time.sleep(0.003)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-target', default='tray')
    ap.add_argument('-dx', type=int, default=0)
    ap.add_argument('-dy', type=int, default=400)
    ap.add_argument('-seconds', type=float, default=2.0)
    ap.add_argument('-speed', type=float, default=900.0, help='px/s')
    ap.add_argument('-outdir', default='dev/traymotion')
    args = ap.parse_args()

    cls = CLASSES[args.target]
    h = find_window(cls)
    if not h:
        print('no', cls, 'window')
        return 1
    strip = find_window('DockStripWindow')
    L0, T0, R0, B0 = rect_of(h)
    w, hh = R0 - L0, B0 - T0
    print('window', cls, (L0, T0, R0, B0), 'size', w, hh)

    sw, sh = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
    # band: the whole path plus the window, plus a margin for the correlation search
    margin = 70
    bx = max(0, min(L0, L0 + args.dx) - margin)
    by = max(0, min(T0, T0 + args.dy) - margin)
    bw = min(sw, max(R0, R0 + args.dx) + margin) - bx
    bh = min(sh, max(B0, B0 + args.dy) + margin) - by
    print('band', bx, by, bw, bh)
    grab = Grabber(bx, by, bw, bh)
    os.makedirs(args.outdir, exist_ok=True)

    # the companion only appears while the pointer is on the strip
    if args.target == 'tray' and strip:
        s = rect_of(strip)
        user32.SetCursorPos((s[0] + s[2]) // 2, (s[1] + s[3]) // 2)
        time.sleep(0.45)

    grab_x = 46 if args.target == 'tray' else 40
    gx, gy = L0 + grab_x, (T0 + B0) // 2
    user32.SetCursorPos(gx, gy)
    time.sleep(0.35)
    ref = grab.grab()
    template = ref[T0 - by:T0 - by + hh, L0 - bx:L0 - bx + w].copy()
    np.save(os.path.join(args.outdir, 'template.npy'), template)

    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, None)
    time.sleep(0.06)

    frames, meta = [], []
    stop = threading.Event()

    def sampler():
        while not stop.is_set():
            img = grab.grab()
            t = time.perf_counter()
            frames.append(img)
            meta.append([t, rect_of(h), cursor()])

    th = threading.Thread(target=sampler, daemon=True)
    th.start()
    mover = Mover((gx, gy), args.dx, args.dy, args.speed, args.seconds)
    time.sleep(0.05)
    mover.start()
    mover.join(timeout=args.seconds + 1.0)
    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, None)
    time.sleep(0.25)
    stop.set()
    th.join(timeout=2.0)

    # walk the window back so the user's layout is untouched
    Ln, Tn = rect_of(h)[:2]
    if (Ln, Tn) != (L0, T0):
        user32.SetCursorPos(Ln + grab_x, (Tn + Tn + hh) // 2)
        time.sleep(0.2)
        user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, None)
        time.sleep(0.05)
        for i in range(1, 26):
            user32.SetCursorPos(Ln + grab_x - int((Ln - L0) * i / 25),
                               (Tn + hh // 2) - int((Tn - T0) * i / 25))
            time.sleep(0.015)
        user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, None)
        time.sleep(0.3)
    restored = rect_of(h)

    axis = 1 if abs(args.dy) >= abs(args.dx) else 0
    print('captured', len(frames), 'frames, mover steps', mover.steps)
    np.save(os.path.join(args.outdir, 'frames.npy'), np.stack(frames[-400:]))
    with open(os.path.join(args.outdir, 'meta.json'), 'w') as f:
        json.dump({'band': [bx, by, bw, bh], 'start': [L0, T0, R0, B0],
                   'axis': axis, 'dx': args.dx, 'dy': args.dy,
                   'speed': args.speed, 'restored': list(restored),
                   'meta': meta}, f)
    print('saved to', args.outdir, '| restored', restored)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
