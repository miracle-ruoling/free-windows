import io

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()


def rep(a, b):
    global s
    assert a in s, "MISSING " + a[:60]
    s = s.replace(a, b, 1)


rep("""struct Item {
    bool isPin = false;""",
    """struct Item {
    std::vector<uint32_t> px;    // pre-scaled premultiplied ARGB at cachedPx
    int cachedPx = 0;
    bool isPin = false;""")

helpers = """static int g_cachedIconPx = 0;

static void BlendPremul(int x0, int y0, int w, int h, const uint32_t* src) {
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint32_t sp = src[(size_t)y * w + x];
            int a = (sp >> 24) & 0xFF;
            if (!a) continue;
            int dx = x0 + x, dy = y0 + y;
            if (dx < 0 || dy < 0 || dx >= g_dibW || dy >= g_dibH) continue;
            BYTE* dst = (BYTE*)g_bits + ((size_t)dy * g_dibW + dx) * 4;
            int sb = sp & 0xFF, sg = (sp >> 8) & 0xFF, sr = (sp >> 16) & 0xFF;
            dst[0] = (BYTE)(sb + dst[0] * (255 - a) / 255);
            dst[1] = (BYTE)(sg + dst[1] * (255 - a) / 255);
            dst[2] = (BYTE)(sr + dst[2] * (255 - a) / 255);
            dst[3] = (BYTE)(a + dst[3] * (255 - a) / 255);
        }
    }
}

// Downscale the shell's 256px artwork with a box filter once per size and cache
// it. Drawing that bitmap directly is what keeps big icons as sharp as desktop
// icons instead of the soft result of DrawIconEx's stretching.
static void RenderIconCache(int px) {
    if (px <= 0 || px == g_cachedIconPx) return;
    g_cachedIconPx = px;

    for (auto& it : g_items) {
        it.px.clear();
        it.cachedPx = 0;
        if (!it.icon) continue;
        ICONINFO ii{};
        if (!GetIconInfo(it.icon, &ii)) continue;
        BITMAP bm{};
        GetObject(ii.hbmColor, sizeof(bm), &bm);
        int sw = bm.bmWidth, sh = bm.bmHeight;
        if (sw <= 0 || sh <= 0) {
            if (ii.hbmColor) DeleteObject(ii.hbmColor);
            if (ii.hbmMask) DeleteObject(ii.hbmMask);
            continue;
        }
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = sw;
        bi.bmiHeader.biHeight = -sh;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        std::vector<uint32_t> src((size_t)sw * sh);
        HDC dc = GetDC(nullptr);
        GetDIBits(dc, ii.hbmColor, 0, sh, src.data(), &bi, DIB_RGB_COLORS);
        ReleaseDC(nullptr, dc);
        if (ii.hbmColor) DeleteObject(ii.hbmColor);
        if (ii.hbmMask) DeleteObject(ii.hbmMask);

        it.px.assign((size_t)px * px, 0);
        it.cachedPx = px;
        for (int y = 0; y < px; y++) {
            int sy0 = y * sh / px, sy1 = (y + 1) * sh / px;
            if (sy1 <= sy0) sy1 = sy0 + 1;
            for (int x = 0; x < px; x++) {
                int sx0 = x * sw / px, sx1 = (x + 1) * sw / px;
                if (sx1 <= sx0) sx1 = sx0 + 1;
                uint32_t r = 0, g = 0, b = 0, a = 0;
                int n = 0;
                for (int sy = sy0; sy < sy1 && sy < sh; sy++) {
                    for (int sx = sx0; sx < sx1 && sx < sw; sx++) {
                        uint32_t v = src[(size_t)sy * sw + sx];
                        uint32_t sa = (v >> 24) & 0xFF;
                        r += ((v >> 16) & 0xFF) * sa / 255;
                        g += ((v >> 8) & 0xFF) * sa / 255;
                        b += (v & 0xFF) * sa / 255;
                        a += sa;
                        n++;
                    }
                }
                if (!n) continue;
                it.px[(size_t)y * px + x] =
                    ((a / n) << 24) | ((r / n) << 16) | ((g / n) << 8) | (b / n);
            }
        }
    }
}

static void Present() {"""
rep("static void Present() {", helpers)

