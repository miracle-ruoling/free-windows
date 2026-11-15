import io, re, sys

p = r"C:\Users\20979\RP_Projects\fly_bar\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()
orig = s

def rep(old, new, count=1):
    global s
    if old not in s:
        print("MISSING ANCHOR:", old[:70].replace("\n", "\\n"))
        sys.exit(1)
    s = s.replace(old, new, count)

# ---------------- config fields ----------------
rep("""    int thumbWidth = 220;
    int thumbHeight = 124;
    int thumbDelay = 400;        // ms before the preview appears""",
"""    int thumbWidth = 220;
    int thumbHeight = 124;
    int thumbDelay = 400;        // ms before the preview appears
    int minIcon = 18;            // icon size never goes below this
    int maxIcon = 72;            // ... nor above this
    int scrollStep = 1;          // items per wheel notch
    int allowResize = 1;         // drag the edges to resize
    int w = 0;                   // saved size
    int h = 0;
    int hasSize = 0;""")

rep("""    g_cfg.thumbDelay = GetInt(L"dock", L"thumbDelay", 400);""",
"""    g_cfg.thumbDelay = GetInt(L"dock", L"thumbDelay", 400);
    g_cfg.minIcon = GetInt(L"dock", L"minIcon", 18);
    g_cfg.maxIcon = GetInt(L"dock", L"maxIcon", 72);
    g_cfg.scrollStep = GetInt(L"dock", L"scrollStep", 1);
    g_cfg.allowResize = GetInt(L"dock", L"allowResize", 1);
    g_cfg.w = GetInt(L"dock", L"w", 0);
    g_cfg.h = GetInt(L"dock", L"h", 0);
    g_cfg.hasSize = GetInt(L"dock", L"hasSize", 0);
    if (g_cfg.scrollStep < 1) g_cfg.scrollStep = 1;""")

rep("""    WritePrivateProfileStringW(L"dock", L"thumbDelay", L"400", g_iniPath.c_str());""",
"""    WritePrivateProfileStringW(L"dock", L"thumbDelay", L"400", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"minIcon", L"18", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"maxIcon", L"72", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"scrollStep", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"allowResize", L"1", g_iniPath.c_str());""")

rep("""static void SavePosition() {
    wchar_t b[32];
    swprintf_s(b, L"%d", g_cfg.x); WritePrivateProfileStringW(L"dock", L"x", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", g_cfg.y); WritePrivateProfileStringW(L"dock", L"y", b, g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hasPos", L"1", g_iniPath.c_str());
}""",
"""static void SavePosition() {
    wchar_t b[32];
    swprintf_s(b, L"%d", g_cfg.x); WritePrivateProfileStringW(L"dock", L"x", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", g_cfg.y); WritePrivateProfileStringW(L"dock", L"y", b, g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hasPos", L"1", g_iniPath.c_str());
}

static void SaveSize() {
    RECT rc{};
    if (!GetClientRect(g_hwnd, &rc)) return;
    wchar_t b[32];
    swprintf_s(b, L"%d", rc.right); WritePrivateProfileStringW(L"dock", L"w", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", rc.bottom); WritePrivateProfileStringW(L"dock", L"h", b, g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hasSize", L"1", g_iniPath.c_str());
}""")

