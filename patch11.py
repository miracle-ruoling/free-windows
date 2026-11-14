import io

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

start = s.index("// ---------------------------------------------------------------- settings UI")
end = s.index("static LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {")
old = s[start:end]

new = r'''// ---------------------------------------------------------------- settings UI
// Self-drawn panel: same layered/alpha pipeline as the dock, so it gets the same
// rounded, translucent look, and every change is applied while you drag.
struct SRow {
    const wchar_t* key;
    const wchar_t* label;
    int minv;
    int maxv;
    int colorAlpha;    // 1 = this row edits the alpha of a colour value
};

static const SRow kRows[] = {
    {L"material", L"玻璃 / 纯色", 0, 1, 0},
    {L"tintAlpha", L"玻璃不透明度", 0, 255, 1},
    {L"blurRadius", L"模糊半径", 0, 32, 0},
    {L"bakeRefreshMs", L"快照刷新 (ms)", 0, 2000, 0},
    {L"radius", L"圆角", 0, 40, 0},
    {L"iconSize", L"默认图标尺寸", 16, 96, 0},
    {L"fadeStart", L"完全显示距离", 0, 200, 0},
    {L"fadeEnd", L"完全透明距离", 20, 400, 0},
};
static const int kRowCount = (int)(sizeof(kRows) / sizeof(kRows[0]));

static HWND g_setWnd = nullptr;
static int g_rowVal[kRowCount]{};
static int g_dragRow = -1;
static HDC g_setDC = nullptr;
static HBITMAP g_setBmp = nullptr;
static void* g_setBits = nullptr;
static int g_setW = 460, g_setH = 400;

static int TintAlpha() { return (int)((g_cfg.tint >> 24) & 0xFF); }

static void RowLoad() {
    for (int i = 0; i < kRowCount; i++) {
        if (kRows[i].colorAlpha) {
            g_rowVal[i] = TintAlpha();
        } else {
            g_rowVal[i] = GetPrivateProfileIntW(L"dock", kRows[i].key, 0, g_iniPath.c_str());
        }
        if (g_rowVal[i] < kRows[i].minv) g_rowVal[i] = kRows[i].minv;
        if (g_rowVal[i] > kRows[i].maxv) g_rowVal[i] = kRows[i].maxv;
    }
}

static void RowApply(int i) {
    wchar_t buf[64]{};
    if (kRows[i].colorAlpha) {
        DWORD tint = (g_cfg.tint & 0x00FFFFFF) | ((DWORD)g_rowVal[i] << 24);
        swprintf_s(buf, L"#%08X", tint);
        WritePrivateProfileStringW(L"dock", L"tint", buf, g_iniPath.c_str());
    } else {
        swprintf_s(buf, L"%d", g_rowVal[i]);
        WritePrivateProfileStringW(L"dock", kRows[i].key, buf, g_iniPath.c_str());
    }
    Reload();
    RowLoad();
}

// GDI text into a 32bpp DIB leaves alpha at 0; render white text on black and
// rebuild the alpha from luminance, then composite with premultiplied maths.
static void DrawTextAlpha(int x, int y, int w, int h, const std::wstring& text, int px,
                          DWORD rgb) {
    if (!g_setBits || w <= 0 || h <= 0) return;
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    HBITMAP bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    HDC dc = CreateCompatibleDC(screen);
    HGDIOBJ old = SelectObject(dc, bmp);
    memset(bits, 0, (size_t)w * h * 4);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    HFONT font = CreateFontW(px, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH, L"Microsoft YaHei UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    RECT tr{0, 0, w, h};
    DrawTextW(dc, text.c_str(), -1, &tr, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS);
    SelectObject(dc, oldFont);
    DeleteObject(font);

    auto* src = (uint32_t*)bits;
    DWORD r0 = rgb & 0xFF, g0 = (rgb >> 8) & 0xFF, b0 = (rgb >> 16) & 0xFF;
    for (int yy = 0; yy < h; yy++) {
        for (int xx = 0; xx < w; xx++) {
            uint32_t v = src[(size_t)yy * w + xx];
            int a = (v >> 16) & 0xFF;            // white text: any channel works
            if (a <= 2) continue;
            SetPixelPremul(x + xx, y + yy,
                           ((DWORD)a << 24) | ((DWORD)(r0 * a / 255) << 16) |
                               ((DWORD)(g0 * a / 255) << 8) | (DWORD)(b0 * a / 255));
        }
    }
    SelectObject(dc, old);
    DeleteObject(bmp);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
}

static void SettingsPaint() {
    if (!g_setWnd) return;
    if (!g_setBits) {
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = g_setW;
        bi.bmiHeader.biHeight = -g_setH;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        HDC screen = GetDC(nullptr);
        g_setDC = CreateCompatibleDC(screen);
        g_setBmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &g_setBits, nullptr, 0);
        SelectObject(g_setDC, g_setBmp);
        ReleaseDC(nullptr, screen);
    }
    memset(g_setBits, 0, (size_t)g_setW * g_setH * 4);

    // panel body: same rounded, translucent treatment as the dock
    FillRound(g_setDC, RECT{0, 0, g_setW, g_setH}, g_cfg.radius + 4, 0xE61C1C1C);
    FillRound(g_setDC, RECT{1, 1, g_setW - 1, g_setH - 1}, g_cfg.radius + 4, 0x1AFFFFFF);

    DrawTextAlpha(20, 14, 240, 28, L"dock 设置", 17, 0xFFFFFF);
    DrawTextAlpha(g_setW - 120, 18, 100, 22, L"拖动滑条即时生效", 12, 0x9AFFFFFF);

    int y = 58;
    for (int i = 0; i < kRowCount; i++) {
        DrawTextAlpha(22, y, 190, 24, kRows[i].label, 13, 0xE6FFFFFF);
        wchar_t val[32]{};
        swprintf_s(val, L"%d", g_rowVal[i]);
        DrawTextAlpha(g_setW - 118, y, 60, 24, val, 13, 0xFFFFFFFF);

        int tx = 232, tw = g_setW - 232 - 130;
        int ty = y + 11;
        FillRound(g_setDC, RECT{tx, ty, tx + tw, ty + 4}, 2, 0x40FFFFFF);
        double frac = (kRows[i].maxv > kRows[i].minv)
                          ? (double)(g_rowVal[i] - kRows[i].minv) / (kRows[i].maxv - kRows[i].minv)
                          : 0.0;
        int px = tx + (int)(frac * tw);
        FillRound(g_setDC, RECT{tx, ty, px, ty + 4}, 2, 0xFF4C9AFF);
        FillRound(g_setDC, RECT{px - 6, ty - 5, px + 6, ty + 9}, 6, 0xFFFFFFFF);
        y += 38;
    }

    BOOL ok = FALSE;
    BOOL useAlpha = TRUE;
    BLENDFUNCTION bf{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    SIZE size{g_setW, g_setH};
    POINT srcPt{0, 0};
    UpdateLayeredWindow(g_setWnd, nullptr, nullptr, &size, g_setDC, &srcPt, 0, &bf, ULW_ALPHA);
}

static int RowAt(int y) {
    int start = 58;
    for (int i = 0; i < kRowCount; i++) {
        if (y >= start && y < start + 38) return i;
        start += 38;
    }
    return -1;
}

static void RowFromX(int i, int x) {
    if (i < 0) return;
    int tx = 232, tw = g_setW - 232 - 130;
    double frac = (double)(x - tx) / tw;
    if (frac < 0) frac = 0;
    if (frac > 1) frac = 1;
    int v = kRows[i].minv + (int)(frac * (kRows[i].maxv - kRows[i].minv) + 0.5);
    if (v != g_rowVal[i]) {
        g_rowVal[i] = v;
        RowApply(i);
        SettingsPaint();
    }
}

static LRESULT CALLBACK SettingsWndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_LBUTTONDOWN: {
            int i = RowAt(GET_Y_LPARAM(lp));
            if (i >= 0) {
                g_dragRow = i;
                SetCapture(h);
                RowFromX(i, GET_X_LPARAM(lp));
            } else if (GET_Y_LPARAM(lp) > g_setH - 46) {
                DestroyWindow(h);
            }
            return 0;
        }
        case WM_MOUSEMOVE:
            if (g_dragRow >= 0) RowFromX(g_dragRow, GET_X_LPARAM(lp));
            return 0;
        case WM_LBUTTONUP:
            if (g_dragRow >= 0) {
                g_dragRow = -1;
                ReleaseCapture();
            }
            return 0;
        case WM_CLOSE:
            DestroyWindow(h);
            return 0;
        case WM_DESTROY:
            g_setWnd = nullptr;
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

static void ShowSettings() {
    if (g_setWnd) {
        SetForegroundWindow(g_setWnd);
        return;
    }
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW wc{sizeof(wc)};
        wc.lpfnWndProc = SettingsWndProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = L"DockSettingsWindow";
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        RegisterClassExW(&wc);
        registered = true;
    }
    RowLoad();
    g_setH = 58 + kRowCount * 38 + 46;
    g_setWnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, L"DockSettingsWindow", L"dock 设置",
                               WS_POPUP, 240, 140, g_setW, g_setH, nullptr, nullptr,
                               GetModuleHandleW(nullptr), nullptr);
    if (!g_setWnd) return;
    g_setBits = nullptr;
    SettingsPaint();
    ShowWindow(g_setWnd, SW_SHOW);
    SetForegroundWindow(g_setWnd);
}

'''

s = s[:start] + new + s[end:]
io.open(p, "w", encoding="utf-8").write(s)
print("self-drawn settings panel")
