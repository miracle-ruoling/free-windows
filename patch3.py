import io, sys

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

def rep(old, new, count=1):
    global s
    if old not in s:
        print("MISSING:", old[:80].replace("\n", "\\n"))
        sys.exit(1)
    s = s.replace(old, new, count)

# ---------- high resolution icons ----------
rep("#include <dwmapi.h>", "#include <dwmapi.h>\n#include <commoncontrols.h>")

rep("""static HICON LoadIconFromPath(const std::wstring& path) {""",
"""static IImageList* g_jumboIcons = nullptr;

// 256x256 shell icon: drawing that down to 30-70px stays crisp at any dock size.
static HICON HiResIconForPath(const std::wstring& path) {
    if (path.empty()) return nullptr;
    SHFILEINFOW sfi{};
    if (!SHGetFileInfoW(path.c_str(), 0, &sfi, sizeof(sfi), SHGFI_SYSICONINDEX)) return nullptr;
    if (!g_jumboIcons) {
        void* pv = nullptr;
        if (FAILED(SHGetImageList(SHIL_JUMBO, IID_IImageList, &pv))) return nullptr;
        g_jumboIcons = static_cast<IImageList*>(pv);
    }
    HICON icon = nullptr;
    if (SUCCEEDED(g_jumboIcons->GetIcon(sfi.iIcon, ILD_TRANSPARENT, &icon)) && icon) return icon;
    return nullptr;
}

static HICON LoadIconFromPath(const std::wstring& path) {
    if (HICON hi = HiResIconForPath(path)) return hi;""")

rep("""static HICON IconForWindow(HWND h) {
    HICON src = (HICON)SendMessageTimeoutW(h, WM_GETICON, ICON_BIG, 0, SMTO_ABORTIFHUNG, 100, nullptr);""",
"""static HICON IconForWindow(HWND h) {
    {
        DWORD pid0 = 0;
        GetWindowThreadProcessId(h, &pid0);
        wchar_t p0[MAX_PATH]{};
        HANDLE h0 = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid0);
        if (h0) {
            DWORD sz0 = MAX_PATH;
            QueryFullProcessImageNameW(h0, 0, p0, &sz0);
            CloseHandle(h0);
        }
        if (HICON hi = HiResIconForPath(p0)) return hi;
    }
    HICON src = (HICON)SendMessageTimeoutW(h, WM_GETICON, ICON_BIG, 0, SMTO_ABORTIFHUNG, 100, nullptr);""")

# ---------- expand toggle + resize + wheel ----------
rep("""static LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {""",
"""static void PaintAndPresent() {
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    ComputeButtons();
    Paint(rc.right, rc.bottom);
    Present();
}

// "Expand": grow the window along its long axis until everything fits (limited
// to the monitor work area). Click again to go back to the previous size.
static void ToggleExpand() {
    RECT wr{};
    GetWindowRect(g_hwnd, &wr);
    if (!g_expanded) {
        int W = wr.right - wr.left, H = wr.bottom - wr.top;
        bool vertical = (H > W);
        int pad = g_cfg.pad, gap = g_cfg.gap;
        int shortSide = vertical ? W : H;
        int icon = shortSide - pad * 2;
        if (icon < g_cfg.minIcon) icon = g_cfg.minIcon;
        if (icon > g_cfg.maxIcon) icon = g_cfg.maxIcon;
        int cell = icon + gap;
        int need = pad * 2 + (int)g_items.size() * cell - gap;
        int newW = W, newH = H;
        if (vertical) newH = need; else newW = need;

        HMONITOR mon = MonitorFromWindow(g_hwnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi{sizeof(mi)};
        if (GetMonitorInfoW(mon, &mi)) {
            int maxW = mi.rcWork.right - mi.rcWork.left;
            int maxH = mi.rcWork.bottom - mi.rcWork.top;
            if (newW > maxW) newW = maxW;
            if (newH > maxH) newH = maxH;
        }
        g_collapsedRect = wr;
        SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, newW, newH, SWP_NOMOVE | SWP_NOACTIVATE);
        g_expanded = true;
        DLog(L"expand to %dx%d", newW, newH);
    } else {
        SetWindowPos(g_hwnd, HWND_TOPMOST, g_collapsedRect.left, g_collapsedRect.top,
                     g_collapsedRect.right - g_collapsedRect.left,
                     g_collapsedRect.bottom - g_collapsedRect.top, SWP_NOACTIVATE);
        g_expanded = false;
        DLog(L"collapse back");
    }
    PaintAndPresent();
}

static LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {""")

# WM_SIZE
rep("""        case WM_DISPLAYCHANGE:
        case WM_SETTINGCHANGE:""",
"""        case WM_SIZE:
            PaintAndPresent();
            return 0;

        case WM_MOUSEWHEEL: {
            int delta = GET_WHEEL_DELTA_WPARAM(wp);
            int n = (int)g_items.size();
            int per = g_capacity > 1 ? g_capacity - 1 : 1;
            if (n > per) {
                g_scroll -= (delta / WHEEL_DELTA) * g_cfg.scrollStep;
                if (g_scroll < 0) g_scroll = 0;
                if (g_scroll > n - per) g_scroll = n - per;
                if (g_scroll < 0) g_scroll = 0;
                PaintAndPresent();
            }
            return 0;
        }

        case WM_DISPLAYCHANGE:
        case WM_SETTINGCHANGE:""")

# hit test borders for resizing
rep("""        case WM_NCHITTEST:
            return HTCLIENT;""",
"""        case WM_NCHITTEST: {
            if (!g_cfg.allowResize) return HTCLIENT;
            POINT p{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            ScreenToClient(h, &p);
            RECT rc{};
            GetClientRect(h, &rc);
            const int b = 6;
            bool left = p.x < b, right = p.x >= rc.right - b;
            bool top = p.y < b, bottom = p.y >= rc.bottom - b;
            if (top && left) return HTTOPLEFT;
            if (top && right) return HTTOPRIGHT;
            if (bottom && left) return HTBOTTOMLEFT;
            if (bottom && right) return HTBOTTOMRIGHT;
            if (left) return HTLEFT;
            if (right) return HTRIGHT;
            if (top) return HTTOP;
            if (bottom) return HTBOTTOM;
            return HTCLIENT;
        }""")

# save size when the user finishes resizing or moving
rep("""        case WM_LBUTTONUP:""",
"""        case WM_EXITSIZEMOVE:
            SavePosition();
            SaveSize();
            PaintAndPresent();
            return 0;

        case WM_LBUTTONUP:""")

io.open(p, "w", encoding="utf-8").write(s)
print("patched expand/resize/wheel/icons")
