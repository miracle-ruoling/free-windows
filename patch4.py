import io, sys

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

def rep(old, new, count=1):
    global s
    if old not in s:
        print("MISSING:", old[:80].replace("\n", "\\n")); sys.exit(1)
    s = s.replace(old, new, count)

# forward declarations near the top
rep("static void DLog(const wchar_t* fmt, ...);\nstatic void ThumbHide();\nstatic HWND g_thumbWnd;",
    "static void DLog(const wchar_t* fmt, ...);\nstatic void ThumbHide();\nstatic HWND g_thumbWnd;\nstatic HWND g_hwnd;\nstatic HICON HiResIconForPath(const std::wstring& path);")

# fix ThumbShow header
rep("""static void ThumbShow(int index) {
    if (index < 0 || index >= (int)g_items.size() || !g_thumbWnd) {
        DLog(L"thumb: bad index %d or no window", index);
        return;
    }
    Item& it = g_items[index];
    if (!it.hwnd || !IsWindow(it.hwnd)) {
        DLog(L"thumb: skip slot=%d item=%d hwnd=%p", index, itemIndex, (void*)it.hwnd);
        ThumbHide();
        return;
    }
    // Minimized windows still get a preview: DWM shows their last frame.
    DLog(L"thumb: register slot=%d item=%d hwnd=%p", index, itemIndex, (void*)it.hwnd);
    RECT btn = slot.rc;""",
"""static void ThumbShow(int index) {
    if (index < 0 || index >= (int)g_slots.size() || !g_thumbWnd) {
        DLog(L"thumb: bad slot %d", index);
        return;
    }
    const Slot slot = g_slots[index];
    int itemIndex = slot.item;
    if (itemIndex < 0 || itemIndex >= (int)g_items.size()) { ThumbHide(); return; }
    Item& it = g_items[itemIndex];
    if (!it.hwnd || !IsWindow(it.hwnd)) {
        DLog(L"thumb: skip slot=%d item=%d", index, itemIndex);
        ThumbHide();
        return;
    }
    // Minimized windows still get a preview: DWM shows their last frame.
    DLog(L"thumb: register slot=%d item=%d hwnd=%p", index, itemIndex, (void*)it.hwnd);
    RECT btn = slot.rc;""")

# default size helper (used at startup only)
rep("""static void PaintAndPresent() {""",
"""// Default size for a fresh install: one row/column sized by the configured icon.
static void ComputeLayout(int* pw, int* ph) {
    int n = (int)g_items.size();
    if (n < 1) n = 1;
    int cell = g_cfg.iconSize + g_cfg.gap;
    int pad = g_cfg.pad;
    if (pw) *pw = n * cell - g_cfg.gap + pad * 2;
    if (ph) *ph = g_cfg.iconSize + pad * 2;
}

static void PaintAndPresent() {""")

# RefreshItems must not resize the window any more
rep("""static void RefreshItems() {
    BuildItems();
    ComputeButtons();
    int w, h;
    ComputeLayout(&w, &h);
    SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, w, h, SWP_NOMOVE | SWP_NOACTIVATE);
    Paint(w, h);
    Present();
    InvalidateRect(g_hwnd, nullptr, FALSE);
}""",
"""static void RefreshItems() {
    BuildItems();
    ComputeButtons();
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    Paint(rc.right, rc.bottom);
    Present();
    InvalidateRect(g_hwnd, nullptr, FALSE);
}""")

io.open(p, "w", encoding="utf-8").write(s)
print("patched fixes")
