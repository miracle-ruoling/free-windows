import io

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()


def rep(a, b, label=""):
    global s
    if a not in s:
        raise SystemExit("MISSING: " + (label or a[:60]))
    s = s.replace(a, b, 1)


# ---- 1. drop the second window / accent: it was the flicker source --------
rep("""static HWND g_bgWnd;""", """static HWND g_bgWnd_unused;""", "bgwnd decl") if "static HWND g_bgWnd;" in s else None

s = s.replace("    SyncBackground();\n", "")
s = s.replace("static void SyncBackground();\n", "")

# ---- 2. baked backdrop ----------------------------------------------------
rep("""static void PaintAndPresent() {""",
    """// Glass background without the GPU cost: grab the desktop behind the strip
// once (BitBlt, no capture API, no compositor), blur it on the CPU and keep the
// result as a bitmap. It is refreshed only when the window moves/resizes and
// every refreshMs, never per frame - that is what made GlassBoard's LiveBlur
// burn the GPU.
static HBITMAP g_bakeBmp = nullptr;
static void* g_bakeBits = nullptr;
static int g_bakeW = 0, g_bakeH = 0;
static DWORD g_bakeTick = 0;

static void FreeBake() {
    if (g_bakeBmp) { DeleteObject(g_bakeBmp); g_bakeBmp = nullptr; }
    g_bakeBits = nullptr;
    g_bakeW = g_bakeH = 0;
}

static void BlurBake(int radius) {
    if (!g_bakeBits || radius <= 0) return;
    int w = g_bakeW, h = g_bakeH;
    auto* px = (uint32_t*)g_bakeBits;
    std::vector<uint32_t> tmp((size_t)w * h);
    for (int pass = 0; pass < 2; pass++) {
        for (int y = 0; y < h; y++) {           // horizontal
            for (int x = 0; x < w; x++) {
                uint32_t r = 0, g = 0, b = 0, n = 0;
                for (int k = -radius; k <= radius; k++) {
                    int sx = x + k;
                    if (sx < 0 || sx >= w) continue;
                    uint32_t v = px[(size_t)y * w + sx];
                    r += v & 0xFF; g += (v >> 8) & 0xFF; b += (v >> 16) & 0xFF; n++;
                }
                tmp[(size_t)y * w + x] = (r / n) | ((g / n) << 8) | ((b / n) << 16) | 0xFF000000;
            }
        }
        for (int y = 0; y < h; y++) {           // vertical
            for (int x = 0; x < w; x++) {
                uint32_t r = 0, g = 0, b = 0, n = 0;
                for (int k = -radius; k <= radius; k++) {
                    int sy = y + k;
                    if (sy < 0 || sy >= h) continue;
                    uint32_t v = tmp[(size_t)sy * w + x];
                    r += v & 0xFF; g += (v >> 8) & 0xFF; b += (v >> 16) & 0xFF; n++;
                }
                px[(size_t)y * w + x] = (r / n) | ((g / n) << 8) | ((b / n) << 16) | 0xFF000000;
            }
        }
    }
}

static void CaptureBackdrop() {
    if (!g_hwnd) return;
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    int w = rc.right, h = rc.bottom;
    if (w <= 0 || h <= 0) return;

    if (w != g_bakeW || h != g_bakeH || !g_bakeBmp) {
        FreeBake();
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        HDC screen = GetDC(nullptr);
        g_bakeBmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &g_bakeBits, nullptr, 0);
        ReleaseDC(nullptr, screen);
        g_bakeW = w;
        g_bakeH = h;
    }
    if (!g_bakeBmp) return;

    POINT origin{0, 0};
    ClientToScreen(g_hwnd, &origin);
    HDC screen = GetDC(nullptr);
    HDC mdc = CreateCompatibleDC(screen);
    HGDIOBJ old = SelectObject(mdc, g_bakeBmp);
    BitBlt(mdc, 0, 0, w, h, screen, origin.x, origin.y, SRCCOPY | CAPTUREBLT);
    SelectObject(mdc, old);
    DeleteDC(mdc);
    ReleaseDC(nullptr, screen);

    BlurBake(g_cfg.blurRadius);
    g_bakeTick = GetTickCount();
}

static void PaintAndPresent() {""",
    "bake")

# ---- 3. config: material + blur radius ----------------------------------
rep("""    int material = 2;            // 0 solid, 1 blur, 2 acrylic
    DWORD tint = 0x99101010;     // AARRGGBB for blur/acrylic""",
    """    int material = 1;            // 0 solid, 1 glass (baked blur)
    int blurRadius = 8;
    int bakeRefreshMs = 900;
    DWORD tint = 0x99101010;""",
    "cfg material")

rep("""    g_cfg.material = GetInt(L"dock", L"material", 2);
    if (g_cfg.material < 0 || g_cfg.material > 2) g_cfg.material = 2;""",
    """    g_cfg.material = GetInt(L"dock", L"material", 1);
    if (g_cfg.material < 0 || g_cfg.material > 1) g_cfg.material = 1;
    g_cfg.blurRadius = GetInt(L"dock", L"blurRadius", 8);
    if (g_cfg.blurRadius < 0) g_cfg.blurRadius = 0;
    if (g_cfg.blurRadius > 32) g_cfg.blurRadius = 32;
    g_cfg.bakeRefreshMs = GetInt(L"dock", L"bakeRefreshMs", 900);
    if (g_cfg.bakeRefreshMs < 0) g_cfg.bakeRefreshMs = 0;""",
    "cfg load")

rep("""    WritePrivateProfileStringW(L"dock", L"material", L"2", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"tint", L"#99101010", g_iniPath.c_str());""",
    """    WritePrivateProfileStringW(L"dock", L"material", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"blurRadius", L"8", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"bakeRefreshMs", L"900", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"tint", L"#99101010", g_iniPath.c_str());""",
    "cfg default")

io.open(p, "w", encoding="utf-8").write(s)
print("bake pipeline added")
