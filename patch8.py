import io

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()


def rep(a, b, label=""):
    global s
    if a not in s:
        raise SystemExit("MISSING: " + (label or a[:60]))
    s = s.replace(a, b, 1)


# ---------- config ----------
rep("""    int upscaleSmallIcons = 1;   // blow up icons whose artwork is smaller""",
    """    int upscaleSmallIcons = 1;   // blow up icons whose artwork is smaller
    int material = 2;            // 0 solid, 1 blur, 2 acrylic
    DWORD tint = 0x99101010;     // AARRGGBB for blur/acrylic""",
    "config fields")

rep("""    g_cfg.upscaleSmallIcons = GetInt(L"dock", L"upscaleSmallIcons", 1);""",
    """    g_cfg.upscaleSmallIcons = GetInt(L"dock", L"upscaleSmallIcons", 1);
    g_cfg.material = GetInt(L"dock", L"material", 2);
    if (g_cfg.material < 0 || g_cfg.material > 2) g_cfg.material = 2;
    GetPrivateProfileStringW(L"dock", L"tint", L"#99101010", buf, 1024, g_iniPath.c_str());
    {
        std::wstring t = buf;
        Trim(t);
        if (!t.empty() && t[0] == L'#') t.erase(0, 1);
        g_cfg.tint = (DWORD)wcstoul(t.c_str(), nullptr, 16);
        if (t.size() <= 6) g_cfg.tint |= 0xFF000000;
    }""",
    "config load")

rep("""    WritePrivateProfileStringW(L"dock", L"upscaleSmallIcons", L"1", g_iniPath.c_str());""",
    """    WritePrivateProfileStringW(L"dock", L"upscaleSmallIcons", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"material", L"2", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"tint", L"#99101010", g_iniPath.c_str());""",
    "config default")

# ---------- acrylic background window ----------
rep("""static void PaintAndPresent() {""",
    """// Acrylic/blur needs a normal (non-layered) window, and our icon layer must stay
// layered for the fade, so the background is a separate topmost window that is
// kept exactly under the icon layer. It is click-through: all input goes to the
// icon window above it.
static HWND g_bgWnd = nullptr;

enum ACCENT_STATE {
    ACCENT_DISABLED = 0,
    ACCENT_ENABLE_GRADIENT = 1,
    ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
    ACCENT_ENABLE_BLURBEHIND = 3,
    ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
};
struct ACCENTPOLICY {
    int nAccentState;
    int nFlags;
    DWORD nColor;
    int nAnimationId;
};
struct WINCOMPATTRDATA {
    int nAttribute;
    PVOID pData;
    ULONG ulDataSize;
};
enum { WCA_ACCENT_POLICY = 19 };

static void ApplyAccent(HWND hwnd, int state, DWORD color) {
    static auto setAttr = (BOOL(WINAPI*)(HWND, const WINCOMPATTRDATA*))GetProcAddress(
        GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute");
    if (!setAttr) return;
    ACCENTPOLICY policy{state, state == ACCENT_ENABLE_TRANSPARENTGRADIENT ? 0x13 : 0, color, 0};
    WINCOMPATTRDATA data{WCA_ACCENT_POLICY, &policy, sizeof(policy)};
    setAttr(hwnd, &data);
}

static void SyncBackground() {
    if (!g_hwnd) return;
    RECT wr{};
    GetWindowRect(g_hwnd, &wr);

    if (!g_bgWnd) {
        g_bgWnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                                      WS_EX_TRANSPARENT,
                                  L"STATIC", L"", WS_POPUP, wr.left, wr.top,
                                  wr.right - wr.left, wr.bottom - wr.top, nullptr, nullptr,
                                  GetModuleHandleW(nullptr), nullptr);
    }
    if (!g_bgWnd) return;

    bool want = g_cfg.material > 0 && g_alpha > 0;
    if (!want) {
        ShowWindow(g_bgWnd, SW_HIDE);
        return;
    }

    SetWindowPos(g_bgWnd, HWND_TOPMOST, wr.left, wr.top, wr.right - wr.left,
                 wr.bottom - wr.top, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // rounded corners
    HRGN rgn = CreateRoundRectRgn(0, 0, wr.right - wr.left + 1, wr.bottom - wr.top + 1,
                                  g_cfg.radius * 2, g_cfg.radius * 2);
    SetWindowRgn(g_bgWnd, rgn, TRUE);
    // fade: the tint alpha follows the strip opacity
    DWORD alpha = (g_cfg.tint >> 24) & 0xFF;
    DWORD tint = (g_cfg.tint & 0x00FFFFFF) | (((DWORD)alpha * g_alpha / 255) << 24);
    ApplyAccent(g_bgWnd, g_cfg.material == 2 ? ACCENT_ENABLE_ACRYLICBLURBEHIND
                                             : ACCENT_ENABLE_BLURBEHIND,
                tint);
    // keep the icon layer above the background
    SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

static void PaintAndPresent() {""",
    "bg window")

# keep them in sync
rep("""static void PaintAndPresent() {
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    ComputeButtons();
    Paint(rc.right, rc.bottom);
    Present();
}""",
    """static void PaintAndPresent() {
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    ComputeButtons();
    Paint(rc.right, rc.bottom);
    Present();
    SyncBackground();
}""",
    "sync in paint")

rep("""    if (wantThrough) ThumbHide();          // invisible dock: no preview either""",
    """    if (wantThrough) ThumbHide();          // invisible dock: no preview either
    SyncBackground();""",
    "sync on fade")

io.open(p, "w", encoding="utf-8").write(s)
print("acrylic background added")
