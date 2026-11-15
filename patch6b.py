import io

p = r"C:\Users\20979\RP_Projects\fly_bar\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

def rep(a, b, label):
    global s
    if a not in s:
        raise SystemExit("MISSING: " + label)
    s = s.replace(a, b, 1)

rep("#include <commoncontrols.h>",
    "#include <commoncontrols.h>\n#include <shobjidl.h>", "includes")

rep("""struct Item {
    std::vector<uint32_t> px;    // pre-scaled premultiplied ARGB at cachedPx
    int cachedPx = 0;""",
    """struct Item {
    std::vector<uint32_t> px;    // pre-scaled premultiplied ARGB at cachedPx
    int cachedPx = 0;
    std::wstring iconPath;       // file the shell should render the icon from""",
    "item field")

rep("""static void RenderIconCache(int px) {""",
    """// The shell renders the icon at exactly the requested size; that is the path
// launchers like Nexus use, and it stays sharp at any size.
static HBITMAP ShellImageForPath(const std::wstring& path, int px) {
    if (path.empty() || px <= 0) return nullptr;
    IShellItemImageFactory* factory = nullptr;
    if (FAILED(SHCreateItemFromParsingName(path.c_str(), nullptr, IID_PPV_ARGS(&factory))) || !factory)
        return nullptr;
    SIZE size{px, px};
    HBITMAP bmp = nullptr;
    HRESULT hr = factory->GetImage(size, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK, &bmp);
    factory->Release();
    if (FAILED(hr) || !bmp) return nullptr;
    return bmp;
}

static void RenderIconCache(int px) {""",
    "shell factory")

rep("""        if (!it.icon) continue;
        ICONINFO ii{};""",
    """        if (!it.iconPath.empty()) {
            HBITMAP shellBmp = ShellImageForPath(it.iconPath, px);
            if (shellBmp) {
                BITMAPINFO bi{};
                bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                bi.bmiHeader.biWidth = px;
                bi.bmiHeader.biHeight = -px;
                bi.bmiHeader.biPlanes = 1;
                bi.bmiHeader.biBitCount = 32;
                bi.bmiHeader.biCompression = BI_RGB;
                it.px.assign((size_t)px * px, 0);
                HDC dc = GetDC(nullptr);
                GetDIBits(dc, shellBmp, 0, px, it.px.data(), &bi, DIB_RGB_COLORS);
                ReleaseDC(nullptr, dc);
                DeleteObject(shellBmp);
                it.cachedPx = px;
                continue;
            }
        }
        if (!it.icon) continue;
        ICONINFO ii{};""",
    "render use")

rep("""    it.exePath = LnkTarget(path);
    it.icon = PinIcon(path, it.exePath);""",
    """    it.exePath = LnkTarget(path);
    it.iconPath = it.exePath.empty() ? path : it.exePath;
    it.icon = PinIcon(path, it.exePath);""",
    "pin path")

rep("""    g_items.swap(ordered);""",
    """    g_items.swap(ordered);
    for (auto& it : g_items) {
        if (it.iconPath.empty() && it.hwnd) it.iconPath = WindowExe(it.hwnd);
    }""",
    "window path")

io.open(p, "w", encoding="utf-8").write(s)
print("patched")