rep("""        Item& it = g_items[s.item];
        if (it.icon) {
            // draw 1:1 and centre it: resampling is what made it look soft
            int cx = (s.rc.left + s.rc.right) / 2 - g_iconBucket / 2;
            int cy = (s.rc.top + s.rc.bottom) / 2 - g_iconBucket / 2;
            DrawIconEx(g_memDC, cx, cy, it.icon, g_iconBucket, g_iconBucket, 0, nullptr, DI_NORMAL);
        }""",
    """        Item& it = g_items[s.item];
        int icx = (s.rc.left + s.rc.right) / 2 - g_iconPx / 2;
        int icy = (s.rc.top + s.rc.bottom) / 2 - g_iconPx / 2;
        if (!it.px.empty() && it.cachedPx == g_iconPx) {
            BlendPremul(icx, icy, g_iconPx, g_iconPx, it.px.data());
        } else if (it.icon) {
            DrawIconEx(g_memDC, icx, icy, it.icon, g_iconPx, g_iconPx, 0, nullptr, DI_NORMAL);
        }""")

rep("""    // never up/downscale the shell bitmap: pick the largest one that fits the cell
    int bucket = 16;
    if (icon >= 256) bucket = 256;
    else if (icon >= 48) bucket = 48;
    else if (icon >= 32) bucket = 32;
    else bucket = 16;
    if (bucket != g_iconBucket) {
        g_iconBucket = bucket;
        BuildItems();          // re-fetch icons at the new size
        g_slots.clear();
        return ComputeButtons();
    }""",
    """    g_iconBucket = 256;        // always cache from the 256px artwork
    RenderIconCache(icon);""")

rep("""static int EdgeAt(POINT p, const RECT& rc) {
    if (!g_cfg.allowResize) return 0;
    const int b = 6;
    int e = 0;
    if (p.x < b) e |= 1;
    if (p.x >= rc.right - b) e |= 2;
    if (p.y < b) e |= 4;
    if (p.y >= rc.bottom - b) e |= 8;
    return e;
}""",
    """static int EdgeAt(POINT p, const RECT& rc) {
    if (!g_cfg.allowResize) return 0;
    const int b = 6;     // edge band
    const int c = 16;    // corner square: much easier to hit than 6x6
    bool left = p.x < b, right = p.x >= rc.right - b;
    bool top = p.y < b, bottom = p.y >= rc.bottom - b;
    if (p.x < c && p.y < c) return 1 | 4;
    if (p.x >= rc.right - c && p.y < c) return 2 | 4;
    if (p.x < c && p.y >= rc.bottom - c) return 1 | 8;
    if (p.x >= rc.right - c && p.y >= rc.bottom - c) return 2 | 8;
    int e = 0;
    if (left) e |= 1;
    if (right) e |= 2;
    if (top) e |= 4;
    if (bottom) e |= 8;
    return e;
}""")

rep("""static bool g_pressActive = false;
static int g_pressSlot = -1;""",
    """static bool g_pressActive = false;
static int g_pressSlot = -1;
static HWND g_pressHwnd = nullptr;
static std::wstring g_pressLnk;""")

rep("""            g_pressSlot = hit;
            g_pressPos = pt;""",
    """            g_pressSlot = hit;
            g_pressHwnd = nullptr;
            g_pressLnk.clear();
            if (hit >= 0 && hit < (int)g_slots.size() && g_slots[hit].item >= 0 &&
                g_slots[hit].item < (int)g_items.size()) {
                g_pressHwnd = g_items[g_slots[hit].item].hwnd;
                g_pressLnk = g_items[g_slots[hit].item].lnkPath;
            }
            g_pressPos = pt;""")

rep("""                DLog(L"click slot=%d slots=%d", g_pressSlot, (int)g_slots.size());
                if (g_pressSlot >= 0 && g_pressSlot < (int)g_slots.size()) {
                    if (g_slots[g_pressSlot].item < 0) ToggleExpand();
                    else ClickItem(g_slots[g_pressSlot].item);
                }""",
    """                DLog(L"click slot=%d hwnd=%p lnk=%s", g_pressSlot, (void*)g_pressHwnd,
                     g_pressLnk.c_str());
                if (g_pressSlot >= 0 && g_pressSlot < (int)g_slots.size() &&
                    g_slots[g_pressSlot].item < 0) {
                    ToggleExpand();
                } else if (g_pressHwnd && IsWindow(g_pressHwnd)) {
                    ActivateWindow(g_pressHwnd);
                } else if (!g_pressLnk.empty()) {
                    LaunchShortcut(g_pressLnk, g_pressSlot);
                }""")

io.open(p, "w", encoding="utf-8").write(s)
print("patched")