# ---------------- layout + paint ----------------
old_layout = s[s.index("static int ButtonSize()"):s.index("static void Present()")]
new_layout = '''struct Slot {
    RECT rc;
    int item;    // index into g_items, -1 = the "expand" button
};
static std::vector<Slot> g_slots;

static int g_iconPx = 32;
static int g_capacity = 0;      // how many cells fit
static int g_scroll = 0;        // first visible item
static bool g_expanded = false;
static RECT g_collapsedRect{};

static void SetPixelPremul(int x, int y, DWORD argb) {
    if (x < 0 || y < 0 || x >= g_dibW || y >= g_dibH) return;
    BYTE a = (BYTE)((argb >> 24) & 0xFF);
    BYTE r = (BYTE)(((argb >> 16) & 0xFF) * a / 255);
    BYTE g = (BYTE)(((argb >> 8) & 0xFF) * a / 255);
    BYTE b = (BYTE)((argb & 0xFF) * a / 255);
    BYTE* px = (BYTE*)g_bits + ((size_t)y * g_dibW + x) * 4;
    // premultiplied source over (mostly transparent) destination
    px[0] = (BYTE)(b + px[0] * (255 - a) / 255);
    px[1] = (BYTE)(g + px[1] * (255 - a) / 255);
    px[2] = (BYTE)(r + px[2] * (255 - a) / 255);
    px[3] = (BYTE)(a + px[3] * (255 - a) / 255);
}

static void DrawLine(int x0, int y0, int x1, int y1, int width, DWORD argb) {
    int dx = abs(x1 - x0), dy = abs(y1 - y0);
    int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;
    for (;;) {
        for (int oy = 0; oy < width; oy++)
            for (int ox = 0; ox < width; ox++) SetPixelPremul(x0 + ox, y0 + oy, argb);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 < dx) { err += dx; y0 += sy; }
    }
}

// Size drives the layout: the short side sets the icon size, the long side sets
// how many cells fit. Taller than wide => a vertical column.
static void ComputeButtons() {
    g_slots.clear();
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    int W = rc.right, H = rc.bottom;
    if (W <= 0 || H <= 0) return;
    bool vertical = (H > W);

    int pad = g_cfg.pad, gap = g_cfg.gap;
    int shortSide = vertical ? W : H;
    int icon = shortSide - pad * 2;
    if (icon < g_cfg.minIcon) icon = g_cfg.minIcon;
    if (icon > g_cfg.maxIcon) icon = g_cfg.maxIcon;
    int cell = icon + gap;
    int longSide = vertical ? H : W;
    int cap = (longSide - pad * 2 + gap) / cell;
    if (cap < 1) cap = 1;

    int n = (int)g_items.size();
    bool needExpand = (n > cap) && cap > 1;
    int show = needExpand ? cap - 1 : cap;

    if (g_scroll > n - show) g_scroll = n - show;
    if (g_scroll < 0) g_scroll = 0;

    g_iconPx = icon;
    g_capacity = cap;

    int x = pad, y = pad;
    for (int i = 0; i < show; i++) {
        int item = g_scroll + i;
        if (item >= n) break;
        Slot s;
        s.item = item;
        s.rc = {x, y, x + icon, y + icon};
        g_slots.push_back(s);
        if (vertical) y += cell; else x += cell;
    }
    if (needExpand) {
        Slot s;
        s.item = -1;
        s.rc = {x, y, x + icon, y + icon};
        g_slots.push_back(s);
    }
}

static void Paint(int w, int h) {
    EnsureDib(w, h);
    memset(g_bits, 0, (size_t)w * h * 4);
    RECT all{0, 0, w, h};
    if (g_cfg.bgAlpha) {
        FillRound(g_memDC, all, g_cfg.radius,
                  ((DWORD)g_cfg.bgAlpha << 24) | (GetRValue(g_cfg.bg) << 16) |
                      (GetGValue(g_cfg.bg) << 8) | GetBValue(g_cfg.bg));
    }
    for (size_t i = 0; i < g_slots.size(); i++) {
        const Slot& s = g_slots[i];
        if ((int)i == g_hover) {
            FillRound(g_memDC, s.rc, g_cfg.radius / 2 + 2,
                      ((DWORD)g_cfg.hoverAlpha << 24) | 0x00FFFFFF);
        }
        if (s.item < 0) {
            // "^" chevron, drawn by hand (GDI would write alpha 0 into the DIB)
            int cx = (s.rc.left + s.rc.right) / 2;
            int cy = (s.rc.top + s.rc.bottom) / 2;
            int r = g_iconPx / 4;
            DrawLine(cx - r, cy + r / 2, cx, cy - r / 2, 2, 0xF0FFFFFF);
            DrawLine(cx, cy - r / 2, cx + r, cy + r / 2, 2, 0xF0FFFFFF);
            continue;
        }
        Item& it = g_items[s.item];
        if (it.icon) {
            DrawIconEx(g_memDC, s.rc.left, s.rc.top, it.icon, g_iconPx, g_iconPx, 0, nullptr,
                       DI_NORMAL);
        }
        if (it.isPin && !it.hasWindow) {
            RECT d{s.rc.right - g_iconPx / 5, s.rc.bottom - g_iconPx / 5,
                   s.rc.right - g_iconPx / 12, s.rc.bottom - g_iconPx / 12};
            FillRound(g_memDC, d, 3, 0x60FFFFFF);
        }
    }
}

'''
s = s.replace(old_layout, new_layout, 1)

# ---------------- hover uses slots ----------------
rep("""        for (size_t i = 0; i < g_buttonRects.size(); i++) {
            if (PtInRect(&g_buttonRects[i], c)) { hover = (int)i; break; }
        }""",
"""        for (size_t i = 0; i < g_slots.size(); i++) {
            if (PtInRect(&g_slots[i].rc, c)) { hover = (int)i; break; }
        }""")

io.open(p, "w", encoding="utf-8").write(s)
print("patched layout/paint/config")
