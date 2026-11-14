// traypost.cpp - post a tray callback message to an icon owner window
//   traypost <hwndHex> <cbMsgHex> <uid> <lParamHex> [x y]
#include <windows.h>
#include <cstdio>
#include <cstdlib>

int wmain(int argc, wchar_t** argv) {
    if (argc < 5) {
        wprintf(L"usage: traypost <hwndHex> <cbMsgHex> <uid> <lParamHex> [x y]\n");
        return 2;
    }
    HWND hwnd = (HWND)(ULONG_PTR)wcstoull(argv[1], nullptr, 16);
    UINT msg = (UINT)wcstoul(argv[2], nullptr, 16);
    WPARAM uid = (WPARAM)wcstoul(argv[3], nullptr, 10);
    LPARAM lp = (LPARAM)wcstoull(argv[4], nullptr, 16);
    if (argc >= 7) {
        int x = _wtoi(argv[5]), y = _wtoi(argv[6]);
        SetCursorPos(x, y);
        wprintf(L"cursor -> %d,%d\n", x, y);
        Sleep(120);
    }
    BOOL ok = PostMessageW(hwnd, msg, uid, lp);
    wprintf(L"post hwnd=%p msg=0x%X uid=%u lparam=0x%X -> %d (err %lu)\n", (void*)hwnd, msg,
            (unsigned)uid, (unsigned)lp, ok, GetLastError());
    return 0;
}
