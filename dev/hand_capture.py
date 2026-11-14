"""Record what the screen really shows while *you* drag the strip; analysis is separate.

Why this exists: every frame contains both the strip's position and its glass content, so
a displacement between the two can be measured without knowing *when* the frame was
composed - which is what defeated the old "stop the mouse, wait, then screenshot" test.
It only needs a real drag (a hand) and a backdrop that is not itself changing.

It watches the strip's rect and saves one crop per position change (plus two rest
references at the start).  The crop is the union of the rect before and after the grab,
padded, so a frame that is one composition old is still fully inside it.

usage: python dev/hand_capture.py [seconds] [max_frames] [outdir]
"""
import ctypes
import ctypes.wintypes as wt
import json
import os
import sys
import time

import numpy as np
from PIL import Image

user32 = ctypes.WinDLL('user32', use_last_error=True)
gdi32 = ctypes.WinDLL('gdi32', use_last_error=True)
user32.SetProcessDPIAware()

CLASS = 'DockStripWindow'
PAD = 64            # padding around the strip's rect inside each saved crop


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


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 240.0
    max_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 150
    outdir = sys.argv[3] if len(sys.argv) > 3 else 'dev/hand'
    os.makedirs(outdir, exist_ok=True)

    hwnd = find_strip()
    if not hwnd:
        print('no strip window')
        return 1
    print('strip', rect_of(hwnd), flush=True)

    screen = user32.GetDC(None)
    mdc = gdi32.CreateCompatibleDC(screen)
    sw, sh = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
    bi = BITMAPINFO()
    bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.bmiHeader.biWidth = sw
    bi.bmiHeader.biHeight = -sh
    bi.bmiHeader.biPlanes = 1
    bi.bmiHeader.biBitCount = 32
    bits = ctypes.c_void_p()
    bmp = gdi32.CreateDIBSection(screen, ctypes.byref(bi), 0, ctypes.byref(bits), None, 0)
    gdi32.SelectObject(mdc, bmp)
    user32.ReleaseDC(None, screen)

    def grab_all():
        src = user32.GetDC(None)
        gdi32.BitBlt(mdc, 0, 0, sw, sh, src, 0, 0, 0x00CC0020)
        user32.ReleaseDC(None, src)
        a = np.frombuffer(ctypes.string_at(bits, sw * sh * 4), np.uint8)
        return a.reshape(sh, sw, 4)[:, :, 2::-1]        # BGRA -> RGB

    meta = {'frames': [], 'pad': PAD, 'screen': [sw, sh]}
    saved = 0
    moves = 0
    last_rect = None

    def save_frame(tag, r_before, r_after):
        nonlocal saved
        img = grab_all()
        rs = [r for r in (r_before, r_after) if r]
        x0 = max(0, min(r[0] for r in rs) - PAD)
        y0 = max(0, min(r[1] for r in rs) - PAD)
        x1 = min(sw, max(r[2] for r in rs) + PAD)
        y1 = min(sh, max(r[3] for r in rs) + PAD)
        crop = np.ascontiguousarray(img[y0:y1, x0:x1])
        Image.fromarray(crop).save(os.path.join(outdir, 'f%04d.png' % saved),
                                   compress_level=3)
        meta['frames'].append({'i': saved, 't': time.perf_counter(), 'tag': tag,
                               'rect': list(r_after or r_before),
                               'crop': [x0, y0, x1, y1]})
        saved += 1
        return crop.shape

    t0 = time.perf_counter()
    r = rect_of(hwnd)
    save_frame('rest', r, r)
    time.sleep(0.15)
    save_frame('rest', r, r)
    last_rect = rect_of(hwnd)
    print('rest reference saved (crop %s); now drag the strip around (%.0fs budget)'
          % (meta['frames'][-1]['crop'], seconds), flush=True)

    while time.perf_counter() - t0 < seconds:
        r = rect_of(hwnd)
        if r != last_rect:
            moves += 1
            if saved < max_frames:
                r_after = None
                save_frame('move', last_rect, r)
                r_after = rect_of(hwnd)
                meta['frames'][-1]['rect'] = list(r_after)
                print('frame %d  %s' % (saved - 1, (r[0], r[1])), flush=True)
            last_rect = r
        else:
            time.sleep(0.003)

    with open(os.path.join(outdir, 'meta.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('done: %d frames, %d position changes' % (saved, moves), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
