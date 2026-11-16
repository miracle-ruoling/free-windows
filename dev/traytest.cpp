// dev/traytest.cpp - test twin of a "needs a double click" tray app, for H1.2.
//
// It registers a tray icon with an unmistakable magenta disc (so a probe can find its cell
// in the dock's grid by colour) and it only shows its window when two left clicks arrive
// within 600 ms - exactly the behaviour some real apps have in the native notification area.
//
// Build (see dev/build_traytest.ps1):
//   cl /nologo /EHsc /MT /std:c++17 /utf-8 /DUNICODE /D_UNICODE /O2 traytest.cpp
//      /link /SUBSYSTEM:WINDOWS /OUT:traytest.exe user32.lib gdi32.lib shell32.lib
#include <windows.h>
#include <shellapi.h>
#include <cstdio>

static const UINT WM_TRAYCB = WM_APP + 1;
static const UINT kIconId = 1;
static DWORD g_lastClick = 0;
static int g_clicks = 0;
static HWND g_win = nullptr;

static HICON MakeIcon() {
    BITMAPV5HEADER bi{};
    bi.bV5Size = sizeof(bi);
    bi.bV5Width = 32;
    bi.bV5Height = -32;
    bi.bV5Planes = 1;
    bi.bV5BitCount = 32;
    bi.bV5Compression = BI_BITFIELDS;
    bi.bV5RedMask = 0x00FF0000;
    bi.bV5GreenMask = 0x0000FF00;
    bi.bV5BlueMask = 0x000000FF;
    bi.bV5AlphaMask = 0xFF000000u;
    void* bits = nullptr;
    HDC dc = GetDC(nullptr);
    HBITMAP color = CreateDIBSection(dc, (BITMAPINFO*)&bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, dc);
    if (!color || !bits) return LoadIconW(nullptr, IDI_APPLICATION);
    auto* px = (DWORD*)bits;
    for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
            const int dx = x - 16, dy = y - 16;
            px[y * 32 + x] = (dx * dx + dy * dy <= 13 * 13) ? 0xFFFF00FFu : 0x00000000u;
        }
    }
    HBITMAP mask = CreateBitmap(32, 32, 1, 1, nullptr);
    ICONINFO ii{};
    ii.fIcon = TRUE;
    ii.hbmMask = mask;
    ii.hbmColor = color;
    HICON ic = CreateIconIndirect(&ii);
    DeleteObject(color);
    DeleteObject(mask);
    return ic ? ic : LoadIconW(nullptr, IDI_APPLICATION);
}

static void AddIcon(HWND h, HICON ic) {
    NOTIFYICONDATAW nid{};
    nid.cbSize = sizeof(nid);
    nid.hWnd = h;
    nid.uID = kIconId;
    nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = WM_TRAYCB;
    nid.hIcon = ic;
    wcscpy_s(nid.szTip, L"traytest (double click only)");
    // Deliberately the classic (pre-4) callback convention: wParam = icon id,
    // lParam = message, which is what dock.exe posts.
    Shell_NotifyIconW(NIM_ADD, &nid);
}

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_TRAYCB: {
            UINT msg = (UINT)l;
            if (msg != WM_LBUTTONUP && LOWORD(l) == WM_LBUTTONUP) msg = WM_LBUTTONUP;
            if (msg == WM_LBUTTONUP) {
                const DWORD now = GetTickCount();
                const bool dbl = g_lastClick && (now - g_lastClick) < 600;
                g_lastClick = now ? now : 1;
                g_clicks++;
                if (dbl) {
                    ShowWindow(h, SW_SHOW);
                    SetForegroundWindow(h);
                    SetWindowTextW(h, L"traytest: DOUBLE CLICK WORKED");
                } else {
                    SetWindowTextW(h, L"traytest: single click (ignored)");
                }
            }
            return 0;
        }
        case WM_CLOSE:
            DestroyWindow(h);
            return 0;
        case WM_DESTROY: {
            NOTIFYICONDATAW nid{};
            nid.cbSize = sizeof(nid);
            nid.hWnd = h;
            nid.uID = kIconId;
            Shell_NotifyIconW(NIM_DELETE, &nid);
            PostQuitMessage(0);
            return 0;
        }
        case WM_PAINT: {
            PAINTSTRUCT ps{};
            HDC dc = BeginPaint(h, &ps);
            RECT rc{};
            GetClientRect(h, &rc);
            wchar_t text[200];
            swprintf_s(text, L"clicks received: %d\nlast message: 0x%04X\n\n"
                             L"single click = nothing, double click = this window",
                       g_clicks, (unsigned)WM_LBUTTONUP);
            DrawTextW(dc, text, -1, &rc, DT_LEFT | DT_TOP | DT_WORDBREAK | DT_EDITCONTROL);
            EndPaint(h, &ps);
            return 0;
        }
    }
    return DefWindowProcW(h, m, w, l);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = inst;
    wc.lpszClassName = L"TrayTestWindow";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    RegisterClassExW(&wc);
    g_win = CreateWindowExW(WS_EX_TOOLWINDOW, L"TrayTestWindow", L"traytest: single click (ignored)",
                            0, 300, 300, 420, 180, nullptr, nullptr, inst, nullptr);
    if (!g_win) return 1;
    AddIcon(g_win, MakeIcon());

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}
