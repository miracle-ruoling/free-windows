import io

p = r"C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()


def rep(a, b, label=""):
    global s
    if a not in s:
        raise SystemExit("MISSING: " + (label or a[:60]))
    s = s.replace(a, b, 1)


# ---- config switch ----------------------------------------------------
rep("""    int allowResize = 1;         // drag the edges to resize""",
    """    int allowResize = 1;         // drag the edges to resize
    int upscaleSmallIcons = 1;   // blow up icons whose artwork is smaller""",
    "config field")

rep("""    g_cfg.allowResize = GetInt(L"dock", L"allowResize", 1);""",
    """    g_cfg.allowResize = GetInt(L"dock", L"allowResize", 1);
    g_cfg.upscaleSmallIcons = GetInt(L"dock", L"upscaleSmallIcons", 1);""",
    "config load")

rep("""    WritePrivateProfileStringW(L"dock", L"allowResize", L"1", g_iniPath.c_str());""",
    """    WritePrivateProfileStringW(L"dock", L"allowResize", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"upscaleSmallIcons", L"1", g_iniPath.c_str());""",
    "config default")

# ---- real frame sizes from the exe's RT_GROUP_ICON --------------------
rep("""static HBITMAP ShellImageForPath(const std::wstring& path, int px) {""",
    """// Largest frame that really exists in the file's icon resources. 0 = unknown
// (store apps, .lnk without a target, ...).
static int MaxRealIconFrame(const std::wstring& path) {
    static std::unordered_map<std::wstring, int> cache;
    auto hit = cache.find(path);
    if (hit != cache.end()) return hit->second;

    int best = 0;
    HMODULE mod = LoadLibraryExW(path.c_str(), nullptr,
                                 LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
    if (mod) {
        EnumResourceNamesW(mod, MAKEINTRESOURCEW(14) /*RT_GROUP_ICON*/,  // NOLINT
                           [](HMODULE m, LPCWSTR, LPWSTR name, LONG_PTR lp) -> BOOL {
                               HRSRC res = FindResourceW(m, name, MAKEINTRESOURCEW(14));
                               if (!res) return TRUE;
                               HGLOBAL glob = LoadResource(m, res);
                               if (!glob) return TRUE;
                               const BYTE* data = (const BYTE*)LockResource(glob);
                               DWORD size = SizeofResource(m, res);
                               if (!data || size < 6) return TRUE;
                               int count = data[4] | (data[5] << 8);
                               auto* out = reinterpret_cast<int*>(lp);
                               for (int i = 0; i < count; i++) {
                                   int off = 6 + i * 14;
                                   if (off + 2 > (int)size) break;
                                   int w = data[off];
                                   int h = data[off + 1];
                                   int side = w > h ? w : h;
                                   if (side == 0) side = 256;   // 0 means 256
                                   if (side > *out) *out = side;
                               }
                               return TRUE;
                           },
                           (LONG_PTR)&best);
        FreeLibrary(mod);
    }
    cache[path] = best;
    return best;
}

static HBITMAP ShellImageForPath(const std::wstring& path, int px) {""",
    "real frames")

# ---- back to a 256 source + our own filter, and honour the real size ---
rep("""            // ask for exactly the size we are going to draw: one resample by the
            // shell instead of "render at 256 then scale again"
            HBITMAP shellBmp = ShellImageForPath(it.iconPath, px);""",
    """            int real = MaxRealIconFrame(it.iconPath);
            int want = px;
            if (real > 0 && real < px) want = real;    // never ask for more than exists
            HBITMAP shellBmp = ShellImageForPath(it.iconPath, want);""",
    "request size")

io.open(p, "w", encoding="utf-8").write(s)
print("patched")
