import io, re

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

start = s.index("// Glass background without the GPU cost")
end = s.index("static void PaintAndPresent() {")
new = r'''// Glass backdrop, following what GlassBoard does:
//  * capture the window *underneath* with PrintWindow (never hide ourselves,
//    so there is nothing to flicker), cached for 160 ms
//  * downscale to 1/4, box-blur twice with a radius capped at 64 (cheap), then
//    upscale into the draw buffer
static HBITMAP g_bakeBmp;
static bool g_bakeDirty = true;
static void* g_bakeBits;
static int g_bakeW, g_bakeH;
static DWORD g_bakeTick;

static void FreeBake() {
    if (g_bakeBmp) { DeleteObject(g_bakeBmp); g_bakeBmp = nullptr; }
    g_bakeBits = nullptr;
    g_bakeW = g_bakeH = 0;
}

static void BoxBlurSmall(std::vector<uint32_t>& v, int w, int h, int radius) {
    if (radius <= 0 || w <= 0 || h <= 0) return;
    std::vector<uint32_t> tmp((size_t)w * h);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint32_t r = 0, g = 0, b = 0, n = 0;
            for (int k = -radius; k <= radius; k++) {
                int sx = x + k;
                if (sx < 0) sx = 0;
                if (sx >= w) sx = w - 1;
                uint32_t c = v[(size_t)y * w + sx];
                b += c & 0xFF; g += (c >> 8) & 0xFF; r += (c >> 16) & 0xFF; n++;
            }
            tmp[(size_t)y * w + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n) | 0xFF000000;
        }
    }
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint32_t r = 0, g = 0, b = 0, n = 0;
            for (int k = -radius; k <= radius; k++) {
                int sy = y + k;
                if (sy < 0) sy = 0;
                if (sy >= h) sy = h - 1;
                uint32_t c = tmp[(size_t)sy * w + x];
                b += c & 0xFF; g += (c >> 8) & 0xFF; r += (c >> 16) & 0xFF; n++;
            }
            v[(size_t)y * w + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n) | 0xFF000000;
        }
    }
}

static HWND WindowUnderUs(const RECT& wr) {
    // the top-level window our strip sits on top of
    POINT c{(wr.left + wr.right) / 2, (wr.top + wr.bottom) / 2};
    HWND h = WindowFromPoint(c);
    if (!h) return nullptr;
    HWND root = GetAncestor(h, GA_ROOT);
    if (!root) root = h;
    if (root == g_hwnd) return nullptr;
    return root;
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
    if (!g_bakeBmp || !g_bakeBits) return;

    RECT wr{};
    GetWindowRect(g_hwnd, &wr);

    // grab our rect out of whatever we are covering
    std::vector<uint32_t> full((size_t)w * h, 0xFF202020);
    HWND under = WindowUnderUs(wr);
    bool got = false;
    if (under) {
        RECT ur{};
        if (GetWindowRect(under, &ur)) {
            int uw = ur.right - ur.left, uh = ur.bottom - ur.top;
            if (uw > 0 && uh > 0 && uw < 8000 && uh < 8000) {
                BITMAPINFO bi{};
                bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                bi.bmiHeader.biWidth = uw;
                bi.bmiHeader.biHeight = -uh;
                bi.bmiHeader.biPlanes = 1;
                bi.bmiHeader.biBitCount = 32;
                bi.bmiHeader.biCompression = BI_RGB;
                void* bits = nullptr;
                HDC screen = GetDC(nullptr);
                HDC mdc = CreateCompatibleDC(screen);
                HBITMAP bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
                HGDIOBJ old = SelectObject(mdc, bmp);
                if (PrintWindow(under, mdc, 2 /*PW_RENDERFULLCONTENT*/) && bits) {
                    auto* src = (uint32_t*)bits;
                    for (int y = 0; y < h; y++) {
                        int sy = (wr.top - ur.left * 0) + y - ur.top;
                        if (sy < 0 || sy >= uh) continue;
                        for (int x = 0; x < w; x++) {
                            int sx = x + (wr.left - ur.left);
                            if (sx < 0 || sx >= uw) continue;
                            full[(size_t)y * w + x] = src[(size_t)sy * uw + sx] | 0xFF000000;
                        }
                    }
                    got = true;
                }
                SelectObject(mdc, old);
                DeleteObject(bmp);
                DeleteDC(mdc);
                ReleaseDC(nullptr, screen);
            }
        }
    }
    if (!got) {
        // fallback: plain screen grab (may include ourselves; better than nothing)
        POINT origin{0, 0};
        ClientToScreen(g_hwnd, &origin);
        HDC screen = GetDC(nullptr);
        HDC mdc = CreateCompatibleDC(screen);
        HGDIOBJ old = SelectObject(mdc, g_bakeBmp);
        BitBlt(mdc, 0, 0, w, h, screen, origin.x, origin.y, SRCCOPY);
        SelectObject(mdc, old);
        DeleteDC(mdc);
        ReleaseDC(nullptr, screen);
        g_bakeTick = GetTickCount();
        return;
    }

    // 1/4 resolution blur (cost drops 16x), radius capped at 64 like GlassBoard
    int sw = (w + 3) / 4, sh = (h + 3) / 4;
    std::vector<uint32_t> small((size_t)sw * sh, 0xFF202020);
    for (int y = 0; y < sh; y++) {
        for (int x = 0; x < sw; x++) {
            uint32_t r = 0, g = 0, b = 0, n = 0;
            for (int yy = 0; yy < 4; yy++) {
                int sy = y * 4 + yy;
                if (sy >= h) break;
                for (int xx = 0; xx < 4; xx++) {
                    int sx = x * 4 + xx;
                    if (sx >= w) break;
                    uint32_t c = full[(size_t)sy * w + sx];
                    b += c & 0xFF; g += (c >> 8) & 0xFF; r += (c >> 16) & 0xFF; n++;
                }
            }
            if (n) small[(size_t)y * sw + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n) | 0xFF000000;
        }
    }

    int rWide = g_cfg.blurRadius;
    if (rWide > 64) rWide = 64;
    if (rWide > 0) {
        BoxBlurSmall(small, sw, sh, rWide);
        BoxBlurSmall(small, sw, sh, rWide);          // twice ~= gaussian
        int rFine = rWide / 3;
        if (rFine > 0) BoxBlurSmall(small, sw, sh, rFine);
    }

    // upscale back into the draw buffer (bilinear-ish)
    auto* dst = (uint32_t*)g_bakeBits;
    for (int y = 0; y < h; y++) {
        int sy0 = y * sh / h;
        if (sy0 >= sh) sy0 = sh - 1;
        for (int x = 0; x < w; x++) {
            int sx0 = x * sw / w;
            if (sx0 >= sw) sx0 = sw - 1;
            dst[(size_t)y * w + x] = small[(size_t)sy0 * sw + sx0] | 0xFF000000;
        }
    }
    g_bakeTick = GetTickCount();
}

'''
s = s[:start] + new + s[end:]

# radius range: 0..64 now (it is applied in 1/4 space)
s = s.replace("    if (g_cfg.blurRadius > 300) g_cfg.blurRadius = 300;",
              "    if (g_cfg.blurRadius > 64) g_cfg.blurRadius = 64;", 1)
s = s.replace('{L"blurRadius", L"背景模糊半径", 0, 300, 0, 0},',
              '{L"blurRadius", L"背景模糊半径 (1/4 采样)", 0, 64, 0, 0},', 1)

io.open(p, "w", encoding="utf-8").write(s)
print("printwindow capture + quarter-res blur")
