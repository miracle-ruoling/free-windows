// Does DWM blur-behind work on this machine for a topmost, click-through, popup window
// with a rounded region?  Three variants side by side so one screenshot answers it:
//   A = ACCENT_ENABLE_ACRYLICBLURBEHIND (Win11 acrylic, tintable)
//   B = ACCENT_ENABLE_BLURBEHIND        (older blur, tintable)
//   C = no accent at all                (control: should be invisible)
// Nothing is painted into the client area on purpose - that is what lets the compositor
// fill it with a blurred copy of whatever is behind the window *right now*, at composite
// time, with no read-back and therefore no way for it to lag the window.
//
//   acrylic_test.exe [seconds] [x] [y]
#include <windows.h>
#include <cstdio>

enum { ACCENT_DISABLED = 0, ACCENT_ENABLE_GRADIENT = 1, ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
       ACCENT_ENABLE_BLURBEHIND = 3, ACCENT_ENABLE_ACRYLICBLURBEHIND = 4 };
struct ACCENTPOLICY { int nAccentState; int nFlags; DWORD nColor; int nAnimationId; };
struct WINCOMPATTRDATA { int nAttribute; PVOID pData; ULONG ulDataSize; };
enum { WCA_ACCENT_POLICY = 19 };

static void ApplyAccent(HWND hwnd, int state, DWORD color) {
    static auto setAttr = (BOOL(WINAPI*)(HWND, const WINCOMPATTRDATA*))GetProcAddress(
        GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute");
    if (!setAttr) { OutputDebugStringW(L"no SetWindowCompositionAttribute\n"); return; }
    ACCENTPOLICY policy{state, state == ACCENT_ENABLE_TRANSPARENTGRADIENT ? 0x13 : 0, color, 0};
    WINCOMPATTRDATA data{WCA_ACCENT_POLICY, &policy, sizeof(policy)};
    setAttr(hwnd, &data);
}

static LRESULT CALLBACK WP(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

static HWND Make(const wchar_t* cls, int x, int y, int cw, int ch, int radius,
                 int accent, DWORD tint) {
    HWND h = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                                 WS_EX_TRANSPARENT,
                             cls, L"", WS_POPUP, x, y, cw, ch, nullptr, nullptr,
                             GetModuleHandleW(nullptr), nullptr);
    if (!h) return nullptr;
    if (radius > 0) {
        HRGN r = CreateRoundRectRgn(0, 0, cw + 1, ch + 1, radius * 2, radius * 2);
        SetWindowRgn(h, r, TRUE);
    }
    ApplyAccent(h, accent, tint);
    ShowWindow(h, SW_SHOWNA);
    return h;
}

int wmain(int argc, wchar_t** argv) {
    int seconds = argc > 1 ? _wtoi(argv[1]) : 20;
    int x = argc > 2 ? _wtoi(argv[2]) : 300;
    int y = argc > 3 ? _wtoi(argv[3]) : 420;
    WNDCLASSW wc{};
    wc.lpfnWndProc = WP;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"AcrylicProbeWindow";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;          // never paint: the accent fills the client area
    RegisterClassW(&wc);

    const int W = 360, H = 140, GAP = 16;
    HWND a = Make(wc.lpszClassName, x, y, W, H, 24, ACCENT_ENABLE_ACRYLICBLURBEHIND, 0xA6101010);
    HWND b = Make(wc.lpszClassName, x + W + GAP, y, W, H, 24, ACCENT_ENABLE_BLURBEHIND, 0xA6101010);
    HWND c = Make(wc.lpszClassName, x + 2 * (W + GAP), y, W, H, 24, ACCENT_DISABLED, 0);
    if (!a || !b || !c) { wprintf(L"create failed %lu\n", GetLastError()); return 1; }
    wprintf(L"acrylic=%p blur=%p none=%p  for %d s\n", a, b, c, seconds);
    fflush(stdout);

    DWORD t0 = GetTickCount();
    MSG msg;
    while (GetTickCount() - t0 < (DWORD)seconds * 1000) {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        Sleep(20);
    }
    DestroyWindow(a); DestroyWindow(b); DestroyWindow(c);
    return 0;
}
