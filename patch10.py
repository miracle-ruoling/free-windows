import io

p = r"C:\Users\20979\RP_Projects\fly_bar\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

if "SettingsWndProc" in s:
    print("already there")
    raise SystemExit

settings = r'''
// ---------------------------------------------------------------- settings UI
// A plain Win32 window with one edit box per config key: it writes dock.ini and
// re-applies immediately, so the effect can be seen without restarting.
struct SettingField {
    const wchar_t* key;
    const wchar_t* label;
    const wchar_t* def;
    int isColor;
};

static const SettingField kFields[] = {
    {L"material", L"material (0 纯色 / 1 玻璃)", L"1", 0},
    {L"blurRadius", L"blurRadius 模糊半径 (0-32)", L"8", 0},
    {L"bakeRefreshMs", L"bakeRefreshMs 快照刷新(ms)", L"900", 0},
    {L"tint", L"tint 玻璃色调 (#AARRGGBB)", L"#99101010", 1},
    {L"radius", L"radius 圆角", L"12", 0},
    {L"bg", L"bg 纯色底 (#AARRGGBB)", L"#3C000000", 1},
    {L"bgAlpha", L"bgAlpha 纯色不透明度", L"60", 0},
    {L"fadeStart", L"fadeStart 完全显示距离", L"48", 0},
    {L"fadeEnd", L"fadeEnd 完全透明距离", L"144", 0},
    {L"iconSize", L"iconSize 默认图标尺寸", L"40", 0},
    {L"gap", L"gap 图标间距", L"6", 0},
    {L"pad", L"pad 内边距", L"10", 0},
    {L"scrollStep", L"scrollStep 滚轮步长", L"1", 0},
    {L"thumbDelay", L"thumbDelay 预览延迟(ms)", L"400", 0},
    {L"upscaleSmallIcons", L"upscaleSmallIcons 小图标放大", L"1", 0},
};
static const int kFieldCount = (int)(sizeof(kFields) / sizeof(kFields[0]));

static HWND g_settingsWnd = nullptr;
static HWND g_fieldEdits[kFieldCount]{};

static void SettingsApply(bool save) {
    for (int i = 0; i < kFieldCount; i++) {
        wchar_t buf[128]{};
        GetWindowTextW(g_fieldEdits[i], buf, 128);
        if (!buf[0]) continue;
        if (save || true) WritePrivateProfileStringW(L"dock", kFields[i].key, buf, g_iniPath.c_str());
    }
    Reload();
}

static LRESULT CALLBACK SettingsWndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CREATE: {
            int y = 12;
            for (int i = 0; i < kFieldCount; i++) {
                CreateWindowExW(0, L"STATIC", kFields[i].label, WS_CHILD | WS_VISIBLE, 14, y + 3, 260,
                                22, h, nullptr, nullptr, nullptr);
                wchar_t val[128]{};
                GetPrivateProfileStringW(L"dock", kFields[i].key, kFields[i].def, val, 128,
                                         g_iniPath.c_str());
                g_fieldEdits[i] = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", val,
                                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 284, y,
                                                  150, 24, h, (HMENU)(INT_PTR)(100 + i), nullptr,
                                                  nullptr);
                y += 30;
            }
            CreateWindowExW(0, L"BUTTON", L"应用", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 14,
                            y + 8, 100, 28, h, (HMENU)1, nullptr, nullptr);
            CreateWindowExW(0, L"BUTTON", L"恢复默认", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 124,
                            y + 8, 100, 28, h, (HMENU)2, nullptr, nullptr);
            CreateWindowExW(0, L"BUTTON", L"关闭", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 234,
                            y + 8, 100, 28, h, (HMENU)3, nullptr, nullptr);
            return 0;
        }
        case WM_COMMAND:
            if (LOWORD(wp) == 1) SettingsApply(true);
            else if (LOWORD(wp) == 2) {
                for (int i = 0; i < kFieldCount; i++) {
                    SetWindowTextW(g_fieldEdits[i], kFields[i].def);
                    WritePrivateProfileStringW(L"dock", kFields[i].key, kFields[i].def,
                                               g_iniPath.c_str());
                }
                Reload();
            } else if (LOWORD(wp) == 3) DestroyWindow(h);
            return 0;
        case WM_CLOSE:
            DestroyWindow(h);
            return 0;
        case WM_DESTROY:
            g_settingsWnd = nullptr;
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

static void ShowSettings() {
    if (g_settingsWnd) {
        SetForegroundWindow(g_settingsWnd);
        return;
    }
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc{sizeof(wc)};
        wc.lpfnWndProc = SettingsWndProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = L"DockSettingsWindow";
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
        RegisterClassExW(&wc);
        registered = true;
    }
    int height = 60 + kFieldCount * 30 + 60;
    g_settingsWnd = CreateWindowExW(WS_EX_TOPMOST, L"DockSettingsWindow", L"dock 设置",
                                    WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, 200, 120, 470, height,
                                    nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (g_settingsWnd) {
        ShowWindow(g_settingsWnd, SW_SHOW);
        SetForegroundWindow(g_settingsWnd);
    }
}
'''

# insert before WndProc so the menu can call it
anchor = "static LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {"
assert anchor in s
s = s.replace(anchor, settings + "\n" + anchor, 1)

# menu entry
s = s.replace("""            AppendMenuW(menu, MF_STRING, 4, L"打开日志");""",
              """            AppendMenuW(menu, MF_STRING, 4, L"打开日志");
            AppendMenuW(menu, MF_STRING, 5, L"设置…");""", 1)
s = s.replace("""            else if (cmd == 4) ShellExecuteW(nullptr, L"open", g_logPath.c_str(), nullptr, nullptr,
                                            SW_SHOWNORMAL);""",
              """            else if (cmd == 4) ShellExecuteW(nullptr, L"open", g_logPath.c_str(), nullptr, nullptr,
                                            SW_SHOWNORMAL);
            else if (cmd == 5) ShowSettings();""", 1)

io.open(p, "w", encoding="utf-8").write(s)
print("settings ui added")
