// Creates windows whose styles probe the "does it get a taskbar button" rule.
//   winstyle.exe [seconds]
// Window A: WS_EX_TOOLWINDOW | WS_EX_APPWINDOW, titled  -> the shell buttons it
// Window B: no ex-style, no title                        -> the shell buttons it too
#include <windows.h>
#include <cstdio>

static LRESULT CALLBACK WP(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

int wmain(int argc, wchar_t** argv) {
    int seconds = argc > 1 ? _wtoi(argv[1]) : 30;
    WNDCLASSW wc{};
    wc.lpfnWndProc = WP;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"StyleProbeWindow";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 2);
    RegisterClassW(&wc);

    HWND a = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_APPWINDOW, wc.lpszClassName, L"TOOLAPP-TEST",
                             WS_OVERLAPPEDWINDOW, 120, 160, 380, 200, nullptr, nullptr, wc.hInstance,
                             nullptr);
    HWND b = CreateWindowExW(0, wc.lpszClassName, L"",
                             WS_OVERLAPPEDWINDOW, 540, 160, 380, 200, nullptr, nullptr,
                             wc.hInstance, nullptr);
    ShowWindow(a, SW_SHOWNOACTIVATE);
    ShowWindow(b, SW_SHOWNOACTIVATE);
    UpdateWindow(a);
    UpdateWindow(b);
    wprintf(L"A(hwnd=%p) B(hwnd=%p) lifetime=%ds\n", (void*)a, (void*)b, seconds);
    fflush(stdout);

    DWORD end = GetTickCount() + (DWORD)seconds * 1000;
    MSG msg;
    while (GetTickCount() < end) {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        Sleep(30);
    }
    DestroyWindow(a);
    DestroyWindow(b);
    return 0;
}
