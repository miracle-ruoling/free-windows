// dock.cpp - a small draggable icon strip.
//   * one button per window (minimized windows included), pinned taskbar items
//     are read from the shell's own "User Pinned\TaskBar" folder
//   * click: not running -> launch the pinned shortcut; running -> bring that
//     window to the front (clicking the active window minimizes it)
//   * fades out with the distance between the cursor and the strip, and becomes
//     click-through while invisible
//   * drag the background to move it; position is stored in dock.ini
//
// Ctrl+Alt+Shift+D quits. Right click on the background: reload / quit.

#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <knownfolders.h>
#include <shlwapi.h>
#include <dwmapi.h>
#include <commoncontrols.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propsys.h>
#include <wincodec.h>
#include <uiautomation.h>
#include <tlhelp32.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <wlanapi.h>
#include <wininet.h>
#include <cmath>
#include <string>
#include <vector>
#include <algorithm>
#include <map>
#include <set>
#include <unordered_map>
#include <utility>
#include <cstdio>
#include <cstdarg>
#include <cstdlib>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "comdlg32.lib")     // ChooseColorW (the 色调 palette)
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "propsys.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "oleaut32.lib")
#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "wininet.lib")

static HWND g_hwnd;
static void CompanionSaveAllPositions();      // defined with the companions
static void CompanionFollowTo(int stripX, int stripY);   // ditto; called from Present()
// Page identity (how a page reads/writes and re-applies itself) and the object a menu asks
// for. Pages are chosen by the *components* the object owns, see SettingsBuildPages().
enum SPageKind {
    kPageGlass = 0,       // 玻璃页: [dock], global params shared by every glass window
    kPageFloatDock = 1,   // 浮窗页 of the strip: [dock]
    kPageBar = 2,         // 图标条页: [dock], only things a float window cannot use
    kPageFloatTray = 3,   // 浮窗页 of a companion: [traybar]
    kPageGroupKind = 4,   // 组 N
};
enum SObj { kObjStrip = 0, kObjCompanion = 1, kObjGroup = 2 };
static void ShowSettings(int hintObj = kObjStrip, int hintId = 0);   // per-window pages (G3/H2)
static void* g_paintBits;
static HWND g_setWnd;
static int g_paintW, g_paintH;
static HICON HiResIconForPath(const std::wstring& path);
static void SetPixelPremul(int x, int y, DWORD argb);
static void DLog(const wchar_t* fmt, ...);

// Profiling helper for "why did the pointer hitch?" (see HANDOVER_NEXT.md §3.19). It is only
// used by the "slow: ..." log lines, which fire only when something is unexpectedly slow, so
// the cost of the calls themselves is irrelevant.
static double NowMs() {
    static LONGLONG freq = 0;
    if (!freq) {
        LARGE_INTEGER f;
        QueryPerformanceFrequency(&f);
        freq = f.QuadPart ? f.QuadPart : 1;
    }
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)freq;
}
static bool g_bakeDirty = true;

// ---- H3 (PLAN_COMPONENTS.md §3): one bake pipeline, one target per glass window --------
// A GlassTarget is the padded, already-blurred-and-tinted picture a glass window draws from.
// The strip owns g_stripGlass; any other glass window owns one of its own (Companion::glass).
// Per-window *targets* with a single shared *pipeline* is the whole point of H3: the expensive
// part (read the screen, blur, tint) exists once, only the cheap crop is per window.
struct GlassTarget {
    HBITMAP bmp = nullptr;      // the DIB the pixels live in (owned by this target)
    void* bits = nullptr;       // ... and its 32bpp top-down pixels
    int w = 0, h = 0;           // size of the padded picture
    POINT origin{};             // screen coords of its top-left corner
    bool valid = false;         // bits holds a real capture (not the neutral fill)
    int marginUsed = 0;         // padding that was baked in (see g_bakeMargin)
    DWORD at = 0;               // tick of the last successful bake
    DWORD lastMs = 0;           // cost of that bake, in ms
    bool dirty = true;          // a bake is wanted before it may be read
};

// The blurred bake is captured with this margin around the strip, so a moving strip can
// keep reading the same picture at a shifted offset (see BakeGlass).
static int g_bakeMargin = 256;   // TEMP experiment: fewer re-bakes while dragging
// Margin actually baked into the current picture (GlassTarget::marginUsed). A drag needs the
// padding (it re-crops the same bake instead of re-grabbing); at rest nothing can move the
// strip, so only the strip itself is grabbed - ~45% cheaper per capture.
static GlassTarget g_stripGlass;

static int g_captureCount = 0;         // captures since the last cadence line
static DWORD g_lastBakeMs = 0;         // cost of the most recent bake (any window), ms
// H3 §3.3: a per-frame budget for "start a new capture". Two glass windows both want a
// backdrop every 1/captureHz; without a budget they would both run inside the same tick and
// the frame loop would stall for the sum of them. With it, the second one simply waits for a
// later tick (a glass backdrop is a slow-moving thing - nobody can see 200 vs 216 ms).
static int g_bakeBudgetUsedMs = 0;
// H3: the padding a *moving* float window's bake gets (see CompanionGlassTick).
static const int kCompanionMargin = 128;
// The glass body (everything before the icons) cached as pixels: while only the icons
// are animating there is no reason to recompute 160k pixels of glass per frame.
static std::vector<uint32_t> g_glassCache;
static int g_glassCacheW = 0, g_glassCacheH = 0;
static int g_glassCacheOx = -1, g_glassCacheOy = -1;   // snapshot offset it was drawn for
static bool g_glassCacheValid = false;
static void CaptureBackdrop();
static void CompanionGlassTick(DWORD now);   // H3: the float window bakes its own backdrop
static int g_cachedIconPx;
static HWND g_gridWnd;            // the "^" panel, built further down
static bool g_gridVisible = false;
static bool g_menuOpen = false;   // a forwarded tray menu is on screen
static bool g_popupOpen = false;  // our own TrackPopupMenu is running (modal)
static bool g_rescanPending = false;  // "重新扫描托盘" asked, waiting for apps to answer
static bool g_menuSeen = false;   // ... and we actually saw its window
static DWORD g_menuOpenedAt = 0;
static DWORD g_menuOutsideAt = 0;
static unsigned int g_menuPid = 0;   // process that owns the forwarded menu
static HWND g_menuHwnd = nullptr;   // the popup we are tracking (menus are reused)
// --- "who is allowed to own the foreground while the panel is up" -----------------
// The panel is a NOACTIVATE layered window, so it never holds focus itself. It only
// goes away when the foreground becomes a *third party*: neither us, nor the window
// that had focus when the panel opened, nor an app we just acted for (activated on a
// click, or the app whose tray menu we forwarded).
static HWND g_fgAtGridOpen = nullptr;   // foreground at the moment the panel opened
static DWORD g_fgPidAtGridOpen = 0;     // ... and its process (an app may switch windows)
static DWORD g_friendPid = 0;           // app we just acted for
static DWORD g_focusGraceUntil = 0;     // ignore foreground churn right after our click
static HWND g_menuWatch;                // the app's menu window we are watching (menu code below)
static DWORD g_menuItemPressAt = 0;     // when the user last pressed *on* the menu itself
static void DrawTextAlpha(int x, int y, int w, int h, const std::wstring& text, int px, DWORD rgb);
static void BlendScaled(int x0, int y0, int dw, int dh, const uint32_t* src, int sw, int sh,
                        int clipL = INT_MIN, int clipR = INT_MAX);

// ---------------------------------------------------------------- settings
struct Config {
    int iconSize = 32;
    int gap = 6;
    int pad = 10;
    int radius = 12;
    COLORREF bg = 0;              // 0 = fully transparent background
    BYTE bgAlpha = 0;
    BYTE hoverAlpha = 0x28;       // hover highlight alpha
    int fadeStart = 48;
    int fadeEnd = 144;
    int vertical = 0;
    int clickActiveMinimizes = 1;
    int x = 0;
    int y = 0;
    int hasPos = 0;
    int thumbWidth = 220;
    int thumbHeight = 124;
    int thumbDelay = 400;        // ms before the preview appears
    int minIcon = 18;            // icon size never goes below this
    int maxIcon = 72;            // ... nor above this
    int scrollStep = 1;          // items per wheel notch
    int allowResize = 1;         // drag the edges to resize
    int upscaleSmallIcons = 1;   // blow up icons whose artwork is smaller
    int material = 1;            // 0 solid, 1 glass (baked blur)
    int lightMode = 0;           // 0 dark, 1 light
    // ---- H2 (2026-11-17): the background is a *layer model*, not a single enum ------------
    // bgMode  : what is drawn underneath  0 = the desktop behind the window, 1 = an image
    //           (placeholder, not rendered yet), 2 = a solid colour
    // glassLayer: whether the glass layer runs over that background (blur + tint + rim)
    // `material` above is now *derived* from these two (glass needs "behind" + layer on) and is
    // kept only because the paint path still keys off it.
    int bgMode = 0;
    int glassLayer = 1;
    int color = 0;               // 0 black, 1 white (solid background only)
    int solidOpacity = 235;      // ~92 %: a fully opaque black slab looks nothing like the rest
    int dragNoCapture = 0;       // H3: drag-time backdrop update off => keep the frozen one
    int glassOpacity = 140;      // how much glass there is (0 = invisible)
    int tintStrength = 110;      // how much of the glass is tint vs blur
    int dumpBake = 0;            // diagnostic: write the captured backdrop
    int debugBeacon = 0;         // diagnostic: magenta marker at a fixed client position
    int presentSync = 0;         // 1 = DwmFlush() after each present (see Present())
    int presentOrder = 0;        // 0 = ULW+pptDst, 1 = SetWindowPos then ULW, 2 = ULW then SWP
    int zWatch = 1;              // task 1: keep the dock on top of newly raised topmost windows
    // task 2: double-clicking the strip's empty area hops it to the other side of the monitor's
    // centre line ("dodge"). 0 disables *only* that path - every other double-click meaning
    // (launching an icon, the tray button) is untouched, it is a different branch.
    int dodgeOnDoubleClick = 1;
    // task 3: "snap" = squaring off the two corners of the screen edge the window hugs. It used
    // to be hard-wired into the strip; now every window has it and it can be switched off.
    // [dock] snap rules the strip, a companion has its own [traybar] snap (-1 = inherit).
    int snap = 1;
    int blurIcons = 0;           // 1 = let the icons bleed into the glass
    int blurRadius = 16;          // blur radius in full-resolution pixels
    int refreshHz = 60;           // how often the strip repaints (0..180)
    int captureHz = 5;            // how often the backdrop is re-captured (0..refreshHz)
    // H3 §3.3: how many ms a single frame may spend *starting* captures. The first capture in a
    // frame is always allowed; a second one only if the frame is still under this budget, so
    // N glass windows stretch their refresh rate instead of dropping frames.
    int captureBudgetMs = 8;
    int hoverMs = 160;            // duration of the icon grow/shrink zoom (ms)
    int bakeRefreshMs = 900;
    DWORD tint = 0x99101010;
    int w = 0;                   // saved size
    int h = 0;
    int hasSize = 0;
    std::wstring extraPins;
    std::wstring order;          // user order of the strip, see ItemKey()       // ';' separated .lnk/.exe paths
};

static Config g_cfg;
static std::wstring g_iniPath;

// ---- per-window glass parameters (user decision 2026-11-21) --------------------------------
// Everything that decides how a glass window *looks* belongs to that window: blur radius, tint
// strength, opacity (and the 色调 above). Only the cadence keys (refreshHz / captureHz /
// captureBudgetMs / dragNoCapture) stay global - those are about the machine, not about one window.
// Nothing is computed before the crop in BakeGlass(), so this split costs no extra work: two glass
// windows already run the whole pipeline separately, and the parameter count never enters the cost.
struct GlassCfg {
    int blurRadius = 16;
    int tintStrength = 110;
    int glassOpacity = 140;
};
static GlassCfg g_glass[2];      // [0] the strip ([dock]), [1] the companion ([traybar], -1 = inherit)

// ---- 色调 (hue): one colour per float window ------------------------------------------------
// User decision 2026-11-21: the 色调 IS the window's colour - it paints the solid background and
// it is the glass layer's tint colour (the old black/white `color` switch and the glass page's
// 浅色/深色 are gone). Per-window is safe: no cache bakes the tint in - the frozen work-area
// picture, the screen grab and the PrintWindow cache all hold *raw* pixels, and the tint is applied
// inside BakeGlass() on every bake.
static DWORD g_hue[2] = {0x101010, 0x101010};   // [0] the strip ([dock]), [1] the companion ([traybar])
static std::wstring g_pinDir;

// ---- tray double click (H1.2, user 2026-11-16)
// Some apps only open their window on a *double* click in the real notification area, and
// the user decided that "every tray click is sent twice" is the simplest rule (a second
// click on a tray icon normally does nothing). [tray] doubleClick= takes:
//   *            -> every icon (this is the default, see LoadConfig)
//   <exe>[,<exe>] -> only those (exe name or full path)
//   -<exe>       -> exception: never send it twice (works with '*' too)
// [tray] autoDoubleClick=1 is the fallback for the opposite case: send one click, and only
// send a second pair when the app demonstrably did nothing (~400 ms).
static bool g_trayDoubleClickAll = false;
static std::vector<std::wstring> g_trayDoubleClick;        // lower case exe name or full path
static std::vector<std::wstring> g_trayDoubleClickExcept;  // never doubled
static int g_trayAutoDoubleClick = 0;

// [tray] native: 1 (default) = the "^" slot opens and moves the shell's own overflow flyout
// (see NativeTrayToggle); 0 = the self-drawn grid. Kept as a switch so the old behaviour is
// one ini edit away.
static int g_trayNative = 1;

static HWND FindOverflowFlyout();   // defined next to NativeTrayToggle()
static bool IsOverflowFlyoutWindow(HWND h);
static void NativeTrayPark();

static void Trim(std::wstring& s) {
    while (!s.empty() && (s.back() == L'\r' || s.back() == L' ' || s.back() == L'\t')) s.pop_back();
    size_t i = 0;
    while (i < s.size() && (s[i] == L' ' || s[i] == L'\t')) i++;
    if (i) s.erase(0, i);
}

static int GetInt(const wchar_t* sec, const wchar_t* key, int def) {
    return (int)GetPrivateProfileIntW(sec, key, def, g_iniPath.c_str());
}

static std::wstring GetStr(const wchar_t* sec, const wchar_t* key, const wchar_t* def = L"") {
    std::vector<wchar_t> b(MAX_PATH * 2, 0);
    GetPrivateProfileStringW(sec, key, def, b.data(), (DWORD)b.size(), g_iniPath.c_str());
    return std::wstring(b.data());
}

// "#RRGGBB" / "RRGGBB" / "#AARRGGBB" (alpha ignored) -> 0x00RRGGBB
static DWORD ParseHexRgb(const std::wstring& s, DWORD def) {
    std::wstring t = s;
    Trim(t);
    if (t.empty()) return def;
    if (t[0] == L'#') t.erase(0, 1);
    if (t.size() != 6 && t.size() != 8) return def;
    wchar_t* end = nullptr;
    unsigned long v = wcstoul(t.c_str(), &end, 16);
    if (end && *end) return def;
    if (t.size() == 8) v &= 0x00FFFFFFu;      // drop the alpha
    return (DWORD)v;
}

// The 色调 of both windows. A profile that predates the key keeps its look: it falls back to the
// old black/white `color` switch plus the glass page's 浅色/深色.
static void LoadHues() {
    std::wstring s = GetStr(L"dock", L"hue");
    g_hue[0] = s.empty() ? (g_cfg.lightMode ? 0xFFFFFFu : 0x101010u) : ParseHexRgb(s, 0x101010u);
    std::wstring t = GetStr(L"traybar", L"hue");
    g_hue[1] = t.empty() ? g_hue[0] : ParseHexRgb(t, g_hue[0]);
}

// Ints from an ini section that may also inherit: a negative value means "use the strip's".
static int GetGlassInt(const wchar_t* section, const wchar_t* key, int stripVal, int lo, int hi) {
    int v = GetInt(section, key, -1);
    if (v < 0) v = stripVal;
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    return v;
}

// Resolve the per-window glass parameters. Must run after the strip's own values are loaded.
static void LoadGlassCfgs() {
    g_glass[0].blurRadius = g_cfg.blurRadius;
    g_glass[0].tintStrength = g_cfg.tintStrength;
    g_glass[0].glassOpacity = g_cfg.glassOpacity;
    g_glass[1].blurRadius = GetGlassInt(L"traybar", L"blurRadius", g_glass[0].blurRadius, 0, 64);
    g_glass[1].tintStrength =
        GetGlassInt(L"traybar", L"tintStrength", g_glass[0].tintStrength, 0, 255);
    g_glass[1].glassOpacity =
        GetGlassInt(L"traybar", L"glassOpacity", g_glass[0].glassOpacity, 0, 255);
}

static COLORREF ParseColor(const std::wstring& s, BYTE* alpha) {
    std::wstring t = s;
    Trim(t);
    if (t.empty()) return 0;
    if (t[0] == L'#') t.erase(0, 1);
    unsigned long v = wcstoul(t.c_str(), nullptr, 16);
    if (t.size() >= 8) {
        if (alpha) *alpha = (BYTE)(v >> 24);
        return RGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    }
    if (alpha) *alpha = 255;
    return RGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

// GetPrivateProfile* refuses a file that starts with a UTF-8 BOM: it then treats
// "[dock]" as garbage and every key silently falls back to its default. Editors
// such as PowerShell's Set-Content add that BOM, so strip it once at startup.
static void StripIniBom() {
    HANDLE f = CreateFileW(g_iniPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    BYTE head[3]{};
    DWORD got = 0;
    bool hasBom = ReadFile(f, head, 3, &got, nullptr) && got == 3 && head[0] == 0xEF &&
                  head[1] == 0xBB && head[2] == 0xBF;
    CloseHandle(f);
    if (!hasBom) return;

    std::string all;
    HANDLE in = CreateFileW(g_iniPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (in == INVALID_HANDLE_VALUE) return;
    DWORD size = GetFileSize(in, nullptr);
    if (size > 3 && size < 1024 * 1024) {
        all.resize(size);
        DWORD rd = 0;
        ReadFile(in, &all[0], size, &rd, nullptr);
    }
    CloseHandle(in);
    if (all.size() < 4) return;

    HANDLE out = CreateFileW(g_iniPath.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                             FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE) return;
    DWORD wr = 0;
    WriteFile(out, all.data() + 3, (DWORD)all.size() - 3, &wr, nullptr);
    CloseHandle(out);
}

static void LoadConfig() {
    wchar_t buf[1024]{};
    g_cfg.iconSize = GetInt(L"dock", L"iconSize", 32);
    g_cfg.gap = GetInt(L"dock", L"gap", 6);
    g_cfg.pad = GetInt(L"dock", L"pad", 10);
    // radius is a percentage of half the short side, so shrinking the strip
    // can never produce a radius bigger than the body
    g_cfg.radius = GetInt(L"dock", L"radius", 24);
    if (g_cfg.radius < 0) g_cfg.radius = 0;
    if (g_cfg.radius > 100) g_cfg.radius = 100;
    g_cfg.fadeStart = GetInt(L"dock", L"fadeStart", 48);
    g_cfg.fadeEnd = GetInt(L"dock", L"fadeEnd", 144);
    g_cfg.vertical = GetInt(L"dock", L"vertical", 0);
    g_cfg.clickActiveMinimizes = GetInt(L"dock", L"clickActiveMinimizes", 1);
    g_cfg.x = GetInt(L"dock", L"x", 200);
    g_cfg.y = GetInt(L"dock", L"y", 200);
    g_cfg.hasPos = GetInt(L"dock", L"hasPos", 0);
    GetPrivateProfileStringW(L"dock", L"bg", L"#00000000", buf, 1024, g_iniPath.c_str());
    g_cfg.bg = ParseColor(buf, &g_cfg.bgAlpha);
    GetPrivateProfileStringW(L"dock", L"hover", L"#28FFFFFF", buf, 1024, g_iniPath.c_str());
    BYTE ha = 0; ParseColor(buf, &ha); g_cfg.hoverAlpha = ha;
    GetPrivateProfileStringW(L"dock", L"extraPins", L"", buf, 1024, g_iniPath.c_str());
    g_cfg.extraPins = buf;
    {
        // the item order can be long: one key per strip item
        std::vector<wchar_t> ob(8192, 0);
        GetPrivateProfileStringW(L"dock", L"order", L"", ob.data(), (DWORD)ob.size(),
                                 g_iniPath.c_str());
        g_cfg.order = ob.data();
    }
    g_cfg.thumbWidth = GetInt(L"dock", L"thumbWidth", 220);
    g_cfg.thumbHeight = GetInt(L"dock", L"thumbHeight", 124);
    g_cfg.thumbDelay = GetInt(L"dock", L"thumbDelay", 400);
    g_cfg.minIcon = GetInt(L"dock", L"minIcon", 18);
    g_cfg.maxIcon = GetInt(L"dock", L"maxIcon", 72);
    g_cfg.scrollStep = GetInt(L"dock", L"scrollStep", 1);
    g_cfg.allowResize = GetInt(L"dock", L"allowResize", 1);
    g_cfg.upscaleSmallIcons = GetInt(L"dock", L"upscaleSmallIcons", 1);
    // ---- H2 layer model, migrated once from the old global `material` switch ---------------
    {
        const int materialOld = GetInt(L"dock", L"material", 1);
        // material=1 meant "glass over the desktop"; material=0 was the plain (transparent)
        // look. So the defaults reproduce both exactly, and no existing profile changes when
        // this build first runs.
        g_cfg.bgMode = GetInt(L"dock", L"bgMode", materialOld ? 0 : 2);
        if (g_cfg.bgMode < 0 || g_cfg.bgMode > 2) g_cfg.bgMode = materialOld ? 0 : 2;
        g_cfg.glassLayer = GetInt(L"dock", L"glassLayer", materialOld ? 1 : 0);
        if (g_cfg.glassLayer != 0 && g_cfg.glassLayer != 1) g_cfg.glassLayer = materialOld ? 1 : 0;
        g_cfg.color = GetInt(L"dock", L"color", 0);
        if (g_cfg.color < 0 || g_cfg.color > 1) g_cfg.color = 0;
        g_cfg.solidOpacity = GetInt(L"dock", L"solidOpacity", 235);
        if (g_cfg.solidOpacity < 0) g_cfg.solidOpacity = 0;
        if (g_cfg.solidOpacity > 255) g_cfg.solidOpacity = 255;
        g_cfg.dragNoCapture = GetInt(L"dock", L"dragNoCapture", 0);
        g_cfg.material = (g_cfg.bgMode == 0 && g_cfg.glassLayer) ? 1 : 0;
    }
    g_cfg.lightMode = GetInt(L"dock", L"lightMode", 0);
    g_cfg.glassOpacity = GetInt(L"dock", L"glassOpacity", 140);
    if (g_cfg.glassOpacity < 0) g_cfg.glassOpacity = 0;
    if (g_cfg.glassOpacity > 255) g_cfg.glassOpacity = 255;
    g_cfg.tintStrength = GetInt(L"dock", L"tintStrength", 110);
    if (g_cfg.tintStrength < 0) g_cfg.tintStrength = 0;
    if (g_cfg.tintStrength > 255) g_cfg.tintStrength = 255;
    g_cfg.dumpBake = GetInt(L"dock", L"dumpBake", 0);
    g_cfg.debugBeacon = GetInt(L"dock", L"debugBeacon", 0);
    g_cfg.presentSync = GetInt(L"dock", L"presentSync", 2);   // 2 = flush before, see Present()
    g_cfg.presentOrder = GetInt(L"dock", L"presentOrder", 0);
    // task 1: WS_EX_TOPMOST is band membership, not a rank - see the "z-order policy" block
    g_cfg.zWatch = GetInt(L"dock", L"zWatch", 1);
    if (g_cfg.zWatch < 0) g_cfg.zWatch = 0;
    if (g_cfg.zWatch > 1) g_cfg.zWatch = 1;
    // task 2: the double-click dodge; 1 = the behaviour this program always had
    g_cfg.dodgeOnDoubleClick = GetInt(L"dock", L"dodgeOnDoubleClick", 1);
    if (g_cfg.dodgeOnDoubleClick < 0) g_cfg.dodgeOnDoubleClick = 0;
    if (g_cfg.dodgeOnDoubleClick > 1) g_cfg.dodgeOnDoubleClick = 1;
    // task 3: the snap switch (both windows default to on = the behaviour that always existed)
    g_cfg.snap = GetInt(L"dock", L"snap", 1);
    if (g_cfg.snap < 0) g_cfg.snap = 0;
    if (g_cfg.snap > 1) g_cfg.snap = 1;
    g_cfg.blurIcons = GetInt(L"dock", L"blurIcons", 0);
    // `material` was read here before H2; it is derived from (bgMode, glassLayer) just above.
    if (g_cfg.material < 0 || g_cfg.material > 1) g_cfg.material = 1;
    g_cfg.blurRadius = GetInt(L"dock", L"blurRadius", 16);
    if (g_cfg.blurRadius < 0) g_cfg.blurRadius = 0;
    if (g_cfg.blurRadius > 64) g_cfg.blurRadius = 64;
    // three independent cadences: panel repaint, backdrop capture, icon animation
    g_cfg.refreshHz = GetInt(L"dock", L"refreshHz", 60);
    if (g_cfg.refreshHz < 1) g_cfg.refreshHz = 1;
    if (g_cfg.refreshHz > 180) g_cfg.refreshHz = 180;
    g_cfg.captureHz = GetInt(L"dock", L"captureHz", 5);
    if (g_cfg.captureHz < 0) g_cfg.captureHz = 0;
    if (g_cfg.captureHz > g_cfg.refreshHz) g_cfg.captureHz = g_cfg.refreshHz;
    g_cfg.captureBudgetMs = GetInt(L"dock", L"captureBudgetMs", 8);
    if (g_cfg.captureBudgetMs < 0) g_cfg.captureBudgetMs = 0;
    if (g_cfg.captureBudgetMs > 100) g_cfg.captureBudgetMs = 100;
    g_cfg.hoverMs = GetInt(L"dock", L"hoverMs", 160);
    if (g_cfg.hoverMs < 40) g_cfg.hoverMs = 40;
    if (g_cfg.hoverMs > 600) g_cfg.hoverMs = 600;
    g_cfg.bakeRefreshMs = GetInt(L"dock", L"bakeRefreshMs", 0);
    if (g_cfg.bakeRefreshMs < 0) g_cfg.bakeRefreshMs = 0;
    g_cfg.bakeRefreshMs = 0;      // always refresh: the delay was only confusing
    GetPrivateProfileStringW(L"dock", L"tint", L"#99101010", buf, 1024, g_iniPath.c_str());
    {
        std::wstring t = buf;
        Trim(t);
        if (!t.empty() && t[0] == L'#') t.erase(0, 1);
        g_cfg.tint = (DWORD)wcstoul(t.c_str(), nullptr, 16);
        if (t.size() <= 6) g_cfg.tint |= 0xFF000000;
    }
    g_cfg.w = GetInt(L"dock", L"w", 0);
    g_cfg.h = GetInt(L"dock", L"h", 0);
    g_cfg.hasSize = GetInt(L"dock", L"hasSize", 0);
    if (g_cfg.scrollStep < 1) g_cfg.scrollStep = 1;
    if (g_cfg.thumbWidth < 80) g_cfg.thumbWidth = 80;
    if (g_cfg.thumbHeight < 60) g_cfg.thumbHeight = 60;
    if (g_cfg.thumbDelay < 0) g_cfg.thumbDelay = 0;
    if (g_cfg.fadeEnd <= g_cfg.fadeStart) g_cfg.fadeEnd = g_cfg.fadeStart + 1;
    LoadHues();      // per-window 色调 (falls back to the old color / lightMode pair)
    LoadGlassCfgs(); // per-window glass parameters ([traybar] -1 = inherit the strip's)

    // [tray] doubleClick=*|<exe,...>|-<exe>,...   /  [tray] autoDoubleClick=0|1
    {
        std::vector<wchar_t> lb(2048, 0);
        GetPrivateProfileStringW(L"tray", L"doubleClick", L"*", lb.data(), (DWORD)lb.size(),
                                 g_iniPath.c_str());
        std::wstring list = lb.data();
        g_trayDoubleClickAll = false;
        g_trayDoubleClick.clear();
        g_trayDoubleClickExcept.clear();
        std::wstring cur;
        for (size_t i = 0; i <= list.size(); i++) {
            const wchar_t ch = i < list.size() ? list[i] : L';';
            if (ch == L';' || ch == L',' || ch == L'\r' || ch == L'\n') {
                Trim(cur);
                if (!cur.empty()) {
                    bool except = false;
                    if (cur[0] == L'-') {
                        except = true;
                        cur.erase(0, 1);
                        Trim(cur);
                    }
                    if (cur == L"*" || cur == L"all") {
                        g_trayDoubleClickAll = true;
                    } else if (!cur.empty()) {
                        for (auto& c : cur) c = (wchar_t)towlower(c);
                        (except ? g_trayDoubleClickExcept : g_trayDoubleClick)
                            .push_back(cur);
                    }
                }
                cur.clear();
            } else {
                cur.push_back(ch);
            }
        }
        g_trayAutoDoubleClick = GetInt(L"tray", L"autoDoubleClick", 0) ? 1 : 0;
        g_trayNative = GetInt(L"tray", L"native", 1) ? 1 : 0;
    }
}

static void SavePosition() {
    wchar_t b[32];
    swprintf_s(b, L"%d", g_cfg.x); WritePrivateProfileStringW(L"dock", L"x", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", g_cfg.y); WritePrivateProfileStringW(L"dock", L"y", b, g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hasPos", L"1", g_iniPath.c_str());
    CompanionSaveAllPositions();      // attached windows moved with us; keep the ini honest
}

static void SaveSize() {
    RECT rc{};
    if (!GetClientRect(g_hwnd, &rc)) return;
    wchar_t b[32];
    swprintf_s(b, L"%d", rc.right); WritePrivateProfileStringW(L"dock", L"w", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", rc.bottom); WritePrivateProfileStringW(L"dock", L"h", b, g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hasSize", L"1", g_iniPath.c_str());
}

// ---------------------------------------------------------------- cadence
// Three independent rates, all live-tunable from the settings panel:
//   refreshHz - how often the strip repaints (0..180)
//   captureHz - how often the backdrop is re-captured; capped at refreshHz (0 = frozen)
//   hoverHz   - how often the icon grow/shrink animation takes a step (1..180)
// Windows timers are quantised to the system tick (15.6ms = ~64Hz), so anything faster
// asks for a 1ms timer resolution while it is in effect.
static bool g_hiResTimer = false;

// high-resolution frame clock (see FrameClockThread)
static volatile LONG g_tickPosted = 0;
static volatile LONG g_timerExit = 0;
static HANDLE g_timerWake = nullptr;
static HANDLE g_timerThread = nullptr;
static double g_tickPeriod100ns = 333333.0;      // 30Hz


static UINT RefreshPeriodMs() {
    int hz = g_cfg.refreshHz;
    if (hz < 1) hz = 1;
    if (hz > 180) hz = 180;
    UINT ms = (UINT)(1000 / hz);
    return ms < 1 ? 1 : ms;
}

static void ApplyTimerResolution() {
    // Always ask for a 1ms timer while the dock runs: WITHOUT it SetTimer rounds up to
    // the 15.6ms system tick (a 33ms request became 47ms, i.e. 21Hz instead of 30Hz).
    bool want = g_cfg.refreshHz > 0;
    if (want == g_hiResTimer) return;
    if (want) {
        if (timeBeginPeriod(1) == TIMERR_NOERROR) g_hiResTimer = true;
    } else {
        timeEndPeriod(1);
        g_hiResTimer = false;
    }
}

static void ArmRepaintTimer(HWND h) {
    if (!h) return;
    int hz = g_cfg.refreshHz < 1 ? 1 : g_cfg.refreshHz;
    g_tickPeriod100ns = 10000000.0 / (double)hz;   // the frame clock reads this every loop
    if (!g_timerThread) ApplyTimerResolution();
    UINT ms = g_timerThread ? 1000u : RefreshPeriodMs();
    SetTimer(h, 1, ms, nullptr);
    DLog(L"cadence: refresh=%d Hz (%u ms), capture=%d Hz, hover=%d ms, 1ms timer=%d, "
         L"capture budget=%d ms",
         g_cfg.refreshHz, ms, g_cfg.captureHz, g_cfg.hoverMs, (int)g_hiResTimer,
         g_cfg.captureBudgetMs);
}

static void CreateDefaultIni() {
    WritePrivateProfileStringW(L"dock", L"iconSize", L"32", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"gap", L"6", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"pad", L"10", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"radius", L"24", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"bg", L"#3C000000", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hover", L"#28FFFFFF", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"fadeStart", L"48", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"fadeEnd", L"144", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"vertical", L"0", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"clickActiveMinimizes", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"extraPins", L"", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"thumbWidth", L"220", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"thumbHeight", L"124", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"thumbDelay", L"400", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"minIcon", L"18", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"maxIcon", L"72", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"scrollStep", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"allowResize", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"upscaleSmallIcons", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"material", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"lightMode", L"0", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"glassOpacity", L"140", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"tintStrength", L"110", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"blurRadius", L"16", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"refreshHz", L"60", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"captureHz", L"5", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"hoverMs", L"160", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"bakeRefreshMs", L"900", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"zWatch", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"dodgeOnDoubleClick", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"snap", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(L"dock", L"tint", L"#99101010", g_iniPath.c_str());
}

// ---------------------------------------------------------------- items
struct Item {
    std::vector<uint32_t> px;    // pre-scaled premultiplied ARGB at cachedPx
    int cachedPx = 0;
    std::wstring iconPath;       // file the shell should render the icon from
    bool isPin = false;
    HWND hwnd = nullptr;
    HICON icon = nullptr;
    std::wstring title;
    std::wstring lnkPath;   // pins
    std::wstring exePath;   // for matching running windows (lowercase)
    bool hasWindow = false;
    // reorder animation: displayed x (client) easing towards the slot's x
    float animX = -1e9f;
    int targetX = 0;
};

static const int kReorderInset = 6;      // px of hysteresis at a cell boundary
static const float kReorderZoom = 1.34f; // the dragged icon stays at the hover size

static std::vector<Item> g_items;
static int g_hover = -1;

static std::wstring Lower(std::wstring s) {
    for (auto& c : s) c = (wchar_t)towlower(c);
    return s;
}

static bool IsCloaked(HWND h) {
    BOOL c = FALSE;
    return SUCCEEDED(DwmGetWindowAttribute(h, DWMWA_CLOAKED, &c, sizeof(c))) && c;
}

static std::wstring WindowExe(HWND h) {
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (!pid) return L"";
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return L"";
    wchar_t path[MAX_PATH]{};
    DWORD sz = MAX_PATH;
    QueryFullProcessImageNameW(p, 0, path, &sz);
    CloseHandle(p);
    return Lower(path);
}

static bool IsDockWindow(HWND h) {
    wchar_t cls[64]{};
    if (!GetClassNameW(h, cls, 64)) return true;
    static const wchar_t* skip[] = {L"Shell_TrayWnd", L"Shell_SecondaryTrayWnd", L"Progman",
                                    L"WorkerW", L"Windows.UI.Core.CoreWindow"};
    for (auto s : skip) if (!_wcsicmp(cls, s)) return true;
    return false;
}

// The shell's own "does this window get a taskbar button" test, approximated:
//   visible && !cloaked && (WS_EX_APPWINDOW || (!WS_EX_TOOLWINDOW && no owner))
// WS_EX_APPWINDOW outranks a tool-window style and an owner, exactly like the
// real taskbar; a title is irrelevant to the shell, so it is irrelevant here
// (untitled windows are labelled with their exe name by WindowLabel()).
static bool IsCandidate(HWND h) {
    if (!IsWindow(h) || !IsWindowVisible(h) || IsCloaked(h)) return false;
    LONG ex = GetWindowLongW(h, GWL_EXSTYLE);
    if (!(ex & WS_EX_APPWINDOW)) {
        if (ex & WS_EX_TOOLWINDOW) return false;
        if (GetWindow(h, GW_OWNER)) return false;
    }
    if (h == GetShellWindow()) return false;
    if (IsDockWindow(h)) return false;
    return true;
}

// What the button should say: the window title, or - for the untitled windows
// that the shell still buttons - the executable's name.
static std::wstring WindowLabel(HWND h) {
    wchar_t t[256]{};
    GetWindowTextW(h, t, 256);
    if (t[0]) return t;
    std::wstring exe = WindowExe(h);
    size_t slash = exe.find_last_of(L'\\');
    if (slash != std::wstring::npos && slash + 1 < exe.size()) return exe.substr(slash + 1);
    return exe.empty() ? L" " : exe;
}

static HICON IconForWindow(HWND h) {
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
    HICON src = (HICON)SendMessageTimeoutW(h, WM_GETICON, ICON_BIG, 0, SMTO_ABORTIFHUNG, 100, nullptr);
    if (!src) src = (HICON)GetClassLongPtrW(h, GCLP_HICON);
    if (src) {
        HICON copy = (HICON)CopyIcon(src);
        if (copy) return copy;
    }
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    wchar_t path[MAX_PATH]{};
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (p) {
        DWORD sz = MAX_PATH;
        QueryFullProcessImageNameW(p, 0, path, &sz);
        CloseHandle(p);
    }
    SHFILEINFOW sfi{};
    if (SHGetFileInfoW(path, 0, &sfi, sizeof(sfi), SHGFI_ICON | SHGFI_LARGEICON))
        return sfi.hIcon;      // owned by us
    return nullptr;
}

static IImageList* g_smallIcons = nullptr;
static IImageList* g_largeIcons = nullptr;
static IImageList* g_xlIcons = nullptr;
static IImageList* g_jumboIcons = nullptr;
static int g_iconBucket = 32;

// Ask the shell for the bitmap that matches the size we are about to draw.
// Scaling the 256px jumbo bitmap down to 32px was what made everything soft.
static HICON HiResIconForPath(const std::wstring& path) {
    if (path.empty()) return nullptr;
    SHFILEINFOW sfi{};
    if (!SHGetFileInfoW(path.c_str(), 0, &sfi, sizeof(sfi), SHGFI_SYSICONINDEX)) return nullptr;

    IImageList** slot = &g_jumboIcons;
    int listId = SHIL_JUMBO;
    if (g_iconBucket <= 16) { slot = &g_smallIcons; listId = SHIL_SMALL; }
    else if (g_iconBucket <= 32) { slot = &g_largeIcons; listId = SHIL_LARGE; }
    else if (g_iconBucket <= 48) { slot = &g_xlIcons; listId = SHIL_EXTRALARGE; }

    if (!*slot) {
        void* pv = nullptr;
        if (FAILED(SHGetImageList(listId, IID_IImageList, &pv))) return nullptr;
        *slot = static_cast<IImageList*>(pv);
    }
    HICON icon = nullptr;
    if (SUCCEEDED((*slot)->GetIcon(sfi.iIcon, ILD_TRANSPARENT, &icon)) && icon) return icon;
    return nullptr;
}

static HICON LoadIconFromPath(const std::wstring& path) {
    if (HICON hi = HiResIconForPath(path)) return hi;
    SHFILEINFOW sfi{};
    if (SHGetFileInfoW(path.c_str(), 0, &sfi, sizeof(sfi), SHGFI_ICON | SHGFI_LARGEICON))
        return sfi.hIcon;
    return nullptr;
}

static std::wstring LnkTarget(const std::wstring& lnk) {
    IShellLinkW* link = nullptr;
    std::wstring result;
    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IShellLinkW, (void**)&link))) {
        IPersistFile* pf = nullptr;
        if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, (void**)&pf))) {
            if (SUCCEEDED(pf->Load(lnk.c_str(), STGM_READ))) {
                wchar_t target[MAX_PATH]{};
                WIN32_FIND_DATAW fd{};
                if (SUCCEEDED(link->GetPath(target, MAX_PATH, &fd, SLGP_UNCPRIORITY)) && target[0])
                    result = Lower(target);
            }
            pf->Release();
        }
        link->Release();
    }
    return result;
}

// The authoritative pin list lives in the registry, not in the pinned folder:
// "User Pinned\TaskBar" keeps shortcuts the user already unpinned long ago
// (e.g. 网易UU远程), so enumerating that folder invents buttons the real
// taskbar does not have. HKCU\...\Explorer\Taskband\Favorites is a REG_BINARY
// blob that stores each pin as a byte-aligned structure holding the .lnk file
// name as UTF-16, and the structures are not aligned to each other - decoding
// the blob as UTF-16 at offset 0 misses some names, decoding at offset 1
// misses the others. So keep both views and match the file name in either.
static bool PinnedLnkListed(const std::wstring& fileName) {
    static std::vector<std::wstring> views;
    static bool loaded = false;
    static DWORD blobBytes = 0;
    if (!loaded) {
        loaded = true;
        HKEY k = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER,
                          L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Taskband", 0,
                          KEY_READ, &k) == ERROR_SUCCESS) {
            DWORD type = 0, size = 0;
            if (RegQueryValueExW(k, L"Favorites", nullptr, &type, nullptr, &size) == ERROR_SUCCESS &&
                type == REG_BINARY && size > 1) {
                std::vector<BYTE> buf(size + 2, 0);
                if (RegQueryValueExW(k, L"Favorites", nullptr, &type, buf.data(), &size) ==
                    ERROR_SUCCESS) {
                    blobBytes = size;
                    for (int shift = 0; shift < 2; shift++) {
                        size_t chars = (size_t)(size - shift) / 2;
                        std::wstring s(chars, L'\\0');
                        memcpy(&s[0], buf.data() + shift, chars * 2);
                        views.push_back(std::move(s));
                    }
                }
            }
            RegCloseKey(k);
        }
        DLog(L"pins: Taskband\\Favorites = %lu bytes, %d decode views", (unsigned long)blobBytes,
             (int)views.size());
    }
    if (views.empty()) return true;   // no blob to consult: trust the folder
    for (const auto& v : views)
        if (v.find(fileName) != std::wstring::npos) return true;
    return false;
}

static HICON IconFromFileIndex(const std::wstring& file, int index) {
    HICON big = nullptr;
    if (ExtractIconExW(file.c_str(), index, &big, nullptr, 1) == 1 && big) return big;
    return nullptr;
}

// Prefer the shortcut's declared icon location: loading the .lnk itself gives
// the icon with the shortcut arrow overlay painted on.
static HICON PinIcon(const std::wstring& lnk, const std::wstring& target) {
    IShellLinkW* link = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IShellLinkW, (void**)&link))) {
        IPersistFile* pf = nullptr;
        if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, (void**)&pf))) {
            if (SUCCEEDED(pf->Load(lnk.c_str(), STGM_READ))) {
                wchar_t iconPath[MAX_PATH]{};
                int index = 0;
                if (SUCCEEDED(link->GetIconLocation(iconPath, MAX_PATH, &index)) && iconPath[0]) {
                    wchar_t expanded[MAX_PATH]{};
                    ExpandEnvironmentStringsW(iconPath, expanded, MAX_PATH);
                    if (HICON i = IconFromFileIndex(expanded, index)) {
                        pf->Release();
                        link->Release();
                        return i;
                    }
                }
            }
            pf->Release();
        }
        link->Release();
    }
    if (!target.empty()) {
        if (HICON i = LoadIconFromPath(target)) return i;
    }
    return LoadIconFromPath(lnk);
}

// Last-resort resolution for pins whose .lnk has no file target (shell namespace items).
// Tries the shell ID list first (many namespace links resolve to a real folder) and then
// the shortcut's icon location, which is normally the executable the shell would start
// (%windir%\explorer.exe,0 for the built-in File Explorer pin).
static std::wstring LnkTargetFallback(const std::wstring& lnk) {
    IShellLinkW* link = nullptr;
    std::wstring result;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW,
                                (void**)&link)))
        return result;
    IPersistFile* pf = nullptr;
    if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, (void**)&pf)) &&
        SUCCEEDED(pf->Load(lnk.c_str(), STGM_READ))) {
        PIDLIST_ABSOLUTE pidl = nullptr;
        if (SUCCEEDED(link->GetIDList(&pidl)) && pidl) {
            wchar_t buf[MAX_PATH]{};
            if (SHGetPathFromIDListW(pidl, buf) && buf[0] && PathFileExistsW(buf)) {
                std::wstring s = buf;
                if (s.size() > 4 && Lower(s).compare(s.size() - 4, 4, L".exe") == 0)
                    result = Lower(s);
            }
            CoTaskMemFree(pidl);
        }
        if (result.empty()) {
            wchar_t iconPath[MAX_PATH]{};
            int index = 0;
            if (SUCCEEDED(link->GetIconLocation(iconPath, MAX_PATH, &index)) && iconPath[0]) {
                wchar_t expanded[MAX_PATH]{};
                ExpandEnvironmentStringsW(iconPath, expanded, MAX_PATH);
                std::wstring s = expanded;
                size_t comma = s.find_last_of(L',');
                if (comma != std::wstring::npos) s = s.substr(0, comma);
                if (PathFileExistsW(s.c_str()) && s.size() > 4 &&
                    Lower(s).compare(s.size() - 4, 4, L".exe") == 0)
                    result = Lower(s);
            }
        }
    }
    if (pf) pf->Release();
    link->Release();
    return result;
}

// exe -> (pin name, pin .lnk). Kept even while the pin has windows (BuildItems then shows
// one button per window and drops the pin item), because the strip's right-click menu
// needs both: the friendly name and the shortcut to "run like the taskbar would".
struct PinInfo {
    std::wstring name;
    std::wstring lnk;
};
static std::map<std::wstring, PinInfo> g_pinInfo;
static const PinInfo* PinForExe(const std::wstring& exe) {
    if (exe.empty()) return nullptr;
    auto it = g_pinInfo.find(Lower(exe));
    return it == g_pinInfo.end() ? nullptr : &it->second;
}

static void AddPin(const std::wstring& path) {
    Item it;
    it.isPin = true;
    it.lnkPath = path;
    wchar_t name[MAX_PATH]{};
    const wchar_t* base = PathFindFileNameW(path.c_str());
    wcscpy_s(name, base);
    PathRemoveExtensionW(name);
    it.title = name;
    it.exePath = LnkTarget(path);
    if (it.exePath.empty()) {
        // Some taskbar pins are shell *namespace* items, not files: the built-in
        // "File Explorer" pin has no target path at all (its icon points at
        // %windir%\explorer.exe). Without an exe the pin can never be matched to its
        // windows, so it stayed on the strip as a second, useless button ("zombie")
        // while every opened window got its own - and clicking it ran the shortcut,
        // which Explorer either reuses or turns into yet another window.
        it.exePath = LnkTargetFallback(path);
        if (!it.exePath.empty())
            DLog(L"pin '%s' has no target path - using %s for window matching", name,
                 it.exePath.c_str());
        else
            DLog(L"pin '%s' has no target path and no usable icon exe - it will never "
                 L"match a window", name);
    }
    it.iconPath = it.exePath.empty() ? path : it.exePath;
    it.icon = PinIcon(path, it.exePath);
    if (!it.exePath.empty()) g_pinInfo[Lower(it.exePath)] = PinInfo{it.title, path};
    g_items.push_back(it);
}

static void DLog(const wchar_t* fmt, ...);
static void ThumbHide();
static HWND g_thumbWnd;

// Logs what kind of token/process context we are in: a restricted token (e.g.
// launched from a sandboxed host) silently blocks CreateProcess/ShellExecute.
static void LogProcessContext() {
    DWORD pid = GetCurrentProcessId();
    DWORD session = 0;
    ProcessIdToSessionId(pid, &session);

    DWORD restricted = 0xFFFFFFFF, integrity = 0, elevated = 0xFFFFFFFF;
    HANDLE tok = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
        DWORD sz = 0;
        GetTokenInformation(tok, TokenIsRestricted, &restricted, sizeof(restricted), &sz);
        GetTokenInformation(tok, TokenElevation, &elevated, sizeof(elevated), &sz);
        BYTE buf[512]{};
        if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof(buf), &sz)) {
            auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf);
            DWORD count = *GetSidSubAuthorityCount(label->Label.Sid);
            if (count) integrity = *GetSidSubAuthority(label->Label.Sid, count - 1);
        }
        CloseHandle(tok);
    }

    DWORD parent = 0;
    WCHAR parentName[MAX_PATH] = L"?";
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W pe{sizeof(pe)};
        std::vector<PROCESSENTRY32W> all;
        if (Process32FirstW(snap, &pe)) {
            do { all.push_back(pe); } while (Process32NextW(snap, &pe));
        }
        CloseHandle(snap);
        for (auto& e : all) {
            if (e.th32ProcessID == pid) { parent = e.th32ParentProcessID; break; }
        }
        for (auto& e : all) {
            if (e.th32ProcessID == parent) { wcscpy_s(parentName, e.szExeFile); break; }
        }
    }

    DLog(L"pid=%lu session=%lu parent=%lu(%s) restricted=%ld elevated=%ld integrity=%lu", pid,
         session, parent, parentName, (long)restricted, (long)elevated, integrity);
}

static void DLog(const wchar_t* fmt, ...);

static void ComputeButtons();
static void PaintAndPresent();

// Identity of a strip item for the persisted order. One key for a pin and for the windows
// it owns, so a pin and its running windows keep travelling together.
static std::wstring ItemKey(const Item& it) {
    if (!it.exePath.empty()) return Lower(it.exePath);
    if (!it.title.empty()) return L"t:" + Lower(it.title);
    return L"";
}

// Rewrite g_cfg.order from the current in-memory order. Called live while reordering so the
// periodic BuildItems() cannot undo it; the ini is only written when the drag ends.
static void SyncOrder() {
    std::wstring out;
    for (size_t i = 0; i < g_items.size(); i++) {
        std::wstring k = ItemKey(g_items[i]);
        if (k.empty()) continue;
        if (!out.empty()) out += L';';
        out += k;
    }
    g_cfg.order = out;
}

static void MoveItem(int from, int to) {
    if (from < 0 || to < 0 || from == to) return;
    if (from >= (int)g_items.size() || to >= (int)g_items.size()) return;
    Item it = g_items[from];
    g_items.erase(g_items.begin() + from);
    g_items.insert(g_items.begin() + to, it);
}

static void FinishReorder() {
    SyncOrder();
    if (!g_cfg.order.empty())
        WritePrivateProfileStringW(L"dock", L"order", g_cfg.order.c_str(), g_iniPath.c_str());
    DLog(L"reorder done: %s", g_cfg.order.c_str());
    ComputeButtons();
    PaintAndPresent();
}

static void BuildItems() {
    // Stable ordering: the position of a button is decided the first time its
    // window is seen, so switching between windows never reorders the strip.
    static std::map<HWND, DWORD> seenOrder;
    static DWORD seenNext = 1;
    for (auto it = seenOrder.begin(); it != seenOrder.end();) {
        if (!IsWindow(it->first)) it = seenOrder.erase(it);
        else ++it;
    }
    auto order = [&](HWND h) -> DWORD {
        auto it = seenOrder.find(h);
        if (it != seenOrder.end()) return it->second;
        DWORD v = seenNext++;
        seenOrder[h] = v;
        return v;
    };
    for (auto& it : g_items) if (it.icon) { DestroyIcon(it.icon); it.icon = nullptr; }
    g_items.clear();
    g_pinInfo.clear();

    // pins first, in the shell's pinned folder
    WIN32_FIND_DATAW fd{};
    std::wstring pattern = g_pinDir + L"\\*.lnk";
    HANDLE find = FindFirstFileW(pattern.c_str(), &fd);
    std::vector<std::wstring> lnks;
    if (find != INVALID_HANDLE_VALUE) {
        do {
            if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) lnks.push_back(g_pinDir + L"\\" + fd.cFileName);
        } while (FindNextFileW(find, &fd));
        FindClose(find);
    }
    std::sort(lnks.begin(), lnks.end());
    int pinSkip = 0;
    for (auto& l : lnks) {
        std::wstring name = PathFindFileNameW(l.c_str());
        if (!PinnedLnkListed(name)) {
            DLog(L"pin skip (leftover, not in Taskband\\Favorites): %s", name.c_str());
            pinSkip++;
            continue;
        }
        AddPin(l);
    }
    DLog(L"pins: %d from the pinned folder, %d skipped as leftovers", (int)g_items.size(), pinSkip);

    // extra pins from the ini
    size_t start = 0;
    while (start < g_cfg.extraPins.size()) {
        size_t end = g_cfg.extraPins.find(L';', start);
        std::wstring part = g_cfg.extraPins.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
        Trim(part);
        if (!part.empty() && PathFileExistsW(part.c_str())) AddPin(part);
        if (end == std::wstring::npos) break;
        start = end + 1;
    }

    // running windows, top of the z-order first
    struct Ctx {
        std::vector<std::pair<HWND, std::wstring>> list;
    } ctx;
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            auto* c = reinterpret_cast<Ctx*>(lp);
            if (IsCandidate(h)) c->list.push_back({h, WindowExe(h)});
            return TRUE;
        },
        (LPARAM)&ctx);

    // pins that have windows: attach their windows right after the pin
    std::vector<Item> ordered;
    std::vector<bool> used(ctx.list.size(), false);
    for (auto& pin : g_items) {
        std::vector<size_t> idx;
        if (!pin.exePath.empty()) {
            for (size_t i = 0; i < ctx.list.size(); i++) {
                if (used[i] || ctx.list[i].second != pin.exePath) continue;
                idx.push_back(i);
            }
        }
        std::sort(idx.begin(), idx.end(),
                  [&](size_t a, size_t b) { return order(ctx.list[a].first) < order(ctx.list[b].first); });
        std::vector<Item> wins;
        for (size_t i : idx) {
            Item w;
            w.hwnd = ctx.list[i].first;
            w.title = WindowLabel(ctx.list[i].first);
            w.icon = IconForWindow(ctx.list[i].first);
            used[i] = true;
            wins.push_back(w);
        }
        if (wins.empty()) {
            ordered.push_back(pin);     // just a shortcut: click launches it
        } else {
            pin.hasWindow = true;
            for (auto& w : wins) ordered.push_back(w);   // one button per window
        }
    }
    std::vector<size_t> rest;
    for (size_t i = 0; i < ctx.list.size(); i++)
        if (!used[i]) rest.push_back(i);
    std::sort(rest.begin(), rest.end(),
              [&](size_t a, size_t b) { return order(ctx.list[a].first) < order(ctx.list[b].first); });
    for (size_t i : rest) {
        Item w;
        w.hwnd = ctx.list[i].first;
        w.title = WindowLabel(ctx.list[i].first);
        w.icon = IconForWindow(ctx.list[i].first);
        ordered.push_back(w);
    }
    g_items.swap(ordered);
    g_cachedIconPx = 0;      // fresh Item objects: the pixel cache must rebuild
    for (auto& it : g_items) {
        // window items need their exe too: BuildTray() uses it to tell "already
        // on the strip" apart from "tray only"
        if (it.hwnd && it.exePath.empty()) it.exePath = WindowExe(it.hwnd);
        if (it.iconPath.empty() && it.hwnd) it.iconPath = it.exePath;
    }

    // The user's own order, if any (drag an icon to a new place). Stable sort: a pin and the
    // windows of its exe share a key and stay together, and anything the list does not mention
    // keeps its build order behind the listed entries.
    if (!g_cfg.order.empty()) {
        std::vector<std::wstring> keys;
        size_t s = 0;
        while (s <= g_cfg.order.size()) {
            size_t e = g_cfg.order.find(L';', s);
            std::wstring k = g_cfg.order.substr(s, e == std::wstring::npos ? std::wstring::npos : e - s);
            Trim(k);
            if (!k.empty()) keys.push_back(k);
            if (e == std::wstring::npos) break;
            s = e + 1;
        }
        auto rank = [&](const Item& it) -> size_t {
            std::wstring k = ItemKey(it);
            for (size_t i = 0; i < keys.size(); i++)
                if (keys[i] == k) return i;
            return keys.size();
        };
        std::stable_sort(g_items.begin(), g_items.end(),
                         [&](const Item& a, const Item& b) { return rank(a) < rank(b); });
        DLog(L"order: applied %d key(s) to %d item(s)", (int)keys.size(), (int)g_items.size());
    }

    // log the strip contents whenever it changes (helps diagnosing clicks)
    static size_t lastSig = 0;
    size_t sig = g_items.size();
    for (auto& it : g_items) sig = (sig ^ (size_t)it.hwnd) * 1099511628211ull;
    if (sig != lastSig) {
        lastSig = sig;
        DLog(L"items=%d", (int)g_items.size());
        for (size_t i = 0; i < g_items.size(); i++) {
            DLog(L"  [%d] hwnd=%p pin=%d exe=%s title=%s", (int)i, (void*)g_items[i].hwnd,
                 (int)g_items[i].isPin, g_items[i].exePath.c_str(), g_items[i].title.c_str());
        }
    }
}

// ---------------------------------------------------------------- painting
// When set, the next Present() also moves the window to this point. UpdateLayeredWindow
// applies position and pixels in one go, which is what makes a drag frame atomic: moving
// first and repainting later always left the old pixels one frame behind.
static POINT g_renderPos{INT_MIN, INT_MIN};
static int g_alpha = 255;

// ---- frame timing (diagnostics) ------------------------------------------
static double g_qpcFreq = 0.0;
static double g_statGlass = 0, g_statIcons = 0, g_statPresent = 0, g_statBake = 0;
static int g_statPaints = 0, g_statPresents = 0, g_statBakes = 0;
// presentSync=2's DwmFlush() *waits* for the next composition and is invisible in the "present"
// figure above (which only wraps the two real present calls). On this 144 Hz screen it measures
// 4.3-4.4 ms per moving frame - the single largest per-frame cost of a drag, so it is measured.
static double g_statSync = 0;
static int g_statSyncs = 0;
// Frames where the strip had moved out of its backdrop snapshot while a drag forbade
// re-capturing. Non-zero means the glass is being drawn from a picture that no longer covers
// the window - the "背景抖动" the user saw on 2026-11-16 14:48. Reported in the cadence line.
static int g_lostSnapshot = 0;
static void QpcInit() {
    LARGE_INTEGER f{};
    QueryPerformanceFrequency(&f);
    g_qpcFreq = (double)f.QuadPart;
}
static double QpcMs(const LARGE_INTEGER& a, const LARGE_INTEGER& b) {
    if (g_qpcFreq <= 0) return 0.0;
    return (double)(b.QuadPart - a.QuadPart) * 1000.0 / g_qpcFreq;
}
static bool g_clickThrough = false;
static HDC g_memDC = nullptr;
static HBITMAP g_dib = nullptr;
static void* g_bits = nullptr;
static int g_dibW = 0, g_dibH = 0;
static POINT g_dragStart{};
static RECT g_dragRect{};
static bool g_dragging = false;
static bool g_dragMovePending = false;   // move the window in the same tick as the repaint

// ---- diagnostics -------------------------------------------------------
static std::wstring g_logPath;
static void DLog(const wchar_t* fmt, ...) {
    if (g_logPath.empty()) return;
    wchar_t buf[1024];
    va_list ap;
    va_start(ap, fmt);
    _vsnwprintf_s(buf, _TRUNCATE, fmt, ap);
    va_end(ap);
    SYSTEMTIME st;
    GetLocalTime(&st);
    wchar_t line[1200];
    _snwprintf_s(line, _TRUNCATE, L"%02d:%02d:%02d.%03d %s\r\n", st.wHour, st.wMinute,
                 st.wSecond, st.wMilliseconds, buf);
    FILE* f = nullptr;
    if (_wfopen_s(&f, g_logPath.c_str(), L"a, ccs=UTF-8") == 0 && f) {
        fputws(line, f);
        fclose(f);
    }
}

static void EnsureDib(int w, int h) {
    if (w == g_dibW && h == g_dibH && g_dib) return;
    if (g_memDC) { DeleteDC(g_memDC); g_memDC = nullptr; }
    if (g_dib) { DeleteObject(g_dib); g_dib = nullptr; }
    HDC screen = GetDC(nullptr);
    g_memDC = CreateCompatibleDC(screen);
    ReleaseDC(nullptr, screen);
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    g_dib = CreateDIBSection(g_memDC, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    SelectObject(g_memDC, g_dib);
    g_bits = bits;
    g_dibW = w; g_dibH = h;
    g_paintBits = bits; g_paintW = w; g_paintH = h;
}

// GDI fills write alpha 0 into a 32bpp DIB, which makes the pixels invisible for
// UpdateLayeredWindow, so round rects are rasterised by hand (premultiplied).
static void FillRound(HDC dc, const RECT& r, int radius, DWORD argb) {
    // sub-pixel coverage: without it every rounded corner was a hard stair-step,
    // which is what made the panel's pills and knob look blurry
    int w = r.right - r.left, h = r.bottom - r.top;
    if (w <= 0 || h <= 0) return;
    int R = radius;
    int maxR = (w < h ? w : h) / 2;
    if (R > maxR) R = maxR;
    if (R < 0) R = 0;
    double cx = r.left + w / 2.0, cy = r.top + h / 2.0;
    double hw = w / 2.0, hh = h / 2.0;
    DWORD baseA = (argb >> 24) & 0xFF;
    for (int y = r.top; y < r.bottom; y++) {
        for (int x = r.left; x < r.right; x++) {
            double qx = fabs(x + 0.5 - cx) - (hw - R);
            double qy = fabs(y + 0.5 - cy) - (hh - R);
            double ax = qx > 0 ? qx : 0;
            double ay = qy > 0 ? qy : 0;
            double inx = qx > qy ? qx : qy;
            if (inx > 0) inx = 0;
            double d = sqrt(ax * ax + ay * ay) + inx - R;
            double cov = 0.5 - d;
            if (cov <= 0) continue;
            if (cov > 1) cov = 1;
            DWORD a = (DWORD)(baseA * cov);
            if (!a) continue;
            SetPixelPremul(x, y, (a << 24) | (argb & 0x00FFFFFF));
        }
    }
}

// A 1 px (or thicker) rounded outline, antialiased the same way FillRound is: two signed
// distances - the outer rounded rect and the same shape inset by `thickness` - and the ring is
// their difference. Only the border band is visited: the group frame is repainted whenever a
// member is dragged, so this has to stay proportional to the perimeter, not to the area.
static void FillRoundRing(int w, int h, int radius, int thickness, DWORD argb) {
    if (w <= 0 || h <= 0) return;
    if (thickness < 1) thickness = 1;
    int maxR = (w < h ? w : h) / 2;
    if (radius > maxR) radius = maxR;
    if (radius < 0) radius = 0;
    int iw = w - 2 * thickness, ih = h - 2 * thickness;
    int iR = radius - thickness;
    if (iR < 0) iR = 0;
    DWORD baseA = (argb >> 24) & 0xFF;
    double R = radius;
    int band = radius + thickness + 2;
    for (int y = 0; y < h; y++) {
        bool rowBand = (y < band) || (y >= h - band);
        for (int x = 0; x < w; x++) {
            if (!rowBand && x >= band && x < w - band) {
                x = w - band - 1;            // jump across the empty middle of the row
                continue;
            }
            double qx = fabs(x + 0.5 - w / 2.0) - (w / 2.0 - R);
            double qy = fabs(y + 0.5 - h / 2.0) - (h / 2.0 - R);
            double ax = qx > 0 ? qx : 0, ay = qy > 0 ? qy : 0;
            double corner = qx > qy ? qx : qy;
            if (corner > 0) corner = 0;
            double dOut = sqrt(ax * ax + ay * ay) + corner - R;
            double covOut = 0.5 - dOut;
            if (covOut <= 0) continue;
            if (covOut > 1) covOut = 1;
            double covIn = 0;
            if (iw > 0 && ih > 0) {
                double ix = x + 0.5 - thickness, iy = y + 0.5 - thickness;
                double jx = fabs(ix - iw / 2.0) - (iw / 2.0 - iR);
                double jy = fabs(iy - ih / 2.0) - (ih / 2.0 - iR);
                double bx = jx > 0 ? jx : 0, by = jy > 0 ? jy : 0;
                double inner = jx > jy ? jx : jy;
                if (inner > 0) inner = 0;
                double dIn = sqrt(bx * bx + by * by) + inner - iR;
                covIn = 0.5 - dIn;
                if (covIn < 0) covIn = 0;
                if (covIn > 1) covIn = 1;
            }
            double cov = covOut * (1.0 - covIn);
            if (cov <= 0) continue;
            DWORD a = (DWORD)(baseA * cov);
            if (!a) continue;
            SetPixelPremul(x, y, (a << 24) | (argb & 0x00FFFFFF));
        }
    }
}

// Same as FillRound, but each corner uses its own animated radius (TL, TR, BL, BR).
// `k` is the per-corner factor set: 1 = the full radius, 0 = square (the strip's is
// g_cornerAnim, a companion carries its own - task 3).
static int CornerRadiusAt(int x, int y, int w, int h, int radius);
static int CornerRadiusAtF(const float* k, int x, int y, int w, int h, int radius);

// Corner rounding is per corner (top-left, top-right, bottom-left, bottom-right):
// 1 = the configured radius, 0 = square. A window pushed against the screen edge
// squares off the corners on that edge only; the other edge keeps its rounding.
// The factors are animated (~120ms) so docking feels like the window settles into the
// edge instead of snapping to a new shape.
static float g_cornerAnim[4] = {1.0f, 1.0f, 1.0f, 1.0f};
static float g_cornerTarget[4] = {1.0f, 1.0f, 1.0f, 1.0f};

static void FillRound4F(const RECT& r, int radius, const float* k, DWORD argb);

static void FillRound4F(const RECT& r, int radius, const float* k, DWORD argb) {
    int w = r.right - r.left, h = r.bottom - r.top;
    if (w <= 0 || h <= 0) return;
    double cx = r.left + w / 2.0, cy = r.top + h / 2.0;
    double hw = w / 2.0, hh = h / 2.0;
    DWORD baseA = (argb >> 24) & 0xFF;
    for (int y = r.top; y < r.bottom; y++) {
        for (int x = r.left; x < r.right; x++) {
            int R = CornerRadiusAtF(k, x - r.left, y - r.top, w, h, radius);
            double qx = fabs(x + 0.5 - cx) - (hw - R);
            double qy = fabs(y + 0.5 - cy) - (hh - R);
            double ax = qx > 0 ? qx : 0;
            double ay = qy > 0 ? qy : 0;
            double inx = qx > qy ? qx : qy;
            if (inx > 0) inx = 0;
            double d = sqrt(ax * ax + ay * ay) + inx - R;
            double cov = 0.5 - d;
            if (cov <= 0) continue;
            if (cov > 1) cov = 1;
            DWORD a = (DWORD)(baseA * cov);
            if (!a) continue;
            SetPixelPremul(x, y, (a << 24) | (argb & 0x00FFFFFF));
        }
    }
}

static void FillRound4(const RECT& r, int radius, DWORD argb) {
    FillRound4F(r, radius, g_cornerAnim, argb);
}

static int RadiusForPercent(int w, int h, int percent) {
    int side = w < h ? w : h;
    int r = side * percent / 200;      // radius% of (short side / 2)
    if (r < 0) r = 0;
    if (r > side / 2) r = side / 2;
    return r;
}

static int RadiusFor(int w, int h) {
    return RadiusForPercent(w, h, g_cfg.radius);
}
// Corner rounding is per corner (top-left, top-right, bottom-left, bottom-right):
// 1 = the configured radius, 0 = square. A strip pushed against the screen edge
// squares off the corners on that edge only; the other edge keeps its rounding.
// The factors are animated (~120ms) so docking feels like the strip settles into the
// edge instead of snapping to a new shape. (The arrays themselves are declared above
// FillRound4F, which needs the strip's set.)

static int CornerIndex(int x, int y, int w, int h) {
    return (y * 2 < h) ? (x * 2 < w ? 0 : 1) : (x * 2 < w ? 2 : 3);
}

// Effective radius for one corner at (x,y), for any factor set.
static int CornerRadiusAtF(const float* k, int x, int y, int w, int h, int radius) {
    float f = k[CornerIndex(x, y, w, h)];
    if (f < 0) f = 0;
    if (f > 1) f = 1;
    return (int)(radius * f + 0.5f);
}

// Effective radius for one corner at (x,y), for the strip's own factors.
static int CornerRadiusAt(int x, int y, int w, int h, int radius) {
    return CornerRadiusAtF(g_cornerAnim, x, y, w, h, radius);
}

static RECT WorkAreaFor(HWND hwnd) {
    RECT wa{};
    MONITORINFO mi{sizeof(mi)};
    HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (mon && GetMonitorInfoW(mon, &mi)) return mi.rcWork;
    wa = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
    return wa;
}

// Per *strip* pixel masks for the glass body: rounded-corner coverage and the rim light.
// They depend only on the size, the radius and the corner animation, so they are built once
// and reused - the per-frame pass then needs no sqrt/fabs at all.
static std::vector<BYTE> g_covMask;      // 0..255 coverage
static std::vector<BYTE> g_rimMask;      // 0..255 extra white for the rim
static int g_maskW = 0, g_maskH = 0, g_maskRadius = -1;
static float g_maskAnim[4] = {-2, -2, -2, -2};

static void EnsureStripMasks(int w, int h, int baseRadius) {
    bool same = (w == g_maskW && h == g_maskH && baseRadius == g_maskRadius);
    for (int i = 0; same && i < 4; i++)
        if (g_cornerAnim[i] != g_maskAnim[i]) same = false;
    if (same) return;
    g_covMask.assign((size_t)w * h, 0);
    g_rimMask.assign((size_t)w * h, 0);
    double cx = w / 2.0, cy = h / 2.0, hw = w / 2.0, hh = h / 2.0;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            double rr = CornerRadiusAt(x, y, w, h, baseRadius);
            double qx = fabs(x + 0.5 - cx) - (hw - rr);
            double qy = fabs(y + 0.5 - cy) - (hh - rr);
            double ax = qx > 0 ? qx : 0;
            double ay = qy > 0 ? qy : 0;
            double inx = qx > qy ? qx : qy;
            if (inx > 0) inx = 0;
            double d = sqrt(ax * ax + ay * ay) + inx - rr;
            double cov = 0.5 - d;
            if (cov <= 0) continue;
            if (cov > 1) cov = 1;
            g_covMask[(size_t)y * w + x] = (BYTE)(cov * 255);
            if (d > -2.5) {
                double e = 1.0 + d / 2.5;           // 1 at the edge, 0 at 2.5 px in
                if (e > 0) {
                    DWORD ea = (DWORD)(e * cov * 0.22 * 255);
                    if (ea > 255) ea = 255;
                    g_rimMask[(size_t)y * w + x] = (BYTE)ea;
                }
            }
        }
    }
    g_maskW = w; g_maskH = h; g_maskRadius = baseRadius;
    for (int i = 0; i < 4; i++) g_maskAnim[i] = g_cornerAnim[i];
}

// Which corners should be square right now? Only the edge that is actually touching
// (or hanging over) the work area: the long side decides, so a wide strip squares off
// top or bottom and a tall one squares off left or right.
static void UpdateSnap() {
    if (!g_hwnd) return;
    RECT wr{};
    if (!GetWindowRect(g_hwnd, &wr)) return;
    RECT wa = WorkAreaFor(g_hwnd);
    bool vertical = (wr.bottom - wr.top) > (wr.right - wr.left);
    float t[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    // task 3: [dock] snap=0 = never square off (the corners keep the configured radius).
    if (g_cfg.snap) {
        if (vertical) {
            if (wr.left <= wa.left) { t[0] = 0.0f; t[2] = 0.0f; }      // left edge: TL + BL
            if (wr.right >= wa.right) { t[1] = 0.0f; t[3] = 0.0f; }    // right edge: TR + BR
        } else {
            if (wr.top <= wa.top) { t[0] = 0.0f; t[1] = 0.0f; }        // top edge: TL + TR
            if (wr.bottom >= wa.bottom) { t[2] = 0.0f; t[3] = 0.0f; }  // bottom edge: BL + BR
        }
    }
    for (int i = 0; i < 4; i++) g_cornerTarget[i] = t[i];
    static float last[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    if (last[0] != t[0] || last[1] != t[1] || last[2] != t[2] || last[3] != t[3]) {
        for (int i = 0; i < 4; i++) last[i] = t[i];
        DLog(L"snap: corners TL=%.0f TR=%.0f BL=%.0f BR=%.0f rect=%ld,%ld-%ld,%ld work=%ld,%ld-%ld,%ld",
             t[0], t[1], t[2], t[3], wr.left, wr.top, wr.right, wr.bottom, wa.left, wa.top,
             wa.right, wa.bottom);
    }
}

// One animation step; true when something moved (caller repaints).
static bool AnimateCorners() {
    static DWORD last = 0;
    DWORD now = GetTickCount();
    float dt = last ? (float)(now - last) : 30.0f;
    last = now;
    if (dt > 120.0f) dt = 120.0f;
    // exponential ease-out, ~120ms to settle
    float k = 1.0f - expf(-dt / 45.0f);
    bool moved = false;
    for (int i = 0; i < 4; i++) {
        float d = g_cornerTarget[i] - g_cornerAnim[i];
        if (d > -0.004f && d < 0.004f) {
            if (g_cornerAnim[i] != g_cornerTarget[i]) {
                g_cornerAnim[i] = g_cornerTarget[i];
                moved = true;
            }
            continue;
        }
        g_cornerAnim[i] += d * k;
        moved = true;
    }
    return moved;
}


struct Slot {
    RECT rc;
    int item;    // index into g_items; negative = one of the fixed buttons below
    int size = 0;    // drawn icon size (grows under the cursor)
};
// Fixed buttons that sit in the same row but outside the scrolling range. They are
// never grabbed by the reorder state machine and nothing can be dropped in front of
// them; their inner edge is a hard boundary for the icons (see Paint/WM_MOUSEMOVE).
static const int kSlotChevron = -1;   // "^": opens / closes the tray grid
static const int kSlotWin = -3;       // the Windows button: Start menu / Win+X menu
static std::vector<Slot> g_slots;
// per-slot hover magnification, 0 = normal, 1 = fully grown
// One grow/shrink animation per slot. The *duration* is fixed (hoverMs), so the number
// of visible steps is just "how often we repaint" - a faster panel refresh means a
// smoother zoom, not a faster one.
struct SlotAnim {
    float v = 0.0f;
    float from = 0.0f;
    float target = 0.0f;
    DWORD t0 = 0;
};
static std::vector<SlotAnim> g_slotHover;
static int g_iconCachePx = 0;

static int g_iconPx = 32;
static int g_capacity = 0;      // how many cells fit
static int g_pageItems = 1;     // how many items are visible at once (cells minus the
                                // two fixed buttons); used for wheel / edge scrolling
static int g_scroll = 0;        // first visible item
static bool g_reordering = false;   // dragging an icon to a new place in the row
static int g_reorderItem = -1;      // item being dragged
static int g_pressItem = -1;        // item under the button at press time (-1 = blank)
static bool g_expanded = false;
static RECT g_collapsedRect{};

static void SetPixelPremul(int x, int y, DWORD argb) {
    if (!g_paintBits || x < 0 || y < 0 || x >= g_paintW || y >= g_paintH) return;
    BYTE a = (BYTE)((argb >> 24) & 0xFF);
    BYTE r = (BYTE)(((argb >> 16) & 0xFF) * a / 255);
    BYTE g = (BYTE)(((argb >> 8) & 0xFF) * a / 255);
    BYTE b = (BYTE)((argb & 0xFF) * a / 255);
    BYTE* px = (BYTE*)g_paintBits + ((size_t)y * g_paintW + x) * 4;
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
// The shell renders the icon at exactly the requested size; that is the path
// launchers like Nexus use, and it stays sharp at any size.
// Largest frame that really exists in the file's icon resources. 0 = unknown
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

static void NormalizeIconSquare(std::vector<uint32_t>& v, int n) {
    if (n <= 0 || v.size() < (size_t)n * n) return;
    int x0 = n, y0 = n, x1 = -1, y1 = -1;
    // "content" = visible and not near-black: some providers pad the artwork
    // with an opaque black canvas, which an alpha-only test cannot trim
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++) {
            uint32_t c = v[(size_t)y * n + x];
            int a = (c >> 24) & 0xFF;
            int r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
            (void)r; (void)g; (void)b;
            if (a > 8) {
                if (x < x0) x0 = x;
                if (y < y0) y0 = y;
                if (x > x1) x1 = x;
                if (y > y1) y1 = y;
            }
        }
    if (x1 < x0 || y1 < y0) return;
    int cw = x1 - x0 + 1, ch = y1 - y0 + 1;
    if (cw > n * 3 / 4 && ch > n * 3 / 4) return;    // already fills the square

    double scale = (double)n / (cw > ch ? cw : ch);
    int dw = (int)(cw * scale), dh = (int)(ch * scale);
    if (dw < 1) dw = 1;
    if (dh < 1) dh = 1;
    std::vector<uint32_t> out((size_t)n * n, 0);
    int ox = (n - dw) / 2, oy = (n - dh) / 2;
    // bilinear on premultiplied values: nearest-neighbour sampling is what turned
    // small artwork (16-32 px tray / exe frames) into visible 2x2 pixel blocks
    for (int y = 0; y < dh; y++) {
        double fy = y0 + (y + 0.5) * ch / dh - 0.5;
        int syA = (int)floor(fy);
        double ty = fy - syA;
        if (syA < y0) { syA = y0; ty = 0; }
        int syB = syA + 1 > y1 ? y1 : syA + 1;
        for (int x = 0; x < dw; x++) {
            double fx = x0 + (x + 0.5) * cw / dw - 0.5;
            int sxA = (int)floor(fx);
            double tx = fx - sxA;
            if (sxA < x0) { sxA = x0; tx = 0; }
            int sxB = sxA + 1 > x1 ? x1 : sxA + 1;
            uint32_t p00 = v[(size_t)syA * n + sxA], p10 = v[(size_t)syA * n + sxB];
            uint32_t p01 = v[(size_t)syB * n + sxA], p11 = v[(size_t)syB * n + sxB];
            double w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty,
                   w11 = tx * ty;
            auto pm = [&](uint32_t c, int shift) {
                int a = (int)((c >> 24) & 0xFF);
                return ((c >> shift) & 0xFF) * a / 255.0;
            };
            auto mix = [&](int shift) {
                double s = pm(p00, shift) * w00 + pm(p10, shift) * w10 +
                           pm(p01, shift) * w01 + pm(p11, shift) * w11;
                int iv = (int)(s + 0.5);
                return iv < 0 ? 0 : (iv > 255 ? 255 : iv);
            };
            double a = ((p00 >> 24) & 0xFF) * w00 + ((p10 >> 24) & 0xFF) * w10 +
                       ((p01 >> 24) & 0xFF) * w01 + ((p11 >> 24) & 0xFF) * w11;
            int ia = (int)(a + 0.5);
            if (!ia) continue;
            out[(size_t)(oy + y) * n + (ox + x)] =
                (ia << 24) | (mix(16) << 16) | (mix(8) << 8) | mix(0);
        }
    }
    v.swap(out);
}

static bool FrameFills(HBITMAP bmp, int* outW, int* outH, double* coverage) {
    BITMAP bm{};
    GetObject(bmp, sizeof(bm), &bm);
    int w = bm.bmWidth, h = bm.bmHeight;
    if (w <= 0 || h <= 0) return false;
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    std::vector<uint32_t> buf((size_t)w * h);
    HDC dc = GetDC(nullptr);
    GetDIBits(dc, bmp, 0, h, buf.data(), &bi, DIB_RGB_COLORS);
    ReleaseDC(nullptr, dc);
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    long nonEmpty = 0;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
            if (((buf[(size_t)y * w + x] >> 24) & 0xFF) > 8) {
                nonEmpty++;
                if (x < x0) x0 = x;
                if (y < y0) y0 = y;
                if (x > x1) x1 = x;
                if (y > y1) y1 = y;
            }
    if (outW) *outW = w;
    if (outH) *outH = h;
    if (coverage) {
        double rw = (x1 >= x0) ? (double)(x1 - x0 + 1) / w : 0;
        double rh = (y1 >= y0) ? (double)(y1 - y0 + 1) / h : 0;
        *coverage = rw < rh ? rw : rh;
    }
    return true;
}

static void RenderIconCache(int px) {
    if (px <= 0 || px == g_cachedIconPx) return;
    g_cachedIconPx = px;

    for (auto& it : g_items) {
        it.px.clear();
        it.cachedPx = 0;
        if (!it.iconPath.empty()) {
            int real = MaxRealIconFrame(it.iconPath);
            // Always take the biggest real artwork (256 by default) and scale it
            // ourselves: never let the shell do the downscaling, and never ask
            // for more than the file actually contains.
            int want = 256;
            if (real > 0 && real < 256) want = real;
            HBITMAP shellBmp = ShellImageForPath(it.iconPath, want);
            if (shellBmp) {
                BITMAP bm{};
                GetObject(shellBmp, sizeof(bm), &bm);
                int bw = bm.bmWidth, bh = bm.bmHeight;
                if (bw > 0 && bh > 0) {
                    BITMAPINFO bi{};
                    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                    bi.bmiHeader.biWidth = bw;
                    bi.bmiHeader.biHeight = -bh;
                    bi.bmiHeader.biPlanes = 1;
                    bi.bmiHeader.biBitCount = 32;
                    bi.bmiHeader.biCompression = BI_RGB;
                    std::vector<uint32_t> src((size_t)bw * bh);
                    HDC dc = GetDC(nullptr);
                    GetDIBits(dc, shellBmp, 0, bh, src.data(), &bi, DIB_RGB_COLORS);
                    ReleaseDC(nullptr, dc);
                    it.px.assign((size_t)px * px, 0);
                    it.cachedPx = px;
                    int dst = px;
                    if (real > 0 && real < px && !g_cfg.upscaleSmallIcons) dst = real;
                    int ox = (px - dst) / 2, oy = (px - dst) / 2;
                    if (bw == dst && bh == dst) {
                        for (int y = 0; y < dst; y++)
                            memcpy(&it.px[(size_t)(oy + y) * px + ox], &src[(size_t)y * bw],
                                   (size_t)dst * 4);
                    } else {
                        for (int y = 0; y < dst; y++) {
                            int sy0 = y * bh / dst, sy1 = (y + 1) * bh / dst;
                            if (sy1 <= sy0) sy1 = sy0 + 1;
                            for (int x = 0; x < dst; x++) {
                                int sx0 = x * bw / dst, sx1 = (x + 1) * bw / dst;
                                if (sx1 <= sx0) sx1 = sx0 + 1;
                                uint32_t a = 0, r = 0, g = 0, b = 0;
                                int n = 0;
                                for (int sy = sy0; sy < sy1 && sy < bh; sy++)
                                    for (int sx = sx0; sx < sx1 && sx < bw; sx++) {
                                        uint32_t v = src[(size_t)sy * bw + sx];
                                        uint32_t sa = (v >> 24) & 0xFF;
                                        r += ((v >> 16) & 0xFF) * sa / 255;
                                        g += ((v >> 8) & 0xFF) * sa / 255;
                                        b += (v & 0xFF) * sa / 255;
                                        a += sa;
                                        n++;
                                    }
                                if (!n) continue;
                                it.px[(size_t)(oy + y) * px + (ox + x)] =
                                    ((a / n) << 24) | ((r / n) << 16) | ((g / n) << 8) | (b / n);
                            }
                        }
                    }
                    DeleteObject(shellBmp);
                    continue;
                }
                DeleteObject(shellBmp);
            }
        }

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

    // Last resort: rasterise the HICON ourselves so every item goes through the
    // same normalisation (DrawIconEx in Paint() bypassed it, which is why some
    // icons stayed "small artwork on a big canvas").
    int empty = 0;
    for (auto& it : g_items) {
        if (!it.px.empty()) continue;
        if (!it.icon) { empty++; continue; }
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = px;
        bi.bmiHeader.biHeight = -px;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        void* bits = nullptr;
        HDC dc = GetDC(nullptr);
        HBITMAP dib = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        HDC mdc = CreateCompatibleDC(dc);
        HGDIOBJ oldBmp = SelectObject(mdc, dib);
        memset(bits, 0, (size_t)px * px * 4);
        DrawIconEx(mdc, 0, 0, it.icon, px, px, 0, nullptr, DI_NORMAL);
        GetDIBits(dc, dib, 0, px, nullptr, &bi, DIB_RGB_COLORS);
        std::vector<uint32_t> buf((size_t)px * px);
        GetDIBits(dc, dib, 0, px, buf.data(), &bi, DIB_RGB_COLORS);
        SelectObject(mdc, oldBmp);
        DeleteObject(dib);
        DeleteDC(mdc);
        ReleaseDC(nullptr, dc);
        // force alpha: GDI leaves it at 0, make the drawn pixels opaque
        for (auto& v : buf) {
            if ((v & 0x00FFFFFF) || ((v >> 24) & 0xFF)) v |= 0xFF000000;
        }
        it.px.swap(buf);
        it.cachedPx = px;
    }

    // whatever produced the pixels, make the artwork fill the square
    for (auto& it : g_items)
        if (it.cachedPx == px) NormalizeIconSquare(it.px, px);

    DLog(L"iconcache px=%d items=%d noIcon=%d", px, (int)g_items.size(), empty);
}

// Publishes the flyout anchor rects to the Windhawk mod (defined further down).
static void PublishAnchors();
static void ArmWinXAnchor();      // marks "the Win+X popup about to appear is ours"

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
    // Two cells are always taken by fixed buttons: the Windows button in the first
    // cell and the chevron in the last one. Neither scrolls, so the items only get
    // whatever is left - that is why the visible item count is cap-2, not cap-1.
    bool needExpand = cap >= 2;
    int show = cap - 1 - (needExpand ? 1 : 0);
    if (show < 0) show = 0;

    if (g_scroll > n - show) g_scroll = n - show;
    if (g_scroll < 0) g_scroll = 0;

    g_iconPx = icon;
    g_capacity = cap;
    g_pageItems = show > 0 ? show : 1;

    g_iconBucket = 256;        // always cache from the 256px artwork
    // cache a little larger than the drawn size: the hover zoom then scales real
    // pixels down instead of blowing up a 1:1 bitmap
    int cachePx = (int)(icon * 1.45 + 0.5);
    if (cachePx < icon + 4) cachePx = icon + 4;
    g_iconCachePx = cachePx;
    RenderIconCache(cachePx);

    int visible = n - g_scroll;
    if (visible > show) visible = show;
    if (visible < 0) visible = 0;
    int cellCount = 1 + visible + (needExpand ? 1 : 0);
    if ((int)g_slotHover.size() != cellCount) g_slotHover.assign(cellCount, SlotAnim{});

    auto animK = [](int i) {
        if (i < 0 || i >= (int)g_slotHover.size()) return 0.0f;
        float k = g_slotHover[i].v;
        return k < 0 ? 0.0f : (k > 1 ? 1.0f : k);
    };
    // sizes first, then positions: the row stays centred while one icon grows
    const int winSize = (int)(icon * (1.0 + 0.34 * animK(0)) + 0.5);
    int total = winSize + gap;
    std::vector<int> sizes(visible, icon);
    for (int i = 0; i < visible; i++) {
        sizes[i] = (int)(icon * (1.0 + 0.34 * animK(1 + i)) + 0.5);
        total += sizes[i] + gap;
    }
    if (needExpand) total += icon + gap;
    total -= gap;
    if (total < 0) total = 0;
    int start = pad + (longSide - pad * 2 - total) / 2;
    int pos = start;
    {
        // the Windows button: permanently the first cell of the row, never scrolled
        Slot s;
        s.item = kSlotWin;
        s.size = winSize;
        int cross = pad + (shortSide - pad * 2 - winSize) / 2;
        if (vertical) s.rc = {cross, pos, cross + winSize, pos + winSize};
        else s.rc = {pos, cross, pos + winSize, cross + winSize};
        g_slots.push_back(s);
        pos += winSize + gap;
    }
    for (int i = 0; i < visible; i++) {
        int item = g_scroll + i;
        if (item >= n) break;
        if (g_reordering && item == g_reorderItem) {
            // the pressed icon follows the cursor: reserve its cell (the hole) but no slot
            pos += sizes[i] + gap;
            continue;
        }
        Slot s;
        s.item = item;
        s.size = sizes[i];
        int cross = pad + (shortSide - pad * 2 - s.size) / 2;
        if (vertical) s.rc = {cross, pos, cross + s.size, pos + s.size};
        else s.rc = {pos, cross, pos + s.size, cross + s.size};
        g_slots.push_back(s);
        if (g_reordering) {
            g_items[item].targetX = vertical ? s.rc.top : s.rc.left;
            if (g_items[item].animX < -1e8f) g_items[item].animX = (float)g_items[item].targetX;
        }
        pos += s.size + gap;
    }
    if (needExpand) {
        Slot s;
        s.item = kSlotChevron;
        s.size = icon;
        int cross = pad + (shortSide - pad * 2 - s.size) / 2;
        if (vertical) s.rc = {cross, pos, cross + s.size, pos + s.size};
        else s.rc = {pos, cross, pos + s.size, cross + s.size};
        g_slots.push_back(s);
    }
    // One line whenever the geometry changes: which cells exist and where the two fixed
    // buttons are. Probing a slot from a script needs this instead of re-deriving the
    // centred row (and the hover zoom moves it all the time anyway).
    PublishAnchors();      // the shell flyouts anchor on those same rects (see below)
    {
        static int lastCap = -1, lastShow = -1, lastCells = -1, lastScroll = -1;
        if (cap != lastCap || show != lastShow || cellCount != lastCells ||
            g_scroll != lastScroll) {
            lastCap = cap;
            lastShow = show;
            lastCells = cellCount;
            lastScroll = g_scroll;
            const Slot& w0 = g_slots.front();
            RECT ch{};
            for (const Slot& s : g_slots)
                if (s.item == kSlotChevron) ch = s.rc;
            DLog(L"layout: cap=%d show=%d cells=%d scroll=%d items=%d win=%d,%d-%d,%d "
                 L"chevron=%d,%d-%d,%d icon=%d",
                 cap, show, cellCount, g_scroll, n, (int)w0.rc.left, (int)w0.rc.top,
                 (int)w0.rc.right, (int)w0.rc.bottom, (int)ch.left, (int)ch.top,
                 (int)ch.right, (int)ch.bottom, icon);
        }
    }
}

// The Windows logo for the fixed first button: four rounded squares, drawn by hand.
// Windows 11 paints its Start glyph with XAML inside the taskbar, so there is no icon
// resource to load; rasterising it here keeps it crisp at any hover zoom and needs no
// asset next to the exe. Colour matches the "^" chevron (white), so both fixed buttons
// read the same against any wallpaper.
static void PaintWinButton(const RECT& rc, int size) {
    if (size < 10) return;
    // A layered window is hit-tested through its alpha channel, so the gap between the
    // four squares would be a hole the click falls through - right in the middle of the
    // button, where people aim. This faint wash (4% white, invisible against any
    // wallpaper) makes the whole button clickable and keeps its rounded outline.
    FillRound(g_memDC, rc, RadiusFor(rc.right - rc.left, rc.bottom - rc.top) / 2 + 2,
              0x0AFFFFFF);
    // the glyph spans ~92% of the button, split 2x2 with a ~9% gap (Fluent logo metrics);
    // corners are only slightly rounded - too much radius melts the four squares into one
    int span = (int)(size * 0.92f + 0.5f);
    int gap = (int)(span * 0.09f + 0.5f);
    int sq = (span - gap) / 2;
    if (sq < 4) return;
    int x0 = (rc.left + rc.right) / 2 - span / 2;
    int y0 = (rc.top + rc.bottom) / 2 - span / 2;
    int rad = sq / 7;
    if (rad < 1) rad = 1;
    const DWORD col = 0xF0FFFFFF;
    for (int iy = 0; iy < 2; iy++)
        for (int ix = 0; ix < 2; ix++) {
            int x = x0 + ix * (sq + gap);
            int y = y0 + iy * (sq + gap);
            FillRound(g_memDC, RECT{x, y, x + sq, y + sq}, rad, col);
        }
}

// ---- H3: picture backgrounds (bgMode = image) ------------------------------------------
// The bake's blur lives further down the file; the composition here reuses it
static void BoxBlurSmall(std::vector<uint32_t>& v, int w, int h, int radius);
static void SaveBmp(const wchar_t* name, const uint32_t* px, int w, int h);   // diagnostics

// Sliding-window box blur: O(1) per pixel instead of O(radius).
// BoxBlurSmall() re-sums 2r+1 taps for every pixel, which is fine for a 200x60 bake but was 10 of
// the 12 ms it took to compose one picture-background frame (radius 12, 71k px, two passes, twice).
// Edges are extended by clamping, so the result is the same shape as BoxBlurSmall's.
static void BoxBlurFast(std::vector<uint32_t>& v, int w, int h, int radius) {
    if (radius <= 0 || w <= 0 || h <= 0) return;
    std::vector<uint32_t> tmp((size_t)w * h);
    const long long span = 2 * radius + 1;
    for (int y = 0; y < h; y++) {
        const uint32_t* row = &v[(size_t)y * w];
        long long r = 0, g = 0, b = 0;
        for (int k = -radius; k <= radius; k++) {
            int x = k < 0 ? 0 : (k >= w ? w - 1 : k);
            uint32_t c = row[x];
            b += c & 0xFF; g += (c >> 8) & 0xFF; r += (c >> 16) & 0xFF;
        }
        for (int x = 0; x < w; x++) {
            tmp[(size_t)y * w + x] = ((uint32_t)(r / span) << 16) | ((uint32_t)(g / span) << 8) |
                                     (uint32_t)(b / span) | 0xFF000000u;
            int xo = x - radius; if (xo < 0) xo = 0;
            int xi = x + radius + 1; if (xi >= w) xi = w - 1;
            uint32_t co = row[xo], ci = row[xi];
            b += (long long)(ci & 0xFF) - (co & 0xFF);
            g += (long long)((ci >> 8) & 0xFF) - ((co >> 8) & 0xFF);
            r += (long long)((ci >> 16) & 0xFF) - ((co >> 16) & 0xFF);
        }
    }
    for (int x = 0; x < w; x++) {
        long long r = 0, g = 0, b = 0;
        for (int k = -radius; k <= radius; k++) {
            int y = k < 0 ? 0 : (k >= h ? h - 1 : k);
            uint32_t c = tmp[(size_t)y * w + x];
            b += c & 0xFF; g += (c >> 8) & 0xFF; r += (c >> 16) & 0xFF;
        }
        for (int y = 0; y < h; y++) {
            v[(size_t)y * w + x] = ((uint32_t)(r / span) << 16) | ((uint32_t)(g / span) << 8) |
                                   (uint32_t)(b / span) | 0xFF000000u;
            int yo = y - radius; if (yo < 0) yo = 0;
            int yi = y + radius + 1; if (yi >= h) yi = h - 1;
            uint32_t co = tmp[(size_t)yo * w + x], ci = tmp[(size_t)yi * w + x];
            b += (long long)(ci & 0xFF) - (co & 0xFF);
            g += (long long)((ci >> 8) & 0xFF) - ((co >> 8) & 0xFF);
            r += (long long)((ci >> 16) & 0xFF) - ((co >> 16) & 0xFF);
        }
    }
}
// A picture is decoded once per (path, size) and cached: decoding a 4K PNG on every repaint would
// cost tens of milliseconds. It is scaled to *cover* the window - aspect ratio kept, the overflow
// cropped, centred - which is what a wallpaper-like background is supposed to look like.
// The glass layer over a picture is "tint only", no blur: a photo is smooth already, and blurring
// it would cost a whole bake for nothing anyone can see (PLAN_COMPONENTS.md §3.4 A10).
struct ImageBg {
    std::wstring path;
    int w = 0, h = 0;
    std::vector<uint32_t> px;      // opaque 0xAARRGGBB, already cover-scaled
    bool ok = false;
    DWORD at = 0;
    // The composition bakes in the glass *blur* (it is applied to the sharp layer), so a change of
    // glassLayer / blurRadius has to invalidate the cache - otherwise moving the slider does
    // nothing until the window is resized (bug, 2026-11-21).
    DWORD sig = 1;
};

static DWORD ImageSig(int which) {
    return (DWORD)((g_cfg.glassLayer ? 1u : 0u) |
                   ((DWORD)(g_glass[which & 1].blurRadius & 0xFF) << 8));
}

static std::wstring ImagePathFor(const wchar_t* section) {
    std::vector<wchar_t> b(MAX_PATH * 2, 0);
    GetPrivateProfileStringW(section, L"image", L"", b.data(), (DWORD)b.size(), g_iniPath.c_str());
    std::wstring p = b.data();
    if (p.empty() && wcscmp(section, L"dock") != 0) {
        // [traybar] has no picture of its own -> inherit the strip's, like every other style key
        GetPrivateProfileStringW(L"dock", L"image", L"", b.data(), (DWORD)b.size(),
                                 g_iniPath.c_str());
        p = b.data();
    }
    return p;
}

// Decode cache: one WIC decode per *picture*, not per size.
// A 4096x2386 JPEG costs ~10 ms to decode, and a window resize recomposes the picture on every
// size change - decoding there made a resize-drag stutter. The composition never needs more than a
// few hundred pixels, so the picture is decoded once and kept downscaled (long side <= 640);
// composing a new window size is then a couple of milliseconds of sampling.
static const int kImageSrcMax = 1024;
struct ImageSrc {
    std::wstring path;
    int w = 0, h = 0;
    std::vector<uint32_t> px;      // opaque 0xAARRGGBB, downscaled
    bool ok = false;
};
// One slot per glass window: the strip and the float window may use different pictures.
static ImageSrc g_imgSrc[2];
static int g_imgSrcNext = 0;

static bool EnsureImageSrc(const std::wstring& path, ImageSrc** out) {
    for (ImageSrc& s : g_imgSrc) {
        if (s.ok && s.path == path) {
            *out = &s;
            return true;
        }
    }
    ImageSrc& slot = g_imgSrc[g_imgSrcNext];
    g_imgSrcNext = (g_imgSrcNext + 1) % 2;
    slot.ok = false;
    slot.path.clear();
    slot.px.clear();
    slot.w = slot.h = 0;

    const double t0 = NowMs();
    IWICImagingFactory* fac = nullptr;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IWICImagingFactory, (void**)&fac))) {
        DLog(L"image: WIC factory unavailable - picture backgrounds are off");
        return false;
    }
    IWICBitmapDecoder* dec = nullptr;
    IWICBitmapFrameDecode* frame = nullptr;
    IWICFormatConverter* conv = nullptr;
    UINT sw = 0, sh = 0;
    std::vector<uint32_t> src;
    bool ok = false;
    if (SUCCEEDED(fac->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ,
                                                 WICDecodeMetadataCacheOnDemand, &dec)) &&
        SUCCEEDED(dec->GetFrame(0, &frame)) && SUCCEEDED(frame->GetSize(&sw, &sh)) &&
        SUCCEEDED(fac->CreateFormatConverter(&conv)) &&
        SUCCEEDED(conv->Initialize(frame, GUID_WICPixelFormat32bppBGR, WICBitmapDitherTypeNone,
                                   nullptr, 0, WICBitmapPaletteTypeCustom)) &&
        sw > 0 && sh > 0) {
        src.resize((size_t)sw * sh);
        ok = SUCCEEDED(conv->CopyPixels(nullptr, sw * 4, (UINT)src.size() * 4,
                                        (BYTE*)src.data()));
    }
    if (conv) conv->Release();
    if (frame) frame->Release();
    if (dec) dec->Release();
    fac->Release();
    if (!ok) {
        DLog(L"image: cannot decode %s", path.c_str());
        return false;
    }
    // downscale so the long side is at most kImageSrcMax (bilinear, aspect kept)
    const int longSide = sw > sh ? (int)sw : (int)sh;
    const double k = longSide > kImageSrcMax ? (double)kImageSrcMax / longSide : 1.0;
    const int dw = (int)(sw * k + 0.5) > 0 ? (int)(sw * k + 0.5) : 1;
    const int dh = (int)(sh * k + 0.5) > 0 ? (int)(sh * k + 0.5) : 1;
    slot.px.resize((size_t)dw * dh);
    for (int y = 0; y < dh; y++) {
        double fy = (y + 0.5) * sh / dh - 0.5;
        int y0 = (int)floor(fy);
        double ty = fy - y0;
        if (y0 < 0) { y0 = 0; ty = 0; }
        int y1 = y0 + 1 < (int)sh ? y0 + 1 : (int)sh - 1;
        for (int x = 0; x < dw; x++) {
            double fx = (x + 0.5) * sw / dw - 0.5;
            int x0 = (int)floor(fx);
            double tx = fx - x0;
            if (x0 < 0) { x0 = 0; tx = 0; }
            int x1 = x0 + 1 < (int)sw ? x0 + 1 : (int)sw - 1;
            uint32_t p00 = src[(size_t)y0 * sw + x0], p10 = src[(size_t)y0 * sw + x1];
            uint32_t p01 = src[(size_t)y1 * sw + x0], p11 = src[(size_t)y1 * sw + x1];
            const double w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty);
            const double w01 = (1 - tx) * ty, w11 = tx * ty;
            auto ch = [&](int shift) {
                double v = (p00 >> shift & 0xFF) * w00 + (p10 >> shift & 0xFF) * w10 +
                           (p01 >> shift & 0xFF) * w01 + (p11 >> shift & 0xFF) * w11;
                int iv = (int)(v + 0.5);
                return (uint32_t)(iv < 0 ? 0 : (iv > 255 ? 255 : iv));
            };
            slot.px[(size_t)y * dw + x] = 0xFF000000u | (ch(16) << 16) | (ch(8) << 8) | ch(0);
        }
    }
    slot.path = path;
    slot.w = dw;
    slot.h = dh;
    slot.ok = true;
    DLog(L"image: decoded %s (%ux%u -> %dx%d) in %.1f ms", path.c_str(), sw, sh, dw, dh,
         NowMs() - t0);
    *out = &slot;
    return true;
}

static bool LoadImageCover(ImageBg& im, const std::wstring& path, int w, int h, int which) {
    im.ok = false;
    // Remember what was asked for even when it fails: EnsureImage() must not retry a broken path
    // on every single repaint (a 4K decode attempt per frame is not a debugging aid).
    im.path = path;
    im.w = w;
    im.h = h;
    im.px.clear();
    if (path.empty() || w <= 0 || h <= 0) return false;
    // decode cache first: a new window size must not decode the JPEG again
    ImageSrc* cached = nullptr;
    if (!EnsureImageSrc(path, &cached)) return false;
    if (cached->w <= 0 || cached->h <= 0) return false;
    const uint32_t* src = cached->px.data();
    const int sw = cached->w, sh = cached->h;
    // ---- composition (user spec 2026-11-21) ---------------------------------------------
    // One picture, two layers:
    //   * the whole window is the same picture, cover-scaled, blurred, desaturated and tinted with
    //     its own dominant colour (so the left side is a natural continuation, never a hard edge);
    //   * the *sharp* picture sits against the right edge, scaled so its short side matches the
    //     window's short side, with its left edge feathered into the backdrop.
    // Everything here is a pure function of (picture, window size), so it is cached in `im` and a
    // repaint is just a masked blit - the cost only appears when the size (or the picture) changes.
    const double tComp0 = NowMs();

    // 1. backdrop: cover-scale (fills the window, overflow cropped symmetrically)
    const double sx = (double)w / sw, sy = (double)h / sh;
    const double sc = sx > sy ? sx : sy;
    const double cropW = w / sc, cropH = h / sc;
    const double ox = (sw - cropW) / 2.0, oy = (sh - cropH) / 2.0;
    std::vector<uint32_t> back((size_t)w * h);
    for (int y = 0; y < h; y++) {
        double fy = oy + (y + 0.5) * cropH / h - 0.5;
        int y0 = (int)floor(fy);
        double ty = fy - y0;
        int y1 = y0 + 1;
        if (y0 < 0) { y0 = 0; ty = 0; }
        if (y1 >= (int)sh) y1 = (int)sh - 1;
        for (int x = 0; x < w; x++) {
            double fx = ox + (x + 0.5) * cropW / w - 0.5;
            int x0 = (int)floor(fx);
            double tx = fx - x0;
            int x1 = x0 + 1;
            if (x0 < 0) { x0 = 0; tx = 0; }
            if (x1 >= (int)sw) x1 = (int)sw - 1;
            uint32_t p00 = src[(size_t)y0 * sw + x0], p10 = src[(size_t)y0 * sw + x1];
            uint32_t p01 = src[(size_t)y1 * sw + x0], p11 = src[(size_t)y1 * sw + x1];
            const double w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty);
            const double w01 = (1 - tx) * ty, w11 = tx * ty;
            auto ch = [&](int shift) {
                double v = (p00 >> shift & 0xFF) * w00 + (p10 >> shift & 0xFF) * w10 +
                           (p01 >> shift & 0xFF) * w01 + (p11 >> shift & 0xFF) * w11;
                int iv = (int)(v + 0.5);
                return (uint32_t)(iv < 0 ? 0 : (iv > 255 ? 255 : iv));
            };
            back[(size_t)y * w + x] = 0xFF000000u | (ch(16) << 16) | (ch(8) << 8) | ch(0);
        }
    }

    // 2. blur + desaturate + slight dim, so the sharp half clearly reads as "in front".
    // The backdrop is meant to be the "big blurred copy" (大模糊) - min(w,h)/8 measured only ~9 px
    // on a 76 px tall strip, which is so mild that the sharp half did not stand out at all
    // (user, 2026-11-21: "压根没有渲染清晰图部分"). A third of the short side reads as blur.
    {
        int radius = (w < h ? w : h) / 3;
        if (radius < 8) radius = 8;
        if (radius > 48) radius = 48;
        BoxBlurFast(back, w, h, radius);
        BoxBlurFast(back, w, h, radius);
        for (auto& v : back) {
            double rd = (v >> 16) & 0xFF, gn = (v >> 8) & 0xFF, bl = v & 0xFF;
            const double lum = rd * 0.2126 + gn * 0.7152 + bl * 0.0722;
            rd = (rd * 0.55 + lum * 0.45) * 0.94;
            gn = (gn * 0.55 + lum * 0.45) * 0.94;
            bl = (bl * 0.55 + lum * 0.45) * 0.94;
            v = 0xFF000000u | ((DWORD)rd << 16) | ((DWORD)gn << 8) | (DWORD)bl;
        }
    }

    // 3. dominant colour (mean of the source, cheap: every 4th pixel), laid over the backdrop as a
    //    horizontal gradient that dies out before the middle - the "colour continuation" on the left
    DWORD domR = 0, domG = 0, domB = 0;
    {
        long long r = 0, g = 0, b = 0, n = 0;
        for (size_t i = 0, nSrc = (size_t)sw * sh; i < nSrc; i += 4) {
            uint32_t c = src[i];
            r += (c >> 16) & 0xFF;
            g += (c >> 8) & 0xFF;
            b += c & 0xFF;
            n++;
        }
        if (n) { domR = (DWORD)(r / n); domG = (DWORD)(g / n); domB = (DWORD)(b / n); }
    }

    // 4. sharp picture against the anchor edge, short side == window short side.
    //    Landscape (w >= h): anchored right, blurred continuation on the left.
    //    Portrait  (h >  w): the same layout rotated 90 degrees counter-clockwise - the picture
    //    fills the top and the blur continues downwards (user, 2026-11-21).
    const bool portrait = h > w;
    const int winShort = w < h ? w : h;
    const int imgShort = sw < sh ? (int)sw : (int)sh;
    const double scale = imgShort > 0 ? (double)winShort / imgShort : 1.0;
    int sharpW = (int)(sw * scale + 0.5), sharpH = (int)(sh * scale + 0.5);
    if (sharpW < 1) sharpW = 1;
    if (sharpH < 1) sharpH = 1;
    const int dx = portrait ? (w - sharpW) / 2 : (w - sharpW);   // centred / against the right edge
    const int dy = portrait ? 0 : (h - sharpH) / 2;              // against the top / centred
    int feather = (portrait ? sharpH : sharpW) / 3;
    if (feather > 140) feather = 140;
    if (feather < 20) feather = 20;

    im.px.resize((size_t)w * h);
    // Render the sharp layer on its own first: this is where the glass "background blur radius"
    // now applies - it blurs the *sharp picture*, while the backdrop keeps its own big blur and
    // must not be blurred a second time (user, 2026-11-21).
    std::vector<uint32_t> sharp((size_t)sharpW * sharpH);
    {
        // ⛔ A big picture shown small with *one* bilinear tap per output pixel averages only 4
        // texels out of a much bigger footprint - that is the "sharp picture looks shrunk-too-small
        // / soft" report (2026-11-21), not a blur. Average the whole footprint: k x k samples,
        // k = the reduction factor (1 = the plain bilinear case when the window is bigger than the
        // cached picture).
        int k = (int)(1.0 / scale + 0.5);
        if (k < 1) k = 1;
        if (k > 6) k = 6;      // 3 undersampled a 8x reduction and softened the "sharp" half
        auto sampleAt = [&](double fsx, double fsy, int shift) {
            if (fsx < 0) fsx = 0;
            if (fsy < 0) fsy = 0;
            if (fsx > (double)sw - 1) fsx = (double)sw - 1;
            if (fsy > (double)sh - 1) fsy = (double)sh - 1;
            int x0 = (int)fsx, y0 = (int)fsy;
            double tx = fsx - x0, ty = fsy - y0;
            int x1 = x0 + 1 < (int)sw ? x0 + 1 : (int)sw - 1;
            int y1 = y0 + 1 < (int)sh ? y0 + 1 : (int)sh - 1;
            return ((src[(size_t)y0 * sw + x0] >> shift) & 0xFF) * (1 - tx) * (1 - ty) +
                   ((src[(size_t)y0 * sw + x1] >> shift) & 0xFF) * tx * (1 - ty) +
                   ((src[(size_t)y1 * sw + x0] >> shift) & 0xFF) * (1 - tx) * ty +
                   ((src[(size_t)y1 * sw + x1] >> shift) & 0xFF) * tx * ty;
        };
        for (int py = 0; py < sharpH; py++) {
            for (int px2 = 0; px2 < sharpW; px2++) {
                auto ch = [&](int shift) {
                    double sum = 0;
                    for (int j = 0; j < k; j++)
                        for (int i = 0; i < k; i++)
                            sum += sampleAt((px2 + (i + 0.5) / k) / scale - 0.5,
                                            (py + (j + 0.5) / k) / scale - 0.5, shift);
                    int v = (int)(sum / (k * k) + 0.5);
                    return (DWORD)(v < 0 ? 0 : (v > 255 ? 255 : v));
                };
                sharp[(size_t)py * sharpW + px2] =
                    0xFF000000u | (ch(16) << 16) | (ch(8) << 8) | ch(0);
            }
        }
        // ⛔ Only the *glass layer* blurs the sharp picture. With the glass material off the picture
        // must stay sharp - applying the radius regardless made the sharp half disappear at any
        // larger setting (bug, 2026-11-21).
        // The radius is a full-resolution number (36 on this profile); on a 76 px tall layer that
        // is a complete wipe, so it is capped to an eighth of the short side - enough to read as
        // "softened by the glass", far from destroying the picture.
        if (g_cfg.glassLayer != 0 && g_glass[which & 1].blurRadius > 0 && sharpW > 8 && sharpH > 8) {
            int cap = (sharpW < sharpH ? sharpW : sharpH) / 8;
            if (cap < 2) cap = 2;
            int rb = g_glass[which & 1].blurRadius;
            if (rb > cap) rb = cap;
            BoxBlurFast(sharp, sharpW, sharpH, rb);
            BoxBlurFast(sharp, sharpW, sharpH, rb);
        }
    }

    // "far" = the edge on the opposite side of the sharp picture; the gradient is strongest there
    const int farLen = portrait ? h : w;
    const double gradEnd = farLen * 0.55;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint32_t c = back[(size_t)y * w + x];
            const int farPos = portrait ? (h - 1 - y) : x;
            if (farPos < gradEnd) {
                double k = 0.45 * (1.0 - farPos / gradEnd);
                double rd = (c >> 16) & 0xFF, gn = (c >> 8) & 0xFF, bl = c & 0xFF;
                rd = rd * (1 - k) + domR * k;
                gn = gn * (1 - k) + domG * k;
                bl = bl * (1 - k) + domB * k;
                c = 0xFF000000u | ((DWORD)rd << 16) | ((DWORD)gn << 8) | (DWORD)bl;
            }
            // sharp layer, feathered on its inner edge
            const int px2 = x - dx, py = y - dy;
            if (px2 >= 0 && px2 < sharpW && py >= 0 && py < sharpH) {
                const int inner = portrait ? (sharpH - 1 - py) : px2;
                double a = 1.0;
                if (inner < feather) a = (inner + 0.5) / feather;
                uint32_t s = sharp[(size_t)py * sharpW + px2];
                double rd = (c >> 16) & 0xFF, gn = (c >> 8) & 0xFF, bl = c & 0xFF;
                rd = rd * (1 - a) + ((s >> 16) & 0xFF) * a;
                gn = gn * (1 - a) + ((s >> 8) & 0xFF) * a;
                bl = bl * (1 - a) + (s & 0xFF) * a;
                c = 0xFF000000u | ((DWORD)rd << 16) | ((DWORD)gn << 8) | (DWORD)bl;
            }
            im.px[(size_t)y * w + x] = c;
        }
    }

    im.path = path;
    im.w = w;
    im.h = h;
    im.ok = true;
    im.at = GetTickCount();
    im.sig = ImageSig(which);
    DLog(L"image: composed %s (%ux%u -> %dx%d, sharp %dx%d at %d,%d, feather %d) in %.1f ms",
         path.c_str(), sw, sh, w, h, sharpW, sharpH, dx, dy, feather, NowMs() - tComp0);
    if (g_cfg.dumpBake) {
        // diagnostic: the composed picture on its own, without icons on top
        wchar_t name[128]{};
        swprintf_s(name, L"dock_img_%dx%d.bmp", w, h);
        SaveBmp(name, im.px.data(), w, h);
    }
    return true;
}

// Load on demand, and reload when the path or the window size changed.
static bool EnsureImage(ImageBg& im, const std::wstring& path, int w, int h, int which) {
    if (im.ok && im.w == w && im.h == h && im.path == path && im.sig == ImageSig(which)) return true;
    return LoadImageCover(im, path, w, h, which);
}

// One cached picture per glass-capable window (the strip and the float window may differ).
static ImageBg g_imgStrip, g_imgTray;

// Paint the picture into the current paint target (g_paintBits) through the given coverage/rim
// masks, with the glass layer's tint applied when it is on. Same maths as the baked glass (lift +
// tint mix) so a picture background and a "behind" background look like the same material.
static void PaintImageBg(const ImageBg& im, int dstW, int dstH, const BYTE* cov, const BYTE* rim,
                         DWORD hueRgb, const GlassCfg& gc) {
    if (!im.ok || !g_paintBits) return;
    const bool glass = g_cfg.glassLayer != 0;
    const double tintK = glass ? gc.tintStrength / 255.0 : 0.0;
    // The whole background layer takes the glass opacity as its alpha (user, 2026-11-21): the
    // icons are drawn afterwards into the same DIB, so they stay fully opaque.
    const double layerA = glass ? gc.glassOpacity / 255.0 : 1.0;
    const DWORD tr = (hueRgb >> 16) & 0xFF, tg = (hueRgb >> 8) & 0xFF, tb = hueRgb & 0xFF;
    for (int y = 0; y < dstH && y < im.h; y++) {
        const uint32_t* srcRow = &im.px[(size_t)y * im.w];
        const BYTE* covRow = cov ? cov + (size_t)y * dstW : nullptr;
        const BYTE* rimRow = rim ? rim + (size_t)y * dstW : nullptr;
        for (int x = 0; x < dstW && x < im.w; x++) {
            const DWORD a = covRow ? covRow[x] : 255;
            if (!a) continue;
            uint32_t v = srcRow[x];
            double rd = (v >> 16) & 0xFF, gn = (v >> 8) & 0xFF, bl = v & 0xFF;
            if (tintK > 0) {
                const double lum = rd * 0.2126 + gn * 0.7152 + bl * 0.0722;
                const double lift = (128.0 - lum) * 0.16;
                rd += lift; gn += lift; bl += lift;
                if (rd < 0) rd = 0; if (rd > 255) rd = 255;
                if (gn < 0) gn = 0; if (gn > 255) gn = 255;
                if (bl < 0) bl = 0; if (bl > 255) bl = 255;
                rd = rd * (1 - tintK) + tr * tintK;
                gn = gn * (1 - tintK) + tg * tintK;
                bl = bl * (1 - tintK) + tb * tintK;
            }
            SetPixelPremul(x, y, ((DWORD)(a * layerA) << 24) | ((DWORD)rd << 16) | ((DWORD)gn << 8) |
                                     (DWORD)bl);
            const DWORD ea = rimRow ? rimRow[x] : 0;
            if (ea) SetPixelPremul(x, y, ((DWORD)(ea * layerA) << 24) | 0x00FFFFFF);
        }
    }
}

// Paint the strip's picture background; false = no usable picture (caller falls back).
static bool DrawImageBgStrip(int w, int h) {
    if (!EnsureImage(g_imgStrip, ImagePathFor(L"dock"), w, h, 0)) return false;
    EnsureStripMasks(w, h, RadiusFor(w, h));
    PaintImageBg(g_imgStrip, w, h, g_covMask.data(), g_rimMask.data(), g_hue[0], g_glass[0]);
    return true;
}

static void Paint(int w, int h) {
    LARGE_INTEGER q0{}, q1{}, q2{};
    QueryPerformanceCounter(&q0);
    EnsureDib(w, h);
    // glassOpacity = tintStrength = 0 means "no glass": the composite would only be a
    // frozen copy of the backdrop, so skip the capture and the per-pixel pass and let the
    // real desktop show through.
    const bool noGlass = (g_glass[0].glassOpacity == 0 && g_glass[0].tintStrength == 0);
    if (g_cfg.material == 1 && g_bakeDirty && !noGlass) {
        CaptureBackdrop();
        g_glassCacheValid = false;
    }
    SetStretchBltMode(g_memDC, HALFTONE);
    SetBrushOrgEx(g_memDC, 0, 0, nullptr);
    memset(g_bits, 0, (size_t)w * h * 4);
    RECT all{0, 0, w, h};
    {
        static int logged = 0;
        if (logged < 5) {
            logged++;
            DLog(L"paint: material=%d bake=%p bakeW=%d bakeH=%d w=%d h=%d op=%d tint=%d blur=%d",
                 g_cfg.material, g_stripGlass.bits, g_stripGlass.w, g_stripGlass.h, w, h,
                 g_glass[0].glassOpacity, g_glass[0].tintStrength, g_glass[0].blurRadius);
        }
    }
    // The glass depends on *where* the strip currently sits inside the padded bake, so
    // that offset is part of the cache key. Without it a moving strip kept reusing the
    // picture rendered for its old position - the backdrop slid along with the window.
    RECT wrNow{};
    if (g_renderPos.x != INT_MIN) {
        wrNow = RECT{g_renderPos.x, g_renderPos.y, g_renderPos.x + w, g_renderPos.y + h};
    } else {
        GetWindowRect(g_hwnd, &wrNow);
    }
    const int pw = g_stripGlass.w, ph = g_stripGlass.h;
    int ox = wrNow.left - g_stripGlass.origin.x;
    int oy = wrNow.top - g_stripGlass.origin.y;
    if (pw >= w) {
        if (ox < 0) ox = 0;
        if (ox > pw - w) ox = pw - w;
    }
    if (ph >= h) {
        if (oy < 0) oy = 0;
        if (oy > ph - h) oy = ph - h;
    }
    bool glassHit = !noGlass && g_glassCacheValid && g_glassCacheW == w &&
                    g_glassCacheH == h && (int)g_glassCache.size() == w * h &&
                    g_glassCacheOx == ox && g_glassCacheOy == oy;
    if (glassHit) {
        memcpy(g_bits, g_glassCache.data(), (size_t)w * h * 4);
    } else if (g_cfg.bgMode == 1 && DrawImageBgStrip(w, h)) {
        // H3: picture background (tint applied inside when the glass layer is on)
    } else if (noGlass || g_cfg.bgMode == 2) {
        // H2b: a solid background paints a real slab here; with "behind" (bgMode = 0) and no
        // glass there is nothing to draw and the icons are the whole strip.
        if (g_cfg.bgMode == 2) {
            int a = g_cfg.solidOpacity;
            if (a < 3) a = 3;
            if (a > 255) a = 255;
            FillRound(g_memDC, RECT{0, 0, w, h}, RadiusForPercent(w, h, g_cfg.radius),
                      ((DWORD)a << 24) | (g_hue[0] & 0x00FFFFFFu));
        }
    } else {
    if (g_cfg.material == 1 && g_stripGlass.bits && g_stripGlass.w >= w &&
        g_stripGlass.h >= h) {
        // baked blur + configurable tint, with a sub-pixel coverage edge so the
        // corners are smooth (no 1-bit region mask)
        double cx = w / 2.0, cy = h / 2.0;
        double hw = w / 2.0, hh = h / 2.0;
        int baseRadius = RadiusFor(w, h);
        // out = glass * a + backdrop * (1 - a), where
        //   glass = blurred * (1 - t) + tint * t
        // The (1 - a) part is free: it is simply DWM showing the real desktop
        // through our translucent pixels, so we only write the glass layer.
        // (the tint/lift/opacity live in the bake already - see the comment below)
        // read the padded bake at the offset computed above (see the cache key)
        const uint32_t* bake = (const uint32_t*)g_stripGlass.bits + (size_t)oy * pw + ox;
        // The tint/lift/opacity live in the bake already, so this pass is a copy plus the
        // precomputed per-strip-pixel coverage and rim.
        EnsureStripMasks(w, h, baseRadius);
        uint32_t* out = (uint32_t*)g_paintBits;
        for (int y = 0; y < h; y++) {
            const uint32_t* srcRow = bake + (size_t)y * pw;
            uint32_t* dstRow = out + (size_t)y * g_paintW;
            const BYTE* covRow = &g_covMask[(size_t)y * w];
            const BYTE* rimRow = &g_rimMask[(size_t)y * w];
            for (int x = 0; x < w; x++) {
                DWORD alpha = covRow[x];
                if (!alpha) continue;
                uint32_t v = srcRow[x];
                if (alpha >= 255) {
                    dstRow[x] = v;                       // fully opaque: straight copy
                } else {
                    SetPixelPremul(x, y, ((alpha) << 24) | (v & 0x00FFFFFF));
                }
                DWORD ea = rimRow[x];
                if (ea) SetPixelPremul(x, y, (ea << 24) | 0x00FFFFFF);
            }
        }
        // proof that the baked image ended up in the layered buffer
        static uint32_t lastC = 0;
        static DWORD lastLog = 0;
        DWORD now = GetTickCount();
        if (now - lastLog > 5000) {
            lastLog = now;
            uint32_t out = 0;
            if (g_paintBits && g_paintW == w && g_paintH == h) {
                out = ((const uint32_t*)g_paintBits)[(size_t)(h / 2) * w + w / 2];
            }
            lastC = bake[(size_t)(h / 2) * pw + w / 2];
            DLog(L"paint: glass op=%d tint=%d bakeC=%08X -> outC=%08X",
                 g_glass[0].glassOpacity, g_glass[0].tintStrength, lastC, out);
        }
    } else if (g_cfg.bgAlpha) {
        DWORD cr = GetRValue(g_cfg.bg), cg = GetGValue(g_cfg.bg), cb = GetBValue(g_cfg.bg);
        if (g_cfg.lightMode) { cr = cg = cb = 255; }
        FillRound4(all, RadiusFor(w, h),
                   ((DWORD)g_cfg.bgAlpha << 24) | (cr << 16) | (cg << 8) | cb);
    }
        g_glassCache.assign((const uint32_t*)g_bits, (const uint32_t*)g_bits + (size_t)w * h);
        g_glassCacheW = w;
        g_glassCacheH = h;
        g_glassCacheOx = ox;
        g_glassCacheOy = oy;
        g_glassCacheValid = true;
    }

    QueryPerformanceCounter(&q1);
    for (size_t i = 0; i < g_slots.size(); i++) {
        const Slot& s = g_slots[i];
        // The Windows logo fills its cell, so the usual white hover disc turns the white
        // squares into one bright blob. It still grows under the cursor, which is the
        // feedback; the disc is only drawn where there is something to sit behind.
        if ((int)i == g_hover && s.item != kSlotWin) {
            FillRound(g_memDC, s.rc,
                      RadiusFor(s.rc.right - s.rc.left, s.rc.bottom - s.rc.top) / 2 + 2,
                      ((DWORD)g_cfg.hoverAlpha << 24) | 0x00FFFFFF);
        }
        if (s.item == kSlotChevron) {
            // "^" chevron, drawn by hand (GDI would write alpha 0 into the DIB)
            int cx = (s.rc.left + s.rc.right) / 2;
            int cy = (s.rc.top + s.rc.bottom) / 2;
            int r = g_iconPx / 4;
            DrawLine(cx - r, cy + r / 2, cx, cy - r / 2, 2, 0xF0FFFFFF);
            DrawLine(cx, cy - r / 2, cx + r, cy + r / 2, 2, 0xF0FFFFFF);
            continue;
        }
        if (s.item == kSlotWin) {
            PaintWinButton(s.rc, s.size > 0 ? s.size : g_iconPx);
            continue;
        }
        Item& it = g_items[s.item];
        int sz = s.size > 0 ? s.size : g_iconPx;
        int cellLeft = s.rc.left;
        if (g_reordering && it.animX > -1e8f) cellLeft = (int)lroundf(it.animX);
        int icx = cellLeft + (s.rc.right - s.rc.left) / 2 - sz / 2;
        int icy = (s.rc.top + s.rc.bottom) / 2 - sz / 2;
        if (!it.px.empty() && it.cachedPx > 0) {
            if (it.cachedPx == sz) BlendPremul(icx, icy, sz, sz, it.px.data());
            else BlendScaled(icx, icy, sz, sz, it.px.data(), it.cachedPx, it.cachedPx);
        } else if (it.icon) {
            DrawIconEx(g_memDC, icx, icy, it.icon, sz, sz, 0, nullptr, DI_NORMAL);
        }
        if (it.isPin && !it.hasWindow) {
            RECT d{s.rc.right - sz / 5, s.rc.bottom - sz / 5, s.rc.right - sz / 12,
                   s.rc.bottom - sz / 12};
            FillRound(g_memDC, d, 3, 0x60FFFFFF);
        }
    }
    if (g_reordering && g_reorderItem >= 0 && g_reorderItem < (int)g_items.size()) {
        // The pressed icon: 1.34x, follows the cursor along the strip only, drawn above the
        // others. Clipped to [win.right, chevron.left): the Windows button and the grid
        // button are the two boundaries of the icon area, which is what the user defined.
        Item& it = g_items[g_reorderItem];
        int sz = (int)(g_iconPx * kReorderZoom + 0.5f);
        POINT cp{};
        GetCursorPos(&cp);
        ScreenToClient(g_hwnd, &cp);
        int left = cp.x - sz / 2;
        int top = (h - sz) / 2;
        int clipL = 0, clipR = w;
        for (size_t i = 0; i < g_slots.size(); i++) {
            if (g_slots[i].item == kSlotWin) clipL = g_slots[i].rc.right;
            else if (g_slots[i].item == kSlotChevron) { clipR = g_slots[i].rc.left; break; }
        }
        // a soft lift so it reads as "picked up"
        FillRound(g_memDC, RECT{left, top, left + sz, top + sz}, RadiusFor(sz, sz) / 2 + 2,
                  ((DWORD)g_cfg.hoverAlpha << 24) | 0x00FFFFFF);
        if (!it.px.empty() && it.cachedPx > 0) {
            // bilinear, like the normal hover zoom: point sampling at 1.34x turned a round
            // icon into a faceted polygon with jagged edges
            BlendScaled(left, top, sz, sz, it.px.data(), it.cachedPx, it.cachedPx, clipL, clipR);
        }
    }
    if (g_cfg.debugBeacon) {
        // A marker that is part of the surface: it tells anyone reading a screenshot where
        // the compositor put this window, independently of what the glass content shows.
        int bx = 8, by = h / 2 - 5;
        for (int yy = 0; yy < 10; yy++)
            for (int xx = 0; xx < 10; xx++)
                if (bx + xx < w && by + yy < h)
                    ((uint32_t*)g_paintBits)[(size_t)(by + yy) * g_paintW + bx + xx] =
                        0xFFFF00FFu;      // premultiplied magenta, opaque
    }
    QueryPerformanceCounter(&q2);
    g_statGlass += QpcMs(q0, q1);
    g_statIcons += QpcMs(q1, q2);
    g_statPaints++;
}

static void Present() {
    POINT src{0, 0};
    SIZE size{g_dibW, g_dibH};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, (BYTE)g_alpha, AC_SRC_ALPHA};
    POINT dst{};
    POINT* pdst = nullptr;
    if (g_renderPos.x != INT_MIN) {
        dst = g_renderPos;
        pdst = &dst;
    }
    // presentSync == 2: wait for a composition *before* handing over the new frame, so the
    // position and the pixels land in the same composition. The compositor applies a new
    // window rectangle at its next composition but takes the layered bitmap right away, so
    // an update issued in the middle of a composition interval is displayed as new content
    // at old geometry for a few milliseconds - measured as a backward offset of
    // "speed x one paint step", i.e. the shimmer. Issuing the update right after a
    // composition leaves the whole next interval for both halves to be picked up together.
    // Only worth it when the position is about to change: a stationary repaint (fade, icon
    // zoom) has no geometry to pair the pixels with, and flushing there would just block.
    if (g_cfg.presentSync == 2 && pdst) {
        LARGE_INTEGER s0{}, s1{};
        QueryPerformanceCounter(&s0);
        DwmFlush();
        QueryPerformanceCounter(&s1);
        g_statSync += QpcMs(s0, s1);
        g_statSyncs++;
    }
    // The strip is about to land at `dst`: move the windows that follow it in this very step.
    // Doing it here (after the composition wait, before our own update) puts the strip and its
    // companions into the *same* composition. Following from the 16 ms housekeeping gate left
    // the companion stepping at ~40 Hz next to a ~139 Hz strip, which is exactly the "the tray
    // bar drags at 30 fps" report (measured: dev/t_followfps.ps1, 40.7 vs 111.4 moves/s).
    if (pdst) CompanionFollowTo(dst.x, dst.y);
    LARGE_INTEGER p0{}, p1{};
    QueryPerformanceCounter(&p0);
    if (pdst && g_cfg.presentOrder == 1) {
        // position first, pixels second
        SetWindowPos(g_hwnd, HWND_TOPMOST, dst.x, dst.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
        UpdateLayeredWindow(g_hwnd, nullptr, nullptr, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
    } else if (pdst && g_cfg.presentOrder == 2) {
        // pixels first, position second
        UpdateLayeredWindow(g_hwnd, nullptr, nullptr, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
        SetWindowPos(g_hwnd, HWND_TOPMOST, dst.x, dst.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
    } else {
        UpdateLayeredWindow(g_hwnd, nullptr, pdst, &size, g_memDC, &src, 0, &bf, ULW_ALPHA);
    }
    if (g_cfg.presentSync == 1) {
        // Return only after the compositor has taken this frame. Without it our next frame
        // can be drawn into the same DIB while DWM is still composing the previous window
        // rectangle, and the composite then shows new content at old geometry - a content
        // offset of "one frame's travel", jittering at the beat between our paint rate and
        // the compositor's rate.
        DwmFlush();
    }
    QueryPerformanceCounter(&p1);
    g_statPresent += QpcMs(p0, p1);
    g_statPresents++;
}

// ---------------------------------------------------------------- window ops
// The window the user is actually looking at: the first entry in the z-order
// that is a real, visible, titled app window. Topmost windows are included on
// purpose - the app in front is often a topmost one (a floating app, a media
// player), and it still has to count as "in front" for the toggle to work.
static HWND FrontmostAppWindow() {
    for (HWND h = GetTopWindow(nullptr); h; h = GetWindow(h, GW_HWNDNEXT)) {
        if (!IsWindowVisible(h) || IsIconic(h)) continue;
        if (h == g_hwnd) continue;
        if (IsDockWindow(h)) continue;
        if (IsCloaked(h)) continue;
        if (GetWindowTextLengthW(h) == 0) continue;
        return h;
    }
    return nullptr;
}

// Is this window the one you would actually hit in the middle of its rect?
// Independent of z-order bookkeeping and of GetForegroundWindow.
static bool IsTopAtCenter(HWND h) {
    RECT r{};
    if (!GetWindowRect(h, &r)) return false;
    POINT c{(r.left + r.right) / 2, (r.top + r.bottom) / 2};
    HWND at = WindowFromPoint(c);
    if (!at) return false;
    HWND root = GetAncestor(at, GA_ROOT);
    return root == h || at == h;
}

// GetForegroundWindow can legitimately return NULL here (it does on this
// machine), so fall back to "is it the front-most window in the z-order".
static bool IsInFront(HWND h) {
    HWND fg = GetForegroundWindow();
    if (fg == h) return true;
    if (fg == nullptr) return FrontmostAppWindow() == h || IsTopAtCenter(h);
    DWORD tid = GetWindowThreadProcessId(h, nullptr);
    if (!tid) return false;
    GUITHREADINFO gi{sizeof(gi)};
    if (GetGUIThreadInfo(tid, &gi) && gi.hwndActive == h) return true;
    return false;
}

// ShowWindow across processes is unreliable (it just posts), so ask the window
// to minimize/restore itself the way the taskbar does.
static void MinimizeWindow(HWND h) {
    ShowWindow(h, SW_MINIMIZE);
    if (!IsIconic(h)) PostMessageW(h, WM_SYSCOMMAND, SC_MINIMIZE, 0);
    DLog(L"minimize: iconicAfter=%d", (int)IsIconic(h));
}

static void RestoreWindow(HWND h) {
    ShowWindow(h, SW_RESTORE);
    if (IsIconic(h)) PostMessageW(h, WM_SYSCOMMAND, SC_RESTORE, 0);
}

static void ActivateWindow(HWND h) {
    // Bringing this window to the front is our own doing: the panel must not read the
    // resulting foreground change as "focus went to a third party" (2b-iii/3b-iii).
    if (h && IsWindow(h)) {
        DWORD pid = 0;
        GetWindowThreadProcessId(h, &pid);
        g_friendPid = pid;
        g_focusGraceUntil = GetTickCount() + 300;   // just for the focus change to land
    }
    if (IsIconic(h)) {
        RestoreWindow(h);
    } else if (IsInFront(h) && g_cfg.clickActiveMinimizes) {
        MinimizeWindow(h);
        return;
    }

    // 1) plain call: works when our process owns the last input event
    SetForegroundWindow(h);
    if (IsInFront(h)) { DLog(L"activate: plain ok"); return; }

    // 2) the classic Alt tap unlocks the foreground lock
    keybd_event(VK_MENU, 0, 0, 0);
    SetForegroundWindow(h);
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
    if (IsInFront(h)) { DLog(L"activate: alt tap ok"); return; }

    // 3) undocumented, but ignores the lock
    SwitchToThisWindow(h, TRUE);
    if (IsInFront(h)) { DLog(L"activate: SwitchToThisWindow ok"); return; }

    // 4) join the target's input queue and activate from inside it
    DWORD tidTarget = GetWindowThreadProcessId(h, nullptr);
    DWORD tidMe = GetCurrentThreadId();
    if (tidTarget && tidTarget != tidMe && AttachThreadInput(tidMe, tidTarget, TRUE)) {
        ShowWindow(h, IsIconic(h) ? SW_RESTORE : SW_SHOW);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        SetActiveWindow(h);
        AttachThreadInput(tidMe, tidTarget, FALSE);
    }
    DLog(L"activate: gave up, inFront=%d fg=%p", (int)IsInFront(h), (void*)GetForegroundWindow());
}

// Launching through the shell (ShellExecuteW) reports success even when nothing
// starts in some setups, so resolve the shortcut and start the target directly;
// fall back to the shell for UWP / non-exe targets.
// A launched app that dies within a second or so is not a dock bug (VS Code on this
// machine does exactly that when its install is incomplete). Watch the handle so the log
// says so instead of leaving "I clicked it and nothing happened".
static HANDLE g_launchWatch = nullptr;
static DWORD g_launchWatchPid = 0;
static DWORD g_launchWatchAt = 0;
static std::wstring g_launchWatchLnk;     // the shortcut, for a one-shot shell retry
static bool g_launchRetried = false;

static void LaunchWatchTick() {
    if (!g_launchWatch) return;
    DWORD now = GetTickCount();
    if (now - g_launchWatchAt < 1500) return;
    DWORD code = 0;
    bool alive = GetExitCodeProcess(g_launchWatch, &code) && code == STILL_ACTIVE;
    if (!alive) {
        DLog(L"launch: pid %lu exited %lu ms after starting (code %lu)",
             (unsigned long)g_launchWatchPid, (unsigned long)(now - g_launchWatchAt),
             (unsigned long)code);
        // Some installs cannot be started by CreateProcess on their exe (stub launchers,
        // packaged apps, an updater holding the folder): let the shell try the shortcut
        // once, the same way Explorer would.
        if (!g_launchRetried && !g_launchWatchLnk.empty()) {
            g_launchRetried = true;
            HINSTANCE r = ShellExecuteW(nullptr, L"open", g_launchWatchLnk.c_str(), nullptr,
                                        nullptr, SW_SHOWNORMAL);
            DLog(L"launch: retrying through the shell (%s) -> %lld", g_launchWatchLnk.c_str(),
                 (long long)(INT_PTR)r);
        }
    } else {
        DLog(L"launch: pid %lu is alive after %lu ms", (unsigned long)g_launchWatchPid,
             (unsigned long)(now - g_launchWatchAt));
    }
    CloseHandle(g_launchWatch);
    g_launchWatch = nullptr;
}

static bool LaunchShortcut(const std::wstring& lnk, int index) {
    std::wstring target, args, workdir;
    IShellLinkW* link = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IShellLinkW, (void**)&link))) {
        IPersistFile* pf = nullptr;
        if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, (void**)&pf))) {
            if (SUCCEEDED(pf->Load(lnk.c_str(), STGM_READ))) {
                wchar_t buf[MAX_PATH]{};
                WIN32_FIND_DATAW fd{};
                if (SUCCEEDED(link->GetPath(buf, MAX_PATH, &fd, SLGP_UNCPRIORITY))) target = buf;
                if (SUCCEEDED(link->GetArguments(buf, MAX_PATH))) args = buf;
                if (SUCCEEDED(link->GetWorkingDirectory(buf, MAX_PATH))) workdir = buf;
            }
            pf->Release();
        }
        link->Release();
    }

    if (!target.empty() && PathFileExistsW(target.c_str())) {
        std::wstring cmd = L"\"" + target + L"\"";
        if (!args.empty()) cmd += L" " + args;
        std::vector<wchar_t> cmdBuf(cmd.begin(), cmd.end());
        cmdBuf.push_back(0);
        STARTUPINFOW si{sizeof(si)};
        PROCESS_INFORMATION pi{};
        BOOL ok = CreateProcessW(target.c_str(), cmdBuf.data(), nullptr, nullptr, FALSE, 0, nullptr,
                                 workdir.empty() ? nullptr : workdir.c_str(), &si, &pi);
        if (ok) {
            DLog(L"launch pin %d: CreateProcess ok pid=%lu target=%s", index, pi.dwProcessId,
                 target.c_str());
            CloseHandle(pi.hThread);
            if (g_launchWatch) CloseHandle(g_launchWatch);
            g_launchWatch = pi.hProcess;
            g_launchWatchPid = pi.dwProcessId;
            g_launchWatchAt = GetTickCount();
            g_launchWatchLnk = lnk;
            g_launchRetried = false;
            return true;
        }
        DLog(L"launch pin %d: CreateProcess failed err=%lu target=%s", index, GetLastError(),
             target.c_str());
    } else {
        DLog(L"launch pin %d: no resolved target (lnk=%s), using the shell", index, lnk.c_str());
    }

    HINSTANCE r = ShellExecuteW(nullptr, L"open", lnk.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    DLog(L"launch pin %d: ShellExecute -> %lld (err=%lu)", index, (long long)(INT_PTR)r,
         GetLastError());
    return (INT_PTR)r > 32;
}

static void ClickItem(int index) {
    if (index < 0 || index >= (int)g_items.size()) return;
    if (index >= (int)g_slots.size()) return;
    const Slot slot = g_slots[index];
    int itemIndex = slot.item;
    if (itemIndex < 0) { ThumbHide(); return; }
    Item& it = g_items[itemIndex];
    if (it.hwnd) {
        HWND fm = FrontmostAppWindow();
        DLog(L"click window item %d hwnd=%p title=%s fg=%p frontmost=%p iconic=%d inFront=%d",
             index, (void*)it.hwnd, it.title.c_str(), (void*)GetForegroundWindow(),
             (void*)fm, (int)IsIconic(it.hwnd), (int)IsInFront(it.hwnd));
        ActivateWindow(it.hwnd);
        DLog(L"after activate: fg=%p frontmost=%p", (void*)GetForegroundWindow(),
             (void*)FrontmostAppWindow());
    } else if (it.isPin) {
        LaunchShortcut(it.lnkPath, index);
        SetTimer(g_hwnd, 2, 1200, nullptr);   // refresh soon: the app may be starting
    } else {
        DLog(L"click item %d had no hwnd and was not a pin", index);
    }
}

// ---------------------------------------------------------------- Windows button
// The two popups behind the fixed first button are the shell's own windows. We never
// draw them: we only send the same keystroke the keyboard would, and Windows opens its
// own menu. Measured on this machine (Win11 25H2, 26200.7623): both the Start panel
// (Windows.UI.Core.CoreWindow, 1000x938) and the Win+X menu (Xaml_WindowedPopupClass,
// 222x761, owned by explorer) are XAML/composition surfaces whose screen position is
// owned by the shell - SetWindowPos changes the window rect but not one visible pixel
// (screenshots before/after are byte-identical), so they cannot be moved next to the
// strip from out here. Documented in HANDOVER_NEXT.md §3.3.
//
// Left click uses Ctrl+Esc instead of Win: the shell opens the same Start menu, but the
// taskbar-hidden-until-win mod only reacts to the Win key, so the hidden taskbar stays
// hidden (verified: the taskbar window stays at y=1078 the whole time).
static void SendChord(const BYTE* vks, int count) {
    for (int i = 0; i < count; i++) keybd_event(vks[i], 0, 0, 0);
    for (int i = count - 1; i >= 0; i--) keybd_event(vks[i], 0, KEYEVENTF_KEYUP, 0);
}

static void OpenStartMenu() {
    const BYTE chord[] = {VK_CONTROL, VK_ESCAPE};
    PublishAnchors();      // the mod reads this the moment the menu appears
    DLog(L"win button: left click -> start menu (ctrl+esc)");
    SendChord(chord, 2);
}

// Win+X does have to press Win, which is exactly the signal the taskbar mod turns into
// "show the taskbar". The menu is anchored to the (auto-hidden) taskbar, so it opens
// where the shell wants it, and the taskbar may slide up on the way; a moment later we
// put it back down ourselves with TrayUI's own hide timer (the same message the mod
// uses). Waiting ~650 ms first lets the mod's 500 ms watchdog see the taskbar on screen
// and revoke its expansion permission, so hovering the bottom edge cannot bring it back
// afterwards.
// The taskbar's window is only enumerable while it sits off-screen: once the shell
// expands it (or opens Start, which brings it up on this build) EnumWindows no longer
// returns it, even though the handle is still alive and GetWindowRect still reports
// y=1020. So keep the handles we saw and post the hide to those as well - measured:
// posting to a remembered handle while Start is open is accepted (PostMessage -> 1) but
// the shell keeps the bar up until Start closes, which it then does by itself.
static HWND g_barSeen[8] = {};
static int g_barSeenCount = 0;
// While this is in the future the dock keeps asking the shell to put its taskbar back down
// (see HideNativeTaskbar). Cloaked counts as down: the mod cloaks the bar while our tray
// flyout is up, and that must not be fought.
static DWORD g_barHideRetryUntil = 0;

static bool NativeTaskbarOnScreen() {
    struct Ctx {
        bool on;
    } ctx{false};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            wchar_t cls[64]{};
            if (!GetClassNameW(h, cls, 64)) return TRUE;
            if (_wcsicmp(cls, L"Shell_TrayWnd") != 0 &&
                _wcsicmp(cls, L"Shell_SecondaryTrayWnd") != 0)
                return TRUE;
            if (!IsWindowVisible(h)) return TRUE;
            int cloaked = 0;
            if (SUCCEEDED(DwmGetWindowAttribute(h, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) &&
                cloaked)
                return TRUE;
            RECT r{};
            if (!GetWindowRect(h, &r)) return TRUE;
            HMONITOR mon = MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST);
            MONITORINFO mi{sizeof(mi)};
            if (!GetMonitorInfoW(mon, &mi)) return TRUE;
            const int top = r.top > mi.rcMonitor.top ? r.top : mi.rcMonitor.top;
            const int bottom = r.bottom < mi.rcMonitor.bottom ? r.bottom : mi.rcMonitor.bottom;
            if (bottom - top > 8) {
                *(bool*)lp = true;
                return FALSE;
            }
            return TRUE;
        },
        (LPARAM)&ctx);
    return ctx.on;
}

static void RememberBar(HWND h) {
    for (int i = 0; i < g_barSeenCount; i++)
        if (g_barSeen[i] == h) return;
    if (g_barSeenCount < 8) g_barSeen[g_barSeenCount++] = h;
}

static BOOL CALLBACK HideTaskbarProc(HWND h, LPARAM lp) {
    wchar_t cls[64]{};
    if (!GetClassNameW(h, cls, 64)) return TRUE;
    if (_wcsicmp(cls, L"Shell_TrayWnd") != 0 && _wcsicmp(cls, L"Shell_SecondaryTrayWnd") != 0)
        return TRUE;
    RememberBar(h);
    *(int*)lp += 1;
    PostMessageW(h, WM_TIMER, 2, 0);          // TrayUI's kTrayTimerHide
    DLog(L"win button: hid the native taskbar again (%p)", (void*)h);
    return TRUE;
}

static void HideNativeTaskbar() {
    int found = 0;
    EnumWindows(HideTaskbarProc, (LPARAM)&found);
    // Keep asking for a couple of seconds: the shell defers the hide while one of its popups
    // is opening (measured with Start / Win+X), and when the deferral is lost the bar simply
    // stays up until the user clicks somewhere else - the rare "it did not go away" case.
    g_barHideRetryUntil = GetTickCount() + 2500;
    if (found) return;
    for (int i = 0; i < g_barSeenCount; i++) {
        if (!IsWindow(g_barSeen[i])) continue;
        PostMessageW(g_barSeen[i], WM_TIMER, 2, 0);
        DLog(L"win button: hid the native taskbar again via a remembered handle (%p)",
             (void*)g_barSeen[i]);
    }
}

static BOOL CALLBACK RememberBarProc(HWND h, LPARAM) {
    wchar_t cls[64]{};
    if (!GetClassNameW(h, cls, 64)) return TRUE;
    if (_wcsicmp(cls, L"Shell_TrayWnd") == 0 || _wcsicmp(cls, L"Shell_SecondaryTrayWnd") == 0)
        RememberBar(h);
    return TRUE;
}

// Seed the handle cache while the taskbar is still in its off-screen state (see above).
static void RememberTaskbars() {
    if (g_barSeenCount) return;
    EnumWindows(RememberBarProc, 0);
    if (g_barSeenCount)
        DLog(L"win button: remembered %d native taskbar window(s), e.g. %p", g_barSeenCount,
             (void*)g_barSeen[0]);
}

static void TaskbarDenyExpansion(DWORD ms);      // see "taskbar ctl" below
static void TaskbarAllowExpansion(DWORD ms);

static void OpenPowerUserMenu() {
    const BYTE chord[] = {VK_LWIN, 'X'};
    // ⛔ STABLE: the deny + the 40 ms margin are what stop the native taskbar from popping out
    // while the Windows cell is clicked left/right in a row (HANDOVER_NEXT.md §3.19). The
    // margin is for the mod's 20 ms cache - without it the request arrives after the shell has
    // already started expanding the bar.
    // Arm the anchor first: the menu window is created shortly after the keystroke and the
    // mod uses this timestamp to tell it apart from every other XAML popup.
    ArmWinXAnchor();
    // This chord *is* a Win press, and the shell reacts to it by expanding its taskbar so it
    // can anchor the menu to the Start button (measured 2026-11-17 00:28: y 1078 -> 1020,
    // starting 213 ms after the click). It then refuses to retract the bar while its popup is
    // open, which is the "the taskbar pops out and stays until I click elsewhere" the user
    // kept hitting while clicking left/right on this cell. Nothing here needs that expansion,
    // so tell the mod to keep the bar down for the length of the menu.
    TaskbarDenyExpansion(1200);
    // Give the mod a moment to see it before the chord goes out. The mod reads the block on
    // its own 20 ms tick, and the shell handles this chord within a few ms of the Win key, so
    // without the margin the request simply arrived too late (measured 2026-11-17 00:59).
    // The mod also reads the block directly now; this is the belt to that suspender.
    Sleep(40);
    DLog(L"win button: right click -> win+x menu");
    SendChord(chord, 2);
    if (g_hwnd) SetTimer(g_hwnd, 6, 650, nullptr);
}

// ---------------------------------------------------------------- fade
static int DistanceToWindow() {
    POINT p;
    if (!GetCursorPos(&p)) return 100000;
    RECT r;
    GetWindowRect(g_hwnd, &r);
    auto dist = [&p](const RECT& rr) {
        int dx = 0, dy = 0;
        if (p.x < rr.left) dx = rr.left - p.x;
        else if (p.x > rr.right) dx = p.x - rr.right;
        if (p.y < rr.top) dy = rr.top - p.y;
        else if (p.y > rr.bottom) dy = p.y - rr.bottom;
        if (dx == 0 && dy == 0) return 0;
        return (int)std::sqrt((double)dx * dx + (double)dy * dy);
    };
    int d = dist(r);
    // While the grid panel is open, walking from the strip to the panel must not
    // fade the strip (and with it the panel). Treat the panel as part of "us",
    // and keep everything within two panel gaps at full opacity so a slightly
    // sloppy diagonal move cannot drop the strip before the cursor arrives.
    if (g_gridVisible && g_gridWnd) {
        RECT gr{};
        if (GetWindowRect(g_gridWnd, &gr)) {
            int guard = 16;          // 2 x the gap the panel sits at
            int dg = dist(gr);
            if (dg < d) d = dg;
            if (d <= guard) d = 0;
        }
    }
    // Same for the shell's overflow flyout once we have moved it next to the chevron: the
    // user works in it, so the strip has to stay up while the cursor is over it.
    {
        // Every popup of ours counts as "us" (user 2026-11-17, PLAN_COMPONENTS §7-A4): the
        // settings panel, the thumbnail preview and the context menu are all anchored to the
        // strip, and with the pointer on one of them the strip used to fade out - taking the
        // popup with it and, worse, hiding the group frame while the user was still working
        // in the settings panel ("移出组再移回来之后框线不显示", reported 2026-11-20).
        HWND ours[3] = {g_setWnd, g_thumbWnd, g_menuHwnd};
        for (HWND h : ours) {
            if (!h || !IsWindow(h) || !IsWindowVisible(h)) continue;
            RECT orr{};
            if (!GetWindowRect(h, &orr)) continue;
            int guard = 16;
            int dg = dist(orr);
            if (dg < d) d = dg;
            if (d <= guard) d = 0;
        }
    }
    {
        HWND flyout = g_trayNative ? FindOverflowFlyout() : nullptr;
        if (flyout && IsWindowVisible(flyout)) {
            RECT fr{};
            if (GetWindowRect(flyout, &fr) && fr.left > -30000) {
                int guard = 16;
                int df = dist(fr);
                if (df < d) d = df;
                if (d <= guard) d = 0;
            }
        }
    }
    return d;
}

// Hover can only be learned from mouse messages, but the strip is click-through
// while invisible: when it fades back in under a stationary cursor no message
// arrives. Recompute it from the cursor position on every fade tick.
static void UpdateHoverFromCursor() {
    if (g_reordering) return;      // the row is being reordered: no zoom, no preview
    int hover = -1;
    POINT p{};
    if (GetCursorPos(&p)) {
        POINT c = p;
        ScreenToClient(g_hwnd, &c);
        for (size_t i = 0; i < g_slots.size(); i++) {
            if (PtInRect(&g_slots[i].rc, c)) { hover = (int)i; break; }
        }
        // keep the state while the cursor is over the preview itself
        if (hover < 0 && g_thumbWnd && IsWindowVisible(g_thumbWnd)) {
            RECT tr{};
            if (GetWindowRect(g_thumbWnd, &tr) && PtInRect(&tr, p)) hover = g_hover;
        }
    }
    if (hover == g_hover) return;
    DLog(L"hover -> %d", hover);
    g_hover = hover;
    KillTimer(g_hwnd, 3);
    ThumbHide();
    if (hover >= 0) SetTimer(g_hwnd, 3, (UINT)g_cfg.thumbDelay, nullptr);
    RECT rc;
    GetClientRect(g_hwnd, &rc);
    Paint(rc.right, rc.bottom);
    Present();
}

static bool CursorInCompanionGroup();   // defined with the companions

// The strip's alpha is the default group's alpha (H2b): distance to the *group* rectangle with
// the group's own fade distances. Defined after the group code because it needs Group.
// The group's shared fade value (H2b): the strip and every companion of a group read this one
// number, so they cannot fade independently any more (user, 2026-11-22).
static int DefaultGroupFadeAlpha();

// Is any of our own UI in use right now? While it is, the dock must not fade out and a group must
// not fold up: the pointer has to leave the group to reach a menu item or the settings panel, and
// that trip is not "the user walked away" (user, 2026-11-22, twice: once for the hide, once for
// the distance fade).
static bool OurUiBusy() {
    if (g_popupOpen || g_menuOpen || g_setWnd || g_gridVisible) return true;
    return g_thumbWnd && IsWindowVisible(g_thumbWnd) != FALSE;
}

static void UpdateAlpha() {
    // Settings open, or the panel/menu is up: never fade. The strip is part of the
    // interaction while the user is picking from the grid, and the user asked for it
    // to stay at full strength no matter where the pointer wanders.
    // Same for "the pointer is somewhere in the group": if the attached windows are up,
    // the strip they belong to must not fade out from under the cursor (user, 2026-11-15).
    if (OurUiBusy() || CursorInCompanionGroup()) {
        if (g_alpha != 255) {
            g_alpha = 255;
            if (g_clickThrough) {
                g_clickThrough = false;
                LONG ex = GetWindowLongW(g_hwnd, GWL_EXSTYLE);
                SetWindowLongW(g_hwnd, GWL_EXSTYLE, ex & ~WS_EX_TRANSPARENT);
            }
            Present();
        }
        return;
    }
    // The fade belongs to the *group* now (H2b): the distance is measured to the group's own
    // rectangle with the group's numbers, and every member of the group shows the same value.
    // This used to be DistanceToWindow() with the global numbers, which is why the strip and the
    // companion visibly faded on their own (user, 2026-11-22).
    int a = DefaultGroupFadeAlpha();
    if (a == g_alpha) return;
    DLog(L"fade: strip %d -> %d", g_alpha, a);     // TEMP: verifying the shared group fade
    g_alpha = a;
    bool wantThrough = (a == 0);
    if (wantThrough) ThumbHide();          // invisible dock: no preview either
    if (wantThrough != g_clickThrough) {
        g_clickThrough = wantThrough;
        LONG ex = GetWindowLongW(g_hwnd, GWL_EXSTYLE);
        if (wantThrough) ex |= WS_EX_TRANSPARENT;
        else ex &= ~WS_EX_TRANSPARENT;
        SetWindowLongW(g_hwnd, GWL_EXSTYLE, ex);
        if (!wantThrough) UpdateHoverFromCursor();
    }
    Present();
}

// ---------------------------------------------------------------- wndproc
static void RefreshItems() {
    BuildItems();
    ComputeButtons();
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    Paint(rc.right, rc.bottom);
    Present();
    InvalidateRect(g_hwnd, nullptr, FALSE);
}

static void RefreshCompanionAfterReload();   // needs the paint helpers, defined further down
static void ReloadGroupsFromIni();            // ditto: the group code is further down

static void Reload() {
    LoadConfig();
    // task 3: [dock] snap may have changed on disk (a hand edit + dev/t_dock_reload.ps1). The
    // targets are only recomputed when the window moves, so a reload has to do it here.
    UpdateSnap();
    // task 4: the group switches (hideEdge and its three sub-rows) live in the ini too - the
    // group code is further down, so it does its own reload there.
    ReloadGroupsFromIni();
    g_bakeDirty = true;      // one capture with the new settings
    RefreshItems();
    RefreshCompanionAfterReload();
}

// ---------------------------------------------------------------- flyout anchors
// The shell's own flyouts (Start menu, the volume/network panel, ...) place themselves
// relative to the native taskbar, which is nowhere near our strip. We cannot move them
// from out here: the Start panel is XAML inside StartMenuExperienceHost's full-work-area
// window, and SetWindowPos on it either does nothing visible or gets reverted. A
// Windhawk mod can (windhawk/dock-flyout-anchor.wh.cpp, forked from m417z's
// shell-flyout-positions) - but it runs inside the shell processes and cannot see our
// geometry, so the strip publishes the rect of every button that anchors a flyout here.
// One entry per flyout kind; the mod does the final placement math because only it knows
// the flyout's size and the work area.
// Layout must match windhawk/dock-flyout-anchor.wh.cpp exactly.
enum : unsigned {
    kAnchorStartMenu = 1,      // left click on the Windows button
    kAnchorQuickSettings = 2,  // reserved: a future volume/network button (Win+A)
    kAnchorNotifications = 3,  // reserved: notification centre
    kAnchorWinXMenu = 4,       // right click on the Windows button (Win+X)
    kAnchorKindMax = 16,
};
struct DockAnchorEntry {
    unsigned int kind;         // 0 = unused
    unsigned int flags;        // bit0 = "armed": the flyout was just requested
    int left, top, right, bottom;   // the anchor button, screen coordinates, physical px
    int gapPx;                 // space to keep between the button and the flyout
    unsigned int armedAtMs;    // GetTickCount of the last request (same base in every
                               // process, so the mod can tell "this one is mine")
    int pad[3];
};
struct DockAnchorShm {
    unsigned int magic;        // 'DANK'
    unsigned int version;
    unsigned int count;        // highest used slot + 1
    unsigned int updatedMs;
    DockAnchorEntry entries[kAnchorKindMax];
};
static HANDLE g_anchorOwnMap = nullptr;
static DockAnchorShm* g_anchorShm = nullptr;

// ---- "cloak the taskbar" request for taskbar-hidden-until-win --------------------------
// While the shell's tray flyout is open it insists on keeping its taskbar on screen: its own
// hide timer is ignored and any move is reverted (measured 2026-11-16). Cloaking the taskbar
// stops it being drawn while the shell's state stays "expanded", which is exactly what we
// want - but DwmSetWindowAttribute is refused from another process (E_ACCESSDENIED), and
// SW_HIDE from here breaks the next Win press (a hidden window is not brought back by the
// shell's expand animation). So we only ask the mod, which runs inside explorer.
struct TaskbarCtlShm {
    unsigned int magic;          // 'DTC1'
    unsigned int version;
    unsigned int cloakUntilMs;   // GetTickCount() deadline; 0 = nothing to do
    unsigned int pad;
    // ---- extension ('DTC2'), added 2026-11-17 ------------------------------------------
    // "Who wants the taskbar to be expanded right now". The mod treats a Win press as
    // "let it rise once", which is right for a real Win press but wrong for the two Win
    // presses *we* synthesise:
    //   allowUntilMs - we do want the rise (the tray flyout needs the shell to raise the
    //                  bar; it stays invisible because of the cloak);
    //   denyUntilMs  - we are opening Win+X and nothing may rise. Without this, the shell
    //                  expands the bar to anchor its Win+X menu (measured 2026-11-17
    //                  00:28: +213 ms after the click, y 1078 -> 1020) and then refuses
    //                  to retract it while its popup is open, so the bar sits on screen
    //                  "until you click elsewhere" - the bug the user kept seeing while
    //                  clicking left/right on the Windows cell.
    // Old mods ignore these two fields (they only read the first 16 bytes), and a page
    // mapping is always page sized, so mixing versions is safe.
    unsigned int extMagic;       // 'DTC2'
    unsigned int extVersion;
    unsigned int allowUntilMs;   // the taskbar may expand until this deadline
    unsigned int denyUntilMs;    // the taskbar must stay down until this deadline
};
static HANDLE g_taskbarCtlMap = nullptr;
static TaskbarCtlShm* g_taskbarCtl = nullptr;

static void TaskbarCtlEnsure() {
    if (g_taskbarCtl) return;
    SECURITY_DESCRIPTOR sd{};
    SECURITY_ATTRIBUTES sa{};
    if (!InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION)) return;
    if (!SetSecurityDescriptorDacl(&sd, TRUE, nullptr, FALSE)) return;
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = &sd;
    g_taskbarCtlMap = CreateFileMappingW(INVALID_HANDLE_VALUE, &sa, PAGE_READWRITE, 0,
                                         sizeof(TaskbarCtlShm), L"Local\\DockTaskbarCtl_v1");
    if (!g_taskbarCtlMap) {
        DLog(L"taskbar ctl: block NOT available (err=%lu)", (unsigned long)GetLastError());
        return;
    }
    g_taskbarCtl = (TaskbarCtlShm*)MapViewOfFile(g_taskbarCtlMap, FILE_MAP_ALL_ACCESS, 0, 0,
                                                 sizeof(TaskbarCtlShm));
    if (!g_taskbarCtl) return;
    g_taskbarCtl->magic = 0x31435444;      // 'DTC1'
    g_taskbarCtl->version = 1;
    g_taskbarCtl->cloakUntilMs = 0;
    g_taskbarCtl->extMagic = 0x32435444;   // 'DTC2'
    g_taskbarCtl->extVersion = 1;
    g_taskbarCtl->allowUntilMs = 0;
    g_taskbarCtl->denyUntilMs = 0;
    DLog(L"taskbar ctl: block ready (mod must implement it to take effect)");
}

// "The taskbar may rise" (the tray flyout needs it; the cloak keeps it invisible).
static void TaskbarAllowExpansion(DWORD ms) {
    TaskbarCtlEnsure();
    if (!g_taskbarCtl) return;
    const DWORD now = GetTickCount();
    g_taskbarCtl->allowUntilMs = ms ? now + ms : 0;
    if (g_taskbarCtl->denyUntilMs) g_taskbarCtl->denyUntilMs = 0;
    DLog(L"taskbar ctl: expansion allowed for %lu ms", (unsigned long)ms);
}

// ---- "the taskbar must stay down" request ------------------------------------------------
// ⛔ STABLE (2026-11-17, user-verified). Read HANDOVER_NEXT.md §3.19 before touching any of
// TaskbarDenyExpansion / TaskbarDenyClear or the places that call them: every one of them
// exists because a measured bug came back without it. Rules:
//   * only the dock's own Win+X chord (OpenPowerUserMenu) and the tray path may *set* it;
//   * it is refreshed for as long as the shell's tray flyout is on screen;
//   * it is cleared only via the g_denyClearAt path in RenderTick (700 ms after the flyout
//     goes) or by an explicit "the request failed" line - never on a plain "no flyout is on
//     screen" checked every frame, which used to wipe it 18 ms after it was written.
// "The taskbar must stay down" - used around our own Win+X chord (the shell expands the bar to
// anchor that menu and then refuses to retract it) **and for as long as the shell's tray flyout
// is on screen** (the shell asks to expand the bar for it; that rise is what later surfaced as
// "the taskbar pops out by itself" once the cloak was released).
// Cleared explicitly with TaskbarDenyClear(); the value is a deadline so a missed clear expires.
static void TaskbarDenyExpansion(DWORD ms) {
    TaskbarCtlEnsure();
    if (!g_taskbarCtl) return;
    const DWORD now = GetTickCount();
    g_taskbarCtl->denyUntilMs = ms ? now + ms : 0;
    g_taskbarCtl->allowUntilMs = 0;
    DLog(L"taskbar ctl: expansion denied for %lu ms", (unsigned long)ms);
}

// Cheap "drop the request" for paths that run every frame: no write and no log when there is
// nothing to clear.
static void TaskbarDenyClear(const wchar_t* why = nullptr) {
    TaskbarCtlEnsure();
    if (!g_taskbarCtl) return;
    if (!g_taskbarCtl->denyUntilMs) return;
    g_taskbarCtl->denyUntilMs = 0;
    if (why) DLog(L"taskbar ctl: deny cleared (%s)", why);
    else DLog(L"taskbar ctl: deny cleared");
}

static DWORD g_cloakLastWrite = 0;

static void TaskbarCloakSet(bool on) {
    TaskbarCtlEnsure();
    if (!g_taskbarCtl) return;
    const DWORD now = GetTickCount();
    if (on) {
        if (g_cloakLastWrite && now - g_cloakLastWrite < 500) return;   // refresh twice a second
        g_taskbarCtl->cloakUntilMs = now + 2500;
        g_cloakLastWrite = now;
    } else if (g_taskbarCtl->cloakUntilMs) {
        g_taskbarCtl->cloakUntilMs = 0;
        g_cloakLastWrite = now;
        DLog(L"tray: asked the mod to un-cloak the taskbar");
    }
}

// Opening a flyout must not wait for the 500 ms refresh: a quick second "^" used to squeeze
// between the release of the last cloak and this request, and the taskbar was visible for
// the length of the Win+B expansion.
static void TaskbarCloakForce() {
    TaskbarCtlEnsure();
    if (!g_taskbarCtl) return;
    g_taskbarCtl->cloakUntilMs = GetTickCount() + 2500;
    g_cloakLastWrite = GetTickCount();
}

// Opening takes a moment (Win+B, the taskbar sliding up, Space, the flyout animating in), so
// the cloak must survive the window where the flyout is not on screen yet.
static DWORD g_cloakGraceUntil = 0;
// When the "keep the taskbar down" request may be dropped again (set when a tray flyout goes).
static DWORD g_denyClearAt = 0;
// What had the focus before we opened the flyout: a tray that keeps the keyboard focus makes
// the shell expand its taskbar again later, so the focus is handed back when the flyout goes.
static HWND g_fgBeforeTray = nullptr;

static void AnchorEnsureExists() {
    if (g_anchorShm) return;
    SECURITY_DESCRIPTOR sd{};
    SECURITY_ATTRIBUTES sa{};
    if (!InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION)) return;
    if (!SetSecurityDescriptorDacl(&sd, TRUE, nullptr, FALSE)) return;
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = &sd;
    sa.bInheritHandle = FALSE;
    if (!g_anchorOwnMap) {
        g_anchorOwnMap = CreateFileMappingW(INVALID_HANDLE_VALUE, &sa, PAGE_READWRITE, 0,
                                            sizeof(DockAnchorShm), L"Local\\DockAnchor_v1");
        DLog(L"anchor: flyout block %s (err=%lu)",
             g_anchorOwnMap ? L"available" : L"NOT available", (unsigned long)GetLastError());
        if (!g_anchorOwnMap) return;
    }
    g_anchorShm = (DockAnchorShm*)MapViewOfFile(g_anchorOwnMap, FILE_MAP_WRITE, 0, 0,
                                                sizeof(DockAnchorShm));
    if (!g_anchorShm) return;
    memset(g_anchorShm, 0, sizeof(DockAnchorShm));
    g_anchorShm->magic = 0x4B4E4144;      // 'DANK'
    g_anchorShm->version = 2;             // 2 = entries carry armedAtMs
}

// Publish (or clear, with a null rect) one anchor. Called for every flyout button we own,
// so the mod always sees the current geometry; the block dies with the dock, which is why
// a stale entry can never survive us. `armed` marks "the flyout is being opened right now",
// which is how the mod recognises a popup that belongs to us (XAML popups all share one
// window class, there is nothing else to go by).
static void AnchorPublish(unsigned kind, const RECT* screenRect, int gapPx, bool armed = false) {
    AnchorEnsureExists();
    if (!g_anchorShm || kind == 0 || kind > kAnchorKindMax) return;
    DockAnchorEntry& e = g_anchorShm->entries[kind - 1];
    bool empty = (screenRect == nullptr);
    int l = empty ? 0 : screenRect->left;
    int t = empty ? 0 : screenRect->top;
    int r = empty ? 0 : screenRect->right;
    int b = empty ? 0 : screenRect->bottom;
    unsigned flags = empty ? 0 : (armed ? 1u : 0u);
    unsigned armedAt = armed ? GetTickCount() : e.armedAtMs;
    // A plain republish (layout change while the menu is opening) must not disarm us: keep
    // the arm for its whole validity window, the mod uses the same 3 s.
    if (!armed && !empty && e.flags && armedAt && (GetTickCount() - armedAt) < 3000) flags = e.flags;
    if (!empty && e.kind == kind && e.left == l && e.top == t && e.right == r && e.bottom == b &&
        e.gapPx == gapPx && e.flags == flags && (!armed || e.armedAtMs == armedAt))
        return;      // unchanged
    if (empty && e.kind == 0) return;
    memset(&e, 0, sizeof(e));
    e.kind = empty ? 0 : kind;
    e.flags = flags;
    e.left = l;
    e.top = t;
    e.right = r;
    e.bottom = b;
    e.gapPx = empty ? 0 : gapPx;
    e.armedAtMs = empty ? 0 : armedAt;
    if (!empty && (unsigned)(kind) >= g_anchorShm->count) g_anchorShm->count = kind;
    g_anchorShm->updatedMs = GetTickCount();
    // No logging here on purpose: this runs on every drag frame (the anchor follows the
    // button), and DLog opens/closes the log file per line - measured, that alone dropped
    // the drag rate and spun the fan up. Use dev/anchordump.ps1 to inspect the block.
}

// Screen rect of a slot (client rect -> screen), or false when the slot is not on screen.
static bool SlotScreenRect(int slot, RECT* out) {
    if (!g_hwnd || slot < 0 || slot >= (int)g_slots.size()) return false;
    RECT r = g_slots[slot].rc;
    POINT tl{r.left, r.top}, br{r.right, r.bottom};
    if (!ClientToScreen(g_hwnd, &tl) || !ClientToScreen(g_hwnd, &br)) return false;
    *out = RECT{tl.x, tl.y, br.x, br.y};
    return true;
}

static RECT AnchorRectForItem(int wantItem) {
    // Deliberately the *cell* rect at the configured icon size, not the current slot:
    // the hover zoom would otherwise move the anchor by up to 34% while the flyout is
    // being opened, and the flyout only needs to know which button this is.
    RECT r{};
    for (int i = 0; i < (int)g_slots.size(); i++) {
        if (g_slots[i].item != wantItem) continue;
        RECT cell = g_slots[i].rc;
        int cx = (cell.left + cell.right) / 2;
        int cy = (cell.top + cell.bottom) / 2;
        int half = g_iconPx / 2;
        cell = RECT{cx - half, cy - half, cx + half, cy + half};
        POINT tl{cell.left, cell.top}, br{cell.right, cell.bottom};
        if (!g_hwnd || !ClientToScreen(g_hwnd, &tl) || !ClientToScreen(g_hwnd, &br))
            return RECT{0, 0, 0, 0};
        return RECT{tl.x, tl.y, br.x, br.y};
    }
    return r;
}

// Republish every anchor the strip owns. Cheap (a few compares) and called from both
// ComputeButtons() and right before a flyout is opened, so a moved/resized strip cannot
// leave the mod with a stale target.
static void PublishAnchors() {
    const int gap = 8;
    RECT win = AnchorRectForItem(kSlotWin);
    bool haveWin = win.right > win.left;
    AnchorPublish(kAnchorStartMenu, haveWin ? &win : nullptr, gap);
    // The same button also anchors the Win+X popup; it is only *armed* for a moment after a
    // right click, because that popup's window class is shared with every other XAML popup.
    AnchorPublish(kAnchorWinXMenu, haveWin ? &win : nullptr, gap);
}

static void ArmWinXAnchor() {
    PublishAnchors();      // fresh rect first, then the arm flag
    RECT win = AnchorRectForItem(kSlotWin);
    if (win.right > win.left) AnchorPublish(kAnchorWinXMenu, &win, 8, true);
}

// ---------------------------------------------------------------- companions
// Attached windows: small windows that live *next to* the strip instead of inside it, so
// they can be moved and resized on their own. Style is not copied - they read the same
// `g_cfg`, and they reuse the strip's drawing primitives by pointing the shared pixel
// pointers at their own DIB for the duration of a paint, which is exactly what
// GridPaint()/SettingsPaint() already do.
//
// First (and for now only) companion: the tray bar - network / volume / battery as one
// button. Any click opens the shell's quick settings (Win+A), and the anchor block tells
// the Windhawk mod to put that panel next to us (kind = QuickSettings).
//
// Group rules (see PLAN_COMPANION.md): follow = 1 means "moves with the strip, appears
// only while the pointer is on the strip (or inside the group)". follow = 0 is an
// independent window that fades with cursor distance like the strip does.
static int EdgeAt(POINT p, const RECT& rcIn);      // defined further down
// How many groups can exist (G2). Fixed: ids/indexes stay stable for windows and the ini.
static const int kMaxGroups = 4;

struct TrayState {
    int netKind = 0;                  // 0 none, 1 wifi, 2 ethernet
    int netQuality = 0;               // 0..100 (wifi)
    wchar_t netName[96] = L"";        // profile name / "以太网"
    int volPercent = 0;
    bool muted = false;
    int batPercent = -1;              // -1 = no battery
    bool charging = false;
};
static TrayState g_trayState;

struct Companion {
    HWND hwnd = nullptr;
    const wchar_t* iniSection = L"traybar";
    bool enabled = true;
    bool follow = true;
    RECT rc{0, 0, 0, 0};              // screen px
    // own 32bpp premultiplied buffer (the strip's pixel helpers are pointed at it while
    // painting, see TrayPaint)
    HDC dc = nullptr;
    HBITMAP bmp = nullptr;
    void* bits = nullptr;
    int dibW = 0, dibH = 0;
    int alpha = 0;
    int alphaTarget = 0;
    bool dragging = false;
    bool resizing = false;
    int resizeEdge = 0;
    RECT resizeRect{};
    POINT resizeOrigin{};
    POINT dragStart{};
    bool pressActive = false;
    POINT pressScreen{};
    int hoverCell = -1;
    HWND tipWnd = nullptr;
    TOOLINFOW tipInfo{};
    // Kept active for the whole session and only moved/texted on hover: the first
    // TTM_TRACKACTIVATE after a deactivate costs ~125 ms (measured 2026-11-17), and it used to
    // run inside the mouse-move handler - that was the hitch when the pointer entered the
    // window. See CompanionTooltipShow().
    bool tipActive = false;
    DWORD stateAt = 0;
    DWORD netAt = 0;              // the WLAN query is expensive: its own, slower cadence
    bool visible = false;
    // Which group this window belongs to (G2): 1 = the default group (follows the strip),
    // 0 = independent (no group at all, distance fade), N>1 = its own group.
    int groupId = 1;
    // Per-window style overrides (R4): [traybar] radius/pad/gap. -1 = inherit from [dock],
    // which is the "跟随条样式" default; the plan's "独立样式" hook is exactly this.
    int padOv = -1, gapOv = -1, radiusOv = -1;
    // task 3: [traybar] snap, -1 = inherit [dock] snap; the per-corner factors are this
    // window's own (the strip has its own g_cornerAnim), animated the same ~120 ms way.
    int snapOv = -1;
    float snapAnim[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float snapTarget[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    // H3: this window's own padded backdrop bake (same pipeline as the strip, own pixels).
    // It is only filled when the window actually draws the glass layer - see CompanionGlassTick.
    GlassTarget glass;
    int glassCount = 0;           // bakes done since the last cadence line (it costs real ms)
    DWORD glassSig = 0;           // glass parameters the current bake was made with
    // H3: when the window last moved. A moved window only needs the *crop* to follow (the
    // picture is anchored to the screen, see CompanionPaintGlass), so a move must not trigger
    // a capture - otherwise following the strip during a drag would re-grab ~15 ms per frame.
    DWORD glassMovedAt = 0;
    DWORD glassWideUntil = 0;     // keep the wide bake margin until then (see CompanionGlassTick)
};
static Companion g_trayBar;

// Style accessors: one place decides "override or inherit" for every drawing site.
static int CompanionPad(const Companion& c) { return c.padOv >= 0 ? c.padOv : g_cfg.pad; }
static int CompanionGap(const Companion& c) { return c.gapOv >= 0 ? c.gapOv : g_cfg.gap; }
static int CompanionRadiusPercent(const Companion& c) {
    return c.radiusOv >= 0 ? c.radiusOv : g_cfg.radius;
}

#define kTrayCellCount 3
#define kTrayVolumeStep 2        // percent per wheel detent over the volume cell (user 2026-11-16)

// forward declarations (the state poller repaints, and the painting code is further down)
static void TrayRepaint(Companion& c);
static void CompanionPresent(Companion& c);
// H3: "does this window draw the glass layer?" - defined with the component helpers further
// down, needed by the paint path above it.
static bool CompanionUsesGlass(const Companion& c);
static int CompanionBgMode(const Companion& c);      // 0 behind / 1 picture / 2 solid
// the group frame (R2) is derived geometry: "the strip + every following companion"
static struct Group& DefaultGroup();
static bool GroupBoxRect(Group& g, RECT* out);
static bool GroupScaling();      // true while any frame is being dragged to scale its group
static bool GroupDragging();     // true while any board (or member) is dragging its group
static bool PointerInDefaultGroup(POINT p);   // pointer in the strip's own group (or driving it)
// quick settings placement (defined after the companions: it needs the capture helpers)
static void QuickSettingsBeginPlacement(const RECT& button);

// Task 1, z-order policy (the whole story is in the block next to CollectOurWindows):
// 0 = normal, every window of ours belongs in the topmost band; 1 = the dock is deliberately
// *below* a capture tool (or a fullscreen app) and NOTHING of ours may assert HWND_TOPMOST -
// the automatic show paths below are the ones that used to undo that in the middle of a
// selection drag (measured by the user with QQ's snip on 2026-11-22: the toolbar/menus sit right
// next to the dock, so moving onto them fades the companion in, and its show path lifted the
// whole dock back over the selection box).
static int g_zMode = 0;
static HWND ZBandInsert() { return g_zMode == 1 ? HWND_NOTOPMOST : HWND_TOPMOST; }

static int CompanionIconPx(const Companion& c) {
    int w = c.rc.right - c.rc.left, h = c.rc.bottom - c.rc.top;
    int shortSide = w < h ? w : h;
    int icon = shortSide - CompanionPad(c) * 2;
    if (icon < g_cfg.minIcon) icon = g_cfg.minIcon;
    if (icon > g_cfg.maxIcon) icon = g_cfg.maxIcon;
    return icon;
}

// Cell rects in client coordinates. The tray bar keeps the same orientation rule as the
// strip: tall window -> cells stacked, wide window -> cells in a row.
static void TrayCells(const Companion& c, RECT out[kTrayCellCount]) {
    int w = c.rc.right - c.rc.left, h = c.rc.bottom - c.rc.top;
    bool vertical = (h > w);
    int icon = CompanionIconPx(c);
    int gap = CompanionGap(c);
    int cell = icon + gap;
    int span = kTrayCellCount * cell - gap;
    int startX = (w - span) / 2;
    int startY = (h - span) / 2;
    for (int i = 0; i < kTrayCellCount; i++) {
        if (vertical) {
            int x = (w - icon) / 2;
            out[i] = RECT{x, startY + i * cell, x + icon, startY + i * cell + icon};
        } else {
            int y = (h - icon) / 2;
            out[i] = RECT{startX + i * cell, y, startX + i * cell + icon, y + icon};
        }
    }
}

// ---------------------------------------------------------------- tray state
// The COM pointers live at file scope because the wheel handler writes through the same
// interface the poller reads (both on the UI thread, so no marshalling).
static IMMDeviceEnumerator* g_volEnum = nullptr;
static IAudioEndpointVolume* g_vol = nullptr;
static bool VolumeEnsure() {
    if (!g_volEnum) {
        CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                         __uuidof(IMMDeviceEnumerator), (void**)&g_volEnum);
    }
    if (g_volEnum && !g_vol) {
        IMMDevice* device = nullptr;
        if (SUCCEEDED(g_volEnum->GetDefaultAudioEndpoint(eRender, eConsole, &device)) && device) {
            device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, (void**)&g_vol);
            device->Release();
        }
    }
    return g_vol != nullptr;
}

static void QueryVolume() {
    if (!VolumeEnsure()) return;
    float scalar = 0;
    BOOL mute = FALSE;
    if (SUCCEEDED(g_vol->GetMasterVolumeLevelScalar(&scalar))) {
        int pct = (int)(scalar * 100.0f + 0.5f);
        g_trayState.volPercent = pct < 0 ? 0 : (pct > 100 ? 100 : pct);
    }
    if (SUCCEEDED(g_vol->GetMute(&mute))) g_trayState.muted = mute != FALSE;
}

// Used by the wheel: one detent = 2 % (user, 2026-11-16).
static bool SetVolumePercent(int pct) {
    if (!VolumeEnsure()) return false;
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    if (FAILED(g_vol->SetMasterVolumeLevelScalar(pct / 100.0f, nullptr))) return false;
    g_trayState.volPercent = pct;
    return true;
}

static bool SetMuted(bool muted) {
    if (!VolumeEnsure()) return false;
    if (FAILED(g_vol->SetMute(muted ? TRUE : FALSE, nullptr))) return false;
    g_trayState.muted = muted;
    return true;
}

static void QueryPower() {
    SYSTEM_POWER_STATUS st{};
    if (!GetSystemPowerStatus(&st)) return;
    if (st.BatteryLifePercent == 255) {
        g_trayState.batPercent = -1;
        g_trayState.charging = false;
        return;
    }
    g_trayState.batPercent = st.BatteryLifePercent;
    g_trayState.charging = (st.ACLineStatus == 1);
}

// ---- network state, queried off the UI thread (2026-11-17) ---------------------------
// WlanOpenHandle + WlanEnumInterfaces + WlanQueryInterface is an RPC into the WLAN service and
// costs tens of milliseconds. Done on the UI thread it starves our WH_MOUSE_LL hook, and a
// hook that cannot answer in time stalls the *whole system's* pointer - the user felt it as a
// hitch exactly when the tray companion (wifi/volume/battery) faded in, because that transition
// forces a refresh. So the query lives on its own thread and the UI thread only copies the last
// snapshot; nothing on the paint/hover path can block on the WLAN service any more.
struct NetSnapshot {
    int kind = 0;                     // 0 = none, 1 = WLAN, 2 = ethernet
    int quality = 0;
    wchar_t name[96] = L"";
    // The audio endpoint getter is an RPC into the audio service too (measured 11.8 ms once, on
    // the very frame the companion appeared), so volume and battery are sampled here as well and
    // the UI thread only copies them.
    int volPercent = -1;
    bool muted = false;
    int batPercent = -1;
    bool charging = false;
};
static NetSnapshot g_netSnapshot;
static unsigned g_netVersion = 0;         // bumped by the worker whenever it publishes
static unsigned g_netSeen = 0;            // last version the UI thread adopted
static CRITICAL_SECTION g_netLock;
static bool g_netLockReady = false;
static HANDLE g_netWake = nullptr;        // auto-reset: "query again now"
static HANDLE g_netQuit = nullptr;        // manual-reset: thread exit
static HANDLE g_netThread = nullptr;

static void QueryNetworkInto(NetSnapshot* out) {
    out->kind = 0;
    out->quality = 0;
    out->name[0] = 0;

    // Wi-Fi first: the WLAN API tells us both whether it is up and how good the signal is.
    bool wifiUp = false;
    HANDLE wlan = nullptr;
    DWORD version = 0;
    if (WlanOpenHandle(2, nullptr, &version, &wlan) == ERROR_SUCCESS) {
        PWLAN_INTERFACE_INFO_LIST list = nullptr;
        if (WlanEnumInterfaces(wlan, nullptr, &list) == ERROR_SUCCESS && list) {
            for (DWORD i = 0; i < list->dwNumberOfItems; i++) {
                PWLAN_INTERFACE_INFO info = &list->InterfaceInfo[i];
                if (info->isState != wlan_interface_state_connected) continue;
                wifiUp = true;
                PWLAN_CONNECTION_ATTRIBUTES attr = nullptr;
                DWORD attrSize = 0;
                WLAN_OPCODE_VALUE_TYPE opType;
                if (WlanQueryInterface(wlan, &info->InterfaceGuid,
                                       wlan_intf_opcode_current_connection, nullptr, &attrSize,
                                       (PVOID*)&attr, &opType) == ERROR_SUCCESS &&
                    attr) {
                    out->quality = (int)attr->wlanAssociationAttributes.wlanSignalQuality;
                    wcsncpy_s(out->name,
                              attr->strProfileName[0] ? attr->strProfileName : L"WLAN",
                              _TRUNCATE);
                    WlanFreeMemory(attr);
                }
                break;
            }
            WlanFreeMemory(list);
        }
        WlanCloseHandle(wlan, nullptr);
    }

    if (wifiUp) {
        out->kind = 1;
        if (!out->name[0]) wcscpy_s(out->name, L"WLAN");
        return;
    }

    // No Wi-Fi: a live LAN connection means the cable is in. (InternetGetConnectedState is
    // "there is a network", which is exactly what the tray icon shows before it has decided
    // whether the internet is reachable.)
    DWORD flags = 0;
    if (InternetGetConnectedState(&flags, 0)) {
        out->kind = 2;
        wcscpy_s(out->name, L"以太网");
    }
}

// The audio endpoint and the battery are queried on the worker as well. The worker has its own
// COM apartment and its own endpoint objects on purpose: an interface pointer is only valid
// inside the apartment that created it, and the dock's UI thread never calls CoInitialize, so
// sharing g_vol with this thread would be a marshal error waiting to happen.
static IMMDeviceEnumerator* g_volEnumW = nullptr;
static IAudioEndpointVolume* g_volW = nullptr;

static bool WorkerVolumeReady() {
    if (!g_volEnumW) {
        CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                         __uuidof(IMMDeviceEnumerator), (void**)&g_volEnumW);
    }
    if (g_volEnumW && !g_volW) {
        IMMDevice* device = nullptr;
        if (SUCCEEDED(g_volEnumW->GetDefaultAudioEndpoint(eRender, eConsole, &device)) && device) {
            device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, (void**)&g_volW);
            device->Release();
        }
    }
    return g_volW != nullptr;
}

static void QueryVolumeInto(int* percent, bool* muted) {
    if (!WorkerVolumeReady()) return;
    float scalar = 0;
    BOOL mute = FALSE;
    if (SUCCEEDED(g_volW->GetMasterVolumeLevelScalar(&scalar))) {
        int pct = (int)(scalar * 100.0f + 0.5f);
        *percent = pct < 0 ? 0 : (pct > 100 ? 100 : pct);
    }
    if (SUCCEEDED(g_volW->GetMute(&mute))) *muted = mute != FALSE;
}

static void QueryPowerInto(int* percent, bool* charging) {
    SYSTEM_POWER_STATUS st{};
    if (!GetSystemPowerStatus(&st)) return;
    if (st.BatteryLifePercent == 255) {
        *percent = -1;
        *charging = false;
        return;
    }
    *percent = st.BatteryLifePercent;
    *charging = (st.ACLineStatus == 1);
}

static DWORD WINAPI NetQueryProc(LPVOID) {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    NetSnapshot prev;
    for (;;) {
        HANDLE waits[2] = {g_netQuit, g_netWake};
        DWORD r = WaitForMultipleObjects(2, waits, FALSE, 3000);
        if (r == WAIT_OBJECT_0) break;                 // quit
        NetSnapshot s;
        const DWORD t0 = GetTickCount();
        QueryNetworkInto(&s);
        QueryVolumeInto(&s.volPercent, &s.muted);
        QueryPowerInto(&s.batPercent, &s.charging);
        const DWORD spent = GetTickCount() - t0;
        EnterCriticalSection(&g_netLock);
        g_netSnapshot = s;
        g_netVersion++;
        LeaveCriticalSection(&g_netLock);
        // Diagnostics: a change is what the icon shows (rare), and a slow query is worth a line
        // because that is exactly the time the UI thread used to spend blocking the mouse hook.
        const bool changed = s.kind != prev.kind || s.quality != prev.quality ||
                             wcscmp(s.name, prev.name) != 0;
        if (changed || spent >= 100) {
            DLog(L"tray net worker: kind=%d q=%d '%s' took %lu ms", s.kind, s.quality, s.name,
                 (unsigned long)spent);
            prev = s;
        }
    }
    return 0;
}

static void NetQueryStart() {
    if (!g_netLockReady) {
        InitializeCriticalSection(&g_netLock);
        g_netLockReady = true;
    }
    if (!g_netWake) g_netWake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!g_netQuit) g_netQuit = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!g_netThread && g_netWake && g_netQuit) {
        g_netThread = CreateThread(nullptr, 0, NetQueryProc, nullptr, 0, nullptr);
    }
}

// "Do it as soon as the worker can" - never blocks the caller.
static void NetQueryNudge() {
    if (g_netWake) SetEvent(g_netWake);
}

// Copy the worker's last answer into the painted state. Cheap (one small struct under a lock)
// and only does anything when the worker has published something new, so it is safe to call on
// every housekeeping tick - which is what keeps the icon honest without a blocking query.
static void QueryNetworkFromSnapshot() {
    if (!g_netLockReady) return;
    NetSnapshot s;
    unsigned ver = 0;
    EnterCriticalSection(&g_netLock);
    s = g_netSnapshot;
    ver = g_netVersion;
    LeaveCriticalSection(&g_netLock);
    if (ver == g_netSeen) return;
    g_netSeen = ver;
    g_trayState.netKind = s.kind;
    g_trayState.netQuality = s.quality;
    wcscpy_s(g_trayState.netName, s.name);
    if (s.volPercent >= 0) g_trayState.volPercent = s.volPercent;
    g_trayState.muted = s.muted;
    g_trayState.batPercent = s.batPercent;
    g_trayState.charging = s.charging;
}

// True when the worker has published a newer network answer than the one being painted.
static bool NetVersionFresh() {
    if (!g_netLockReady) return false;
    EnterCriticalSection(&g_netLock);
    const unsigned v = g_netVersion;
    LeaveCriticalSection(&g_netLock);
    return v != g_netSeen;
}

static void TrayStateRefresh(DWORD now) {
    // Two cadences on purpose: volume/power are cheap (a COM getter and a struct), but the
    // WLAN query is an RPC into the wireless service and can take tens of milliseconds - at
    // 1 Hz that was a visible hitch every second while the bar was on screen. Since 2026-11-17
    // that query runs on its own thread (NetQueryProc); here we only copy its last answer and
    // ask for a new one every few seconds, so nothing on this path can block.
    if (g_trayBar.alpha <= 0 && g_trayBar.stateAt) {
        // Hidden: only take the worker's answer (no repaint). The wifi signal wobbles by a few
        // percent every sample, and repainting the DIB here cost 5-15 ms every three seconds
        // while nobody was looking - the pixels are rebuilt on the show transition instead.
        QueryNetworkFromSnapshot();
        return;
    }

    bool networkDue = !g_trayBar.netAt || (now - g_trayBar.netAt) >= 5000;
    // The cadence gate must not hold back a fresh answer from the worker: the wifi icon would
    // then be up to a second stale right after the companion appears.
    if (g_trayBar.stateAt && (now - g_trayBar.stateAt) < 1000 && !NetVersionFresh()) return;
    g_trayBar.stateAt = now;

    TrayState before = g_trayState;
    const double t0 = NowMs();
    // Everything here is a lock-and-copy of the worker's last answer; the only UI-thread query
    // left is the one-time "we have no volume value yet" case (the worker needs a moment after
    // start-up), and that is exactly what used to cost 11.8 ms on the show transition.
    if (g_trayState.volPercent < 0 || g_trayState.batPercent == -100) {
        QueryVolume();
        QueryPower();
    }
    QueryNetworkFromSnapshot();
    const double t1 = NowMs();
    if (t1 - t0 >= 3.0) DLog(L"slow: tray state refresh %.1f ms", t1 - t0);
    if (networkDue) {
        g_trayBar.netAt = now;
        NetQueryNudge();          // the answer arrives on the worker thread; no blocking here
    }
    bool changed = memcmp(&before, &g_trayState, sizeof(TrayState)) != 0;
    if (changed && g_trayBar.hwnd) {
        DLog(L"tray bar: net=%d(q=%d '%s') vol=%d mute=%d bat=%d chg=%d",
             g_trayState.netKind, g_trayState.netQuality, g_trayState.netName,
             g_trayState.volPercent, (int)g_trayState.muted, g_trayState.batPercent,
             (int)g_trayState.charging);
        TrayRepaint(g_trayBar);
        CompanionPresent(g_trayBar);
    }
}

// ---------------------------------------------------------------- tray painting
// A glyph from the system icon font (the taskbar uses the same one). GDI writes alpha 0
// into a 32bpp DIB, so the glyph is rasterised into a scratch mask first; the mask is then
// measured and scaled to fit the cell (the font's line height is much larger than its ink,
// which made an unlucky first version overflow and clip), and finally blended through
// SetPixelPremul - the same idea as DrawTextAlpha() for the settings panel.
struct GlyphMask {
    wchar_t code = 0;
    int px = 0;
    int w = 0, h = 0;
    std::vector<unsigned char> a;
};
static std::vector<GlyphMask> g_glyphCache;

static bool RenderGlyphMask(wchar_t code, int px, GlyphMask* out) {
    for (const auto& g : g_glyphCache)
        if (g.code == code && g.px == px) {
            *out = g;
            return true;
        }

    const int box = px * 2;                     // room for ascenders/descenders
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = box;
    bi.bmiHeader.biHeight = -box;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    HBITMAP bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bmp) { ReleaseDC(nullptr, screen); return false; }
    HDC dc = CreateCompatibleDC(screen);
    HGDIOBJ old = SelectObject(dc, bmp);
    memset(bits, 0, (size_t)box * box * 4);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    HFONT font = CreateFontW(px, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                             DEFAULT_PITCH, L"Segoe Fluent Icons");
    HGDIOBJ oldFont = SelectObject(dc, font);
    RECT tr{0, 0, box, box};
    wchar_t text[2] = {code, 0};
    DrawTextW(dc, text, 1, &tr, DT_SINGLELINE | DT_CENTER | DT_TOP | DT_NOPREFIX);
    SelectObject(dc, oldFont);
    DeleteObject(font);

    // ink bounding box
    auto* src = (uint32_t*)bits;
    int minX = box, minY = box, maxX = -1, maxY = -1;
    for (int y = 0; y < box; y++)
        for (int x = 0; x < box; x++) {
            int a = ((src[(size_t)y * box + x] >> 16) & 0xFF);
            if (a <= 4) continue;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }

    bool ok = maxX > minX && maxY > minY;
    if (ok) {
        out->code = code;
        out->px = px;
        out->w = maxX - minX + 1;
        out->h = maxY - minY + 1;
        out->a.assign((size_t)out->w * out->h, 0);
        for (int y = 0; y < out->h; y++)
            for (int x = 0; x < out->w; x++) {
                int a = ((src[(size_t)(minY + y) * box + (minX + x)] >> 16) & 0xFF);
                out->a[(size_t)y * out->w + x] = (unsigned char)(a > 255 ? 255 : a);
            }
        if (g_glyphCache.size() < 24) g_glyphCache.push_back(*out);
    }

    SelectObject(dc, old);
    DeleteObject(bmp);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
    return ok;
}

// Draw one glyph centred in `cell`, its ink scaled to fill `fill` (0..1) of the cell.
static void DrawGlyphInCell(const RECT& cell, wchar_t code, DWORD rgb, float fill) {
    if (!g_paintBits) return;
    int cw = cell.right - cell.left, ch = cell.bottom - cell.top;
    if (cw <= 0 || ch <= 0) return;

    GlyphMask mask;
    if (!RenderGlyphMask(code, ch, &mask)) return;

    int targetH = (int)(ch * fill + 0.5f);
    if (targetH < 1) return;
    int targetW = (int)((float)mask.w * targetH / (float)mask.h + 0.5f);
    if (targetW > cw) {
        targetW = cw;
        targetH = (int)((float)mask.h * targetW / (float)mask.w + 0.5f);
    }
    int ox = cell.left + (cw - targetW) / 2;
    int oy = cell.top + (ch - targetH) / 2;

    DWORD r0 = rgb & 0xFF, g0 = (rgb >> 8) & 0xFF, b0 = (rgb >> 16) & 0xFF;
    for (int y = 0; y < targetH; y++) {
        // bilinear sample of the mask (it is a coverage map, so this stays smooth)
        float sy = (y + 0.5f) * mask.h / targetH - 0.5f;
        int y0 = (int)floorf(sy);
        float fy = sy - y0;
        int y1 = y0 + 1;
        if (y0 < 0) y0 = 0;
        if (y1 < 0) y1 = 0;
        if (y0 >= mask.h) y0 = mask.h - 1;
        if (y1 >= mask.h) y1 = mask.h - 1;
        for (int x = 0; x < targetW; x++) {
            float sx = (x + 0.5f) * mask.w / targetW - 0.5f;
            int x0 = (int)floorf(sx);
            float fx = sx - x0;
            int x1 = x0 + 1;
            if (x0 < 0) x0 = 0;
            if (x1 < 0) x1 = 0;
            if (x0 >= mask.w) x0 = mask.w - 1;
            if (x1 >= mask.w) x1 = mask.w - 1;
            float a00 = mask.a[(size_t)y0 * mask.w + x0];
            float a10 = mask.a[(size_t)y0 * mask.w + x1];
            float a01 = mask.a[(size_t)y1 * mask.w + x0];
            float a11 = mask.a[(size_t)y1 * mask.w + x1];
            float a = (a00 * (1 - fx) + a10 * fx) * (1 - fy) +
                      (a01 * (1 - fx) + a11 * fx) * fy;
            int ai = (int)(a * 1.6f + 0.5f);        // icon ink is thinner than text
            if (ai > 255) ai = 255;
            if (ai <= 6) continue;
            SetPixelPremul(ox + x, oy + y,
                           ((DWORD)ai << 24) | ((DWORD)(r0 * ai / 255) << 16) |
                               ((DWORD)(g0 * ai / 255) << 8) | (DWORD)(b0 * ai / 255));
        }
    }
}

static wchar_t TrayGlyphNet() {
    if (g_trayState.netKind == 2) return 0xE839;      // Ethernet
    if (g_trayState.netKind == 1) return 0xE874;      // Wi-Fi
    return 0xE871;                                     // no connection
}

static wchar_t TrayGlyphVolume() {
    if (g_trayState.muted) return 0xE74F;             // muted speaker
    int p = g_trayState.volPercent;
    if (p <= 0) return 0xE992;
    if (p < 33) return 0xE993;
    if (p < 66) return 0xE994;
    return 0xE995;
}

static wchar_t TrayGlyphBattery() {
    int pct = g_trayState.batPercent;
    if (pct < 0) return 0xE850;               // no battery: the empty shell
    if (g_trayState.charging) {
        // E85A..E862 are "battery N + bolt"; E863 is the eco leaf, so stop at 8.
        int level = pct * 9 / 100;
        if (level > 8) level = 8;
        if (level < 0) level = 0;
        return (wchar_t)(0xE85A + level);
    }
    int level = pct * 10 / 100;               // E850 (empty) .. E859 (full)
    if (level > 9) level = 9;
    if (level < 0) level = 0;
    return (wchar_t)(0xE850 + level);
}

static std::wstring TrayTipText(int cell) {
    wchar_t buf[160];
    if (cell == 0) {
        if (g_trayState.netKind == 0) return L"未连接";
        if (g_trayState.netKind == 2) return L"以太网";
        swprintf_s(buf, L"%s（信号 %d%%）", g_trayState.netName, g_trayState.netQuality);
        return buf;
    }
    if (cell == 1) {
        if (g_trayState.muted) return L"音量：静音";
        swprintf_s(buf, L"音量：%d%%", g_trayState.volPercent);
        return buf;
    }
    if (g_trayState.batPercent < 0) return L"未检测到电池";
    swprintf_s(buf, g_trayState.charging ? L"电池：%d%%，正在充电" : L"电池：%d%%",
               g_trayState.batPercent);
    return buf;
}

static void TrayRepaint(Companion& c);

// ---------------------------------------------------------------- companion plumbing
// A DIB cannot be deleted while it is still selected into the DC, so park a 1x1 dummy
// there first (creating one lazily keeps this simple).
static HBITMAP g_dummyBmp = nullptr;
static HBITMAP DummyBitmap() {
    if (g_dummyBmp) return g_dummyBmp;
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = 1;
    bi.bmiHeader.biHeight = -1;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    g_dummyBmp = CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    return g_dummyBmp;
}

static void CompanionEnsureDib(Companion& c, int w, int h) {
    if (w <= 0 || h <= 0) return;
    if (c.bits && c.dibW == w && c.dibH == h) return;
    if (c.bmp) {
        if (c.dc && DummyBitmap()) SelectObject(c.dc, g_dummyBmp);
        DeleteObject(c.bmp);
        c.bmp = nullptr;
        c.bits = nullptr;
    }
    if (!c.dc) c.dc = CreateCompatibleDC(nullptr);
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    c.bmp = CreateDIBSection(c.dc, &bi, DIB_RGB_COLORS, &c.bits, nullptr, 0);
    if (c.bmp) SelectObject(c.dc, c.bmp);
    c.dibW = w;
    c.dibH = h;
}

static void CompanionPresent(Companion& c) {
    if (!c.hwnd || !c.bits) return;
    POINT src{0, 0};
    SIZE size{c.dibW, c.dibH};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, (BYTE)c.alpha, AC_SRC_ALPHA};
    POINT dst{c.rc.left, c.rc.top};
    // Same reason as Present(): when the window geometry changes in the same step as the
    // pixels, wait for a composition first, otherwise the new content shows at the old
    // place for a few milliseconds (the "glass slides" bug).
    //
    // ⛔ Only for *geometry* changes. `c.alpha != c.alphaTarget` used to be in this condition
    // too, and that is what made the pointer hitch while the companion faded in: DwmFlush waits
    // for the next vertical blank (measured 4.5-7.7 ms on this 144 Hz screen), so a 120 ms fade
    // stalled the UI thread - and with it WH_MOUSE_LL - eight to ten times in a row. A pure
    // alpha change cannot move pixels, so it needs no sync at all (HANDOVER_NEXT.md §3.19).
    if (g_cfg.presentSync == 2 && (c.dragging || c.resizing)) {
        DwmFlush();
    }
    UpdateLayeredWindow(c.hwnd, nullptr, &dst, &size, c.dc, &src, 0, &bf, ULW_ALPHA);
}

static bool CursorInCompanionGroup() {
    // Only the *default* group can keep the strip opaque: it is the one the strip belongs to.
    POINT p{};
    if (!GetCursorPos(&p)) return false;
    if (PointerInDefaultGroup(p)) return true;
    if (!g_trayBar.hwnd || !g_trayBar.enabled || g_trayBar.groupId != 1) return false;
    if (g_trayBar.alpha <= 0) return false;      // nothing of ours is on screen
    // Before a frame exists (companion disabled in the ini) fall back to strip-united-member.
    RECT group{};
    if (!GetWindowRect(g_hwnd, &group)) return false;
    UnionRect(&group, &group, &g_trayBar.rc);
    return PtInRect(&group, p) != FALSE;
}

// Move the window without moving the pixels twice: geometry and content in one go.
// `repaint` = the content changed, `publishAnchor` = the shell may need this rect right away
// (opening the flyout, end of a user drag). A plain follow move does neither: it just shifts
// the window, and the layered bitmap travels with it - re-presenting every frame for a pure
// move was wasted work.
static void CompanionSetRect(Companion& c, int x, int y, int w, int h, bool repaint,
                             bool publishAnchor = false) {
    bool sizeChanged = (w != c.rc.right - c.rc.left) || (h != c.rc.bottom - c.rc.top);
    const bool moved = (c.rc.left != x || c.rc.top != y);
    c.rc = RECT{x, y, x + w, y + h};
    // H3: a move does *not* invalidate the bake - the picture stays anchored to the desktop and
    // CompanionGlassTick re-crops it. A resize does (the bake has to cover the new size).
    if (moved) c.glassMovedAt = GetTickCount();
    if (sizeChanged) c.glass.dirty = true;
    if (repaint || sizeChanged) CompanionEnsureDib(c, w, h);
    if (repaint) TrayRepaint(c);
    if (IsWindow(c.hwnd)) {
        // SWP_NOZORDER: a pure move must not re-insert the window into the topmost band
        // every frame - that churns the compositor while the strip is being dragged.
        SetWindowPos(c.hwnd, nullptr, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
        if (repaint || sizeChanged) CompanionPresent(c);
    }
    // The quick settings panel anchors on this rect.
    if (publishAnchor) AnchorPublish(kAnchorQuickSettings, &c.rc, 8);
}

static void CompanionSave(Companion& c) {
    if (g_iniPath.empty()) return;
    wchar_t b[32];
    swprintf_s(b, L"%d", c.rc.left);
    WritePrivateProfileStringW(c.iniSection, L"x", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", c.rc.top);
    WritePrivateProfileStringW(c.iniSection, L"y", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", c.rc.right - c.rc.left);
    WritePrivateProfileStringW(c.iniSection, L"w", b, g_iniPath.c_str());
    swprintf_s(b, L"%d", c.rc.bottom - c.rc.top);
    WritePrivateProfileStringW(c.iniSection, L"h", b, g_iniPath.c_str());
    WritePrivateProfileStringW(c.iniSection, L"hasPos", L"1", g_iniPath.c_str());
    WritePrivateProfileStringW(c.iniSection, L"follow", c.follow ? L"1" : L"0",
                               g_iniPath.c_str());
    swprintf_s(b, L"%d", c.groupId);
    WritePrivateProfileStringW(c.iniSection, L"group", b, g_iniPath.c_str());
    DLog(L"tray bar: saved %ld,%ld %ldx%ld (follow=%d group=%d)", (long)c.rc.left,
         (long)c.rc.top, (long)(c.rc.right - c.rc.left), (long)(c.rc.bottom - c.rc.top),
         (int)c.follow, c.groupId);
}

// Called from SavePosition(): the attached windows moved with the strip, so their stored
// position has to follow, otherwise a restart would put them back where the strip used to be.
static void CompanionSaveAllPositions() {
    if (!g_trayBar.hwnd || !g_trayBar.enabled) return;
    CompanionSave(g_trayBar);
}

// The ini is read with the same helpers the strip uses (GetInt), so the semantics match.
static void CompanionLoad(Companion& c) {
    c.enabled = GetInt(c.iniSection, L"enabled", 1) != 0;
    c.follow = GetInt(c.iniSection, L"follow", 1) != 0;
    // G2: the group id is the real assignment; `follow` is kept for older builds and for the
    // common case (1 = default group, 0 = independent). No `group` key -> derive from `follow`.
    int defGroup = c.follow ? 1 : 0;
    c.groupId = GetInt(c.iniSection, L"group", defGroup);
    if (c.groupId < 0) c.groupId = 0;
    if (c.groupId > kMaxGroups) c.groupId = kMaxGroups;
    c.follow = (c.groupId == 1);
    // Style overrides (R4): absent (or negative) means "inherit the strip's style".
    c.padOv = GetInt(c.iniSection, L"pad", -1);
    c.gapOv = GetInt(c.iniSection, L"gap", -1);
    c.radiusOv = GetInt(c.iniSection, L"radius", -1);
    c.snapOv = GetInt(c.iniSection, L"snap", -1);

    int icon = g_cfg.iconSize < 40 ? 40 : g_cfg.iconSize;
    if (icon > g_cfg.maxIcon) icon = g_cfg.maxIcon;
    int pad = CompanionPad(c), gap = CompanionGap(c);
    int defW = kTrayCellCount * (icon + gap) - gap + pad * 2;
    int defH = icon + pad * 2;

    int w = GetInt(c.iniSection, L"w", defW);
    int h = GetInt(c.iniSection, L"h", defH);
    if (w < 40) w = 40;
    if (h < 40) h = 40;

    RECT sr{};
    GetWindowRect(g_hwnd, &sr);
    int defX = sr.right - w;
    int defY = sr.bottom + 8;
    int x = GetInt(c.iniSection, L"x", defX);
    int y = GetInt(c.iniSection, L"y", defY);
    c.rc = RECT{x, y, x + w, y + h};
    DLog(L"tray bar: loaded %ld,%ld %dx%d (follow=%d enabled=%d)", (long)x, (long)y, w, h,
         (int)c.follow, (int)c.enabled);
}

// ---- task 3: the snap (贴边方角) for a float window --------------------------------------
// Exactly the strip's rule (UpdateSnap): the *long* side decides, so a wide window only squares
// off when it hugs the top or the bottom edge, a tall one when it hugs the left or the right.
// The rect used is c.rc (the stored one), not GetWindowRect: a hidden companion has nothing on
// screen and its stored rect is where it will be shown.
static int CompanionSnapOn(const Companion& c) {
    return c.snapOv >= 0 ? c.snapOv : g_cfg.snap;
}

static void CompanionSnapUpdate(Companion& c) {
    float t[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    if (CompanionSnapOn(c)) {
        RECT wa = WorkAreaFor(c.hwnd ? c.hwnd : g_hwnd);
        bool vertical = (c.rc.bottom - c.rc.top) > (c.rc.right - c.rc.left);
        if (vertical) {
            if (c.rc.left <= wa.left) { t[0] = 0.0f; t[2] = 0.0f; }
            if (c.rc.right >= wa.right) { t[1] = 0.0f; t[3] = 0.0f; }
        } else {
            if (c.rc.top <= wa.top) { t[0] = 0.0f; t[1] = 0.0f; }
            if (c.rc.bottom >= wa.bottom) { t[2] = 0.0f; t[3] = 0.0f; }
        }
    }
    bool changed = false;
    for (int i = 0; i < 4; i++) {
        if (c.snapTarget[i] != t[i]) {
            c.snapTarget[i] = t[i];
            changed = true;
        }
    }
    if (changed)
        DLog(L"snap: %s corners TL=%.0f TR=%.0f BL=%.0f BR=%.0f rect=%ld,%ld-%ld,%ld on=%d",
             c.iniSection, t[0], t[1], t[2], t[3], (long)c.rc.left, (long)c.rc.top,
             (long)c.rc.right, (long)c.rc.bottom, CompanionSnapOn(c));
}

// One animation step, same easing/duration as the strip (AnimateCorners). True = repaint.
static bool CompanionSnapStep(Companion& c, DWORD now) {
    static DWORD last = 0;
    float dt = last ? (float)(now - last) : 30.0f;
    last = now;
    if (dt > 120.0f) dt = 120.0f;
    float k = 1.0f - expf(-dt / 45.0f);
    bool moved = false;
    for (int i = 0; i < 4; i++) {
        float d = c.snapTarget[i] - c.snapAnim[i];
        if (d > -0.004f && d < 0.004f) {
            if (c.snapAnim[i] != c.snapTarget[i]) {
                c.snapAnim[i] = c.snapTarget[i];
                moved = true;
            }
            continue;
        }
        c.snapAnim[i] += d * k;
        moved = true;
    }
    return moved;
}

// Called once per housekeeping tick. A hidden window snaps straight to its target (nothing to
// animate and nothing to repaint); a visible one steps like the strip does.
static void CompanionSnapTick(Companion& c, DWORD now) {
    if (!c.hwnd) return;
    CompanionSnapUpdate(c);
    if (!(c.alpha > 0 || c.alphaTarget > 0)) {
        for (int i = 0; i < 4; i++) c.snapAnim[i] = c.snapTarget[i];
        return;
    }
    if (CompanionSnapStep(c, now)) {
        TrayRepaint(c);
        CompanionPresent(c);
    }
}

// ---- H3: the float window's glass ------------------------------------------------------
// Rounded-rect coverage + rim for a *plain* window. The per-corner factors are part of the
// cache key, so a window that is settling into a screen edge rebuilds it and everything else
// keeps the cached one. (One shared mask: the companions take turns by (size, radius, corners);
// there is a single companion today.)
static std::vector<BYTE> g_fltCov, g_fltRim;
static int g_fltW = 0, g_fltH = 0, g_fltR = -1;
static float g_fltK[4] = {-2, -2, -2, -2};

static void EnsureFloatMask(int w, int h, int radius, const float* k) {
    bool same = (w == g_fltW && h == g_fltH && radius == g_fltR);
    for (int i = 0; same && i < 4; i++)
        if (k[i] != g_fltK[i]) same = false;
    if (same) return;
    g_fltCov.assign((size_t)w * h, 0);
    g_fltRim.assign((size_t)w * h, 0);
    int R = radius;
    int maxR = (w < h ? w : h) / 2;
    if (R > maxR) R = maxR;
    if (R < 0) R = 0;
    double cx = w / 2.0, cy = h / 2.0, hw = w / 2.0, hh = h / 2.0;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            double rr = CornerRadiusAtF(k, x, y, w, h, R);
            double qx = fabs(x + 0.5 - cx) - (hw - rr);
            double qy = fabs(y + 0.5 - cy) - (hh - rr);
            double ax = qx > 0 ? qx : 0;
            double ay = qy > 0 ? qy : 0;
            double inx = qx > qy ? qx : qy;
            if (inx > 0) inx = 0;
            double d = sqrt(ax * ax + ay * ay) + inx - rr;
            double cov = 0.5 - d;
            if (cov <= 0) continue;
            if (cov > 1) cov = 1;
            g_fltCov[(size_t)y * w + x] = (BYTE)(cov * 255);
            if (d > -2.5) {
                double e = 1.0 + d / 2.5;
                if (e > 0) {
                    DWORD ea = (DWORD)(e * cov * 0.22 * 255);
                    if (ea > 255) ea = 255;
                    g_fltRim[(size_t)y * w + x] = (BYTE)ea;
                }
            }
        }
    }
    g_fltW = w; g_fltH = h; g_fltR = radius;
    for (int i = 0; i < 4; i++) g_fltK[i] = k[i];
}

// Paint the baked backdrop into the companion's own DIB. The bake is a picture of the desktop
// with the same lift/tint/opacity the strip uses, so all that is left here is masking it to the
// rounded rect and adding the rim - the expensive part ran once, in BakeGlass().
// The offsets are *clamped* rather than refused: a window that slid out of its bake keeps a
// glass body that lags behind the desktop (exactly what the strip does in the same situation)
// instead of flashing a different background for the length of a drag.
static bool CompanionPaintGlass(Companion& c) {
    const GlassTarget& g = c.glass;
    if (!g.valid || !g.bits) return false;
    const int w = c.dibW, h = c.dibH;
    if (w <= 0 || h <= 0 || g.w < w || g.h < h) return false;
    int ox = c.rc.left - g.origin.x, oy = c.rc.top - g.origin.y;
    if (ox < 0) ox = 0;
    if (oy < 0) oy = 0;
    if (ox > g.w - w) ox = g.w - w;
    if (oy > g.h - h) oy = g.h - h;
    EnsureFloatMask(w, h, RadiusForPercent(w, h, CompanionRadiusPercent(c)), c.snapAnim);
    for (int y = 0; y < h; y++) {
        const uint32_t* src = (const uint32_t*)g.bits + (size_t)(oy + y) * g.w + ox;
        const BYTE* covRow = &g_fltCov[(size_t)y * w];
        const BYTE* rimRow = &g_fltRim[(size_t)y * w];
        for (int x = 0; x < w; x++) {
            DWORD a = covRow[x];
            if (!a) continue;
            // the bake is opaque, so the glass body is too: coverage is the only alpha
            SetPixelPremul(x, y, (a << 24) | (src[x] & 0x00FFFFFF));
            DWORD ea = rimRow[x];
            if (ea) SetPixelPremul(x, y, (ea << 24) | 0x00FFFFFF);
        }
    }
    return true;
}

static void TrayRepaint(Companion& c) {
    if (!c.hwnd || !c.bits) return;

    // retarget the shared pixel helpers at our own DIB (same as GridPaint)
    void* savePaint = g_paintBits;
    int savePW = g_paintW, savePH = g_paintH;
    g_paintBits = c.bits;
    g_paintW = c.dibW;
    g_paintH = c.dibH;

    memset(c.bits, 0, (size_t)c.dibW * c.dibH * 4);

    RECT all{0, 0, c.dibW, c.dibH};
    // A layered window is hit-tested through its alpha, and the glyphs have holes in them -
    // hovering/clicking the middle of a speaker would fall straight through to whatever is
    // behind. This wash (4% white, invisible against any wallpaper) makes the whole bar one
    // button, which is exactly what the user asked for ("clicking anywhere opens the menu").
    // H2: ackground=solid paints a real colour here (its opacity doubles as the clickable
    // area, so no extra wash is needed). 透过背后 keeps the 4% wash - the glass layer that
    // would sit on top of the desktop behind it is H3's work.
    DWORD bgFill = 0x0AFFFFFF;
    {
        int bgMode = GetInt(L"traybar", L"bgMode", -1);
        if (bgMode < 0 || bgMode > 2) bgMode = g_cfg.bgMode;
        if (bgMode == 2) {
            int a = GetInt(L"traybar", L"solidOpacity", -1);
            if (a < 0) a = g_cfg.solidOpacity;
            if (a > 255) a = 255;
            if (a < 3) a = 3;
            bgFill = ((DWORD)a << 24) | (g_hue[1] & 0x00FFFFFFu);   // the window's 色调
        }
    }
    FillRound4F(all, RadiusForPercent(all.right, all.bottom, CompanionRadiusPercent(c)),
                c.snapAnim, bgFill);
    // H3: with the glass layer on, the baked backdrop replaces the wash as the background. It
    // lands on top of the fill, so the fill is still the clickable area while the first bake
    // is missing (and the wash is invisible anyway).
    if (CompanionUsesGlass(c)) CompanionPaintGlass(c);
    else if (CompanionBgMode(c) == 1) {
        // picture background: fill the rounded rect from the cached picture
        if (EnsureImage(g_imgTray, ImagePathFor(L"traybar"), c.dibW, c.dibH, 1)) {
            EnsureFloatMask(c.dibW, c.dibH,
                            RadiusForPercent(c.dibW, c.dibH, CompanionRadiusPercent(c)),
                            c.snapAnim);
            PaintImageBg(g_imgTray, c.dibW, c.dibH, g_fltCov.data(), g_fltRim.data(), g_hue[1], g_glass[1]);
        }
    }

    RECT cells[kTrayCellCount];
    TrayCells(c, cells);
    int icon = CompanionIconPx(c);

    for (int i = 0; i < kTrayCellCount; i++) {
        const RECT& cellRect = cells[i];
        if (i == c.hoverCell) {
            FillRound(c.dc, cellRect, RadiusFor(cellRect.right - cellRect.left,
                                                cellRect.bottom - cellRect.top) / 2 + 2,
                      ((DWORD)g_cfg.hoverAlpha << 24) | 0x00FFFFFF);
        }
        wchar_t glyph = (i == 0) ? TrayGlyphNet() : (i == 1) ? TrayGlyphVolume()
                                                             : TrayGlyphBattery();
        DrawGlyphInCell(cellRect, glyph, 0xE8FFFFFF, 0.78f);
    }

    g_paintBits = savePaint;
    g_paintW = savePW;
    g_paintH = savePH;
}

// ---------------------------------------------------------------- tooltip
static void CompanionTooltipEnsure(Companion& c) {
    if (c.tipWnd || !c.hwnd) return;
    c.tipWnd = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr,
                               WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX, CW_USEDEFAULT,
                               CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, nullptr, nullptr,
                               GetModuleHandleW(nullptr), nullptr);
    if (!c.tipWnd) {
        DLog(L"tray bar: tooltip create failed err=%lu", (unsigned long)GetLastError());
        return;
    }

    // This shell's tooltip only accepts the V1 TOOLINFO layout for TTM_ADDTOOL (measured:
    // sizeof(TOOLINFO) = 72 is rejected, TTTOOLINFOW_V1_SIZE is accepted), so try the small
    // layout first and fall back to the full one.
    RECT cells[kTrayCellCount];
    TrayCells(c, cells);
    const int sizes[] = {(int)TTTOOLINFOW_V1_SIZE, (int)sizeof(TOOLINFOW)};
    for (int size : sizes) {
        c.tipInfo = TOOLINFOW{};
        c.tipInfo.cbSize = (UINT)size;
        c.tipInfo.uFlags = TTF_TRACK | TTF_ABSOLUTE;
        c.tipInfo.hwnd = c.hwnd;
        c.tipInfo.uId = 0x51;
        c.tipInfo.rect = cells[0];
        c.tipInfo.lpszText = const_cast<LPWSTR>(L"");
        SetLastError(0);
        LRESULT added = SendMessageW(c.tipWnd, TTM_ADDTOOLW, 0, (LPARAM)&c.tipInfo);
        DLog(L"tray bar: tooltip %p add cb=%d -> %ld (err=%lu)", (void*)c.tipWnd, size,
             (long)added, (unsigned long)GetLastError());
        if (added) {
            // Warm it up once, off screen. The first TTM_TRACKACTIVATE costs ~125 ms; paying it
            // here (during load) means every later hover is a cheap move + text change.
            const double t0 = NowMs();
            c.tipInfo.lpszText = const_cast<LPWSTR>(L"");
            SendMessageW(c.tipWnd, TTM_TRACKPOSITION, 0, MAKELPARAM(-4000, -4000));
            SendMessageW(c.tipWnd, TTM_TRACKACTIVATE, TRUE, (LPARAM)&c.tipInfo);
            c.tipActive = true;
            DLog(L"tray bar: tooltip warmed up in %.1f ms", NowMs() - t0);
            return;
        }
    }
}

static void CompanionTooltipShow(Companion& c, int cell) {
    if (!c.tipWnd) return;
    const double t0 = NowMs();
    if (cell < 0) {
        // Hide by moving it off screen instead of TTM_TRACKACTIVATE FALSE: re-activating is
        // what costs ~125 ms, and that used to happen on the first hover of every appearance.
        c.tipInfo.lpszText = const_cast<LPWSTR>(L"");
        SendMessageW(c.tipWnd, TTM_UPDATETIPTEXTW, 0, (LPARAM)&c.tipInfo);
        SendMessageW(c.tipWnd, TTM_TRACKPOSITION, 0, MAKELPARAM(-4000, -4000));
        const double d = NowMs() - t0;
        if (d >= 3.0) DLog(L"slow: tooltip hide %.1f ms", d);
        return;
    }
    static std::wstring text;
    text = TrayTipText(cell);
    c.tipInfo.lpszText = const_cast<LPWSTR>(text.c_str());
    SendMessageW(c.tipWnd, TTM_UPDATETIPTEXTW, 0, (LPARAM)&c.tipInfo);
    const double t1 = NowMs();

    RECT cells[kTrayCellCount];
    TrayCells(c, cells);
    // centre of the hovered cell, just below it (screen coordinates)
    POINT pt{c.rc.left + (cells[cell].left + cells[cell].right) / 2,
             c.rc.top + cells[cell].bottom + 6};
    SendMessageW(c.tipWnd, TTM_TRACKPOSITION, 0, MAKELPARAM(pt.x, pt.y));
    const double t2 = NowMs();
    // Only (re)activate if it is not already up: that call is the 125 ms one.
    LRESULT on = 1;
    if (!c.tipActive) {
        on = SendMessageW(c.tipWnd, TTM_TRACKACTIVATE, TRUE, (LPARAM)&c.tipInfo);
        if (on) c.tipActive = true;
    }
    const double t3 = NowMs();
    if (t3 - t0 >= 3.0) {
        DLog(L"slow: tooltip cell=%d text %.1f, position %.1f, activate %.1f ms (track=%ld)",
             cell, t1 - t0, t2 - t1, t3 - t2, (long)on);
    }
    static int logged = 0;
    if (logged < 6) {
        logged++;
        DLog(L"tray bar: tooltip cell=%d text='%s' at %ld,%ld track=%ld", cell, text.c_str(),
             (long)pt.x, (long)pt.y, (long)on);
    }
}

// ---------------------------------------------------------------- groups (G2)
// A group is a first-class thing: settings + one frame window + a member list (G1) and, since
// G2, there can be several of them. The strip can only ever belong to group 1 (user,
// 2026-11-16); the other groups consist of companion windows that were moved there from a
// companion's context menu.
//   * group 1 keeps the original rule: the frame and its companions appear while the pointer is
//     on the strip, and stay while it is anywhere inside the frame;
//   * a group without the strip has nothing to "be entered" by: its members therefore live with
//     the normal distance fade (otherwise they could never be hovered), and its *frame* fades in
//     when the pointer is on one of its members or inside it;
//   * `enabled` only decides whether the 1 px line is painted - the board keeps working;
//   * a group with fewer than two members has no frame at all (a group of one is not a group);
//     its settings are then reachable from the single member's own menu ("叠加上组的菜单").
struct GroupMember {
    HWND hwnd = nullptr;
    Companion* comp = nullptr;   // nullptr = the strip
    RECT rc{0, 0, 0, 0};
};
static const int kGroupMaxMembers = 8;

// One frame being dragged by its margin ring (R3), now per group.
struct GroupScaleState {
    bool active = false;
    int edges = 0;               // 1 left, 2 right, 4 top, 8 bottom (bits as in EdgeAt)
    RECT box0{};
    POINT origin{};
    int count = 0;
    GroupMember members0[kGroupMaxMembers];
    int lastSx1000 = 1000, lastSy1000 = 1000;
};

// One group being dragged (G1/G2), per group.
struct GroupDragState {
    bool active = false;         // pressed on the board (or redirected from a member)
    bool moving = false;         // past the 4 px threshold
    POINT origin{};              // screen px at press
    POINT grab{};                // cursor - (g_cfg.x, g_cfg.y) at press   [group 1]
    int count = 0;               // member rects at press                    [group N>1]
    GroupMember members0[kGroupMaxMembers];
};

struct Group {
    int id = 1;                  // 1 = default (owns the strip); ini: [group] / [group.N]
    // settings (per group)
    bool enabled = true;         // paint the 1 px line?
    bool blockResize = false;    // members cannot resize themselves
    bool blockMove = false;      // dragging a member moves the whole group
    int margin = 8;
    int lineAlpha = 64;
    int lineWidth = 1;
    int radius = 12;
    // H2b: the fade distances belong to the *group* now (user 2026-11-17), and the distance is
    // measured to the group's own rectangle. -1 = not loaded yet -> inherit [dock].
    int fadeStart = -1;
    int fadeEnd = -1;
    // ---- task 4: 贴边隐藏 ----------------------------------------------------------------
    // The group glues itself to the screen perimeter (kHideGap inside the edge) and slides out
    // of the screen when the pointer leaves it; a thin band along that screen edge brings it
    // back. Geometry only, applied to the members - a single-member group works with no special
    // case (GroupBounds() covers it; GroupBoxMembers() deliberately does not, so a one-member
    // group simply has no frame to slide off).
    bool hideEdge = false;        // [group] hideEdge (= hideMode 1), kept as the runtime mirror
    // 隐藏方案 (user, 2026-11-23): 0 = 鼠标距离 (the fade), 1 = 贴边隐藏, 2 = 从不 (always visible).
    // It replaces the old boolean switch and decides which sub-rows the group page shows.
    int hideMode = 0;
    int wakeExt = 4;              // [group] wakeExt 0..10: the band's thickness
    bool wakeVisible = false;     // [group] wakeVisible: always painted / only flashing
    bool wakeModeHover = false;   // [group] wakeMode: 0 = click the band, 1 = move into it
    // runtime
    int hideSide = -1;            // 0 top, 1 right, 2 bottom, 3 left; -1 = not attached yet
    float hideSlide = 1.0f;       // 1 = awake (at the inset), 0 = fully out of the screen
    float hideSlideTarget = 1.0f;
    int hideShift = 0;            // px currently applied outwards along the perpendicular axis
    bool hideWakeClick = false;   // the wake window received a click (click mode)
    DWORD hideArmAt = 0;          // no hiding before this (seen turning the switch on)
    DWORD hideFlashStart = 0;     // the 2 s flash (2 x 1 s) after an auto-hide / a wakeExt change
    DWORD hideFlashUntil = 0;
    HWND wakeHwnd = nullptr;      // the 唤出区域 window
    RECT wakeRc{0, 0, 0, 0};      // its rect while hidden (screen px)
    // The 唤出区域's colour. A group has no tone of its own (the tone belongs to a *window*, see
    // g_hue[]), so it carries one here; unset = use the strip's tone.
    DWORD hue = 0;
    bool hasHue = false;
    // One fade for the whole group (H2b): the strip and the companions used to compute their own,
    // which made them visibly fade independently (user, 2026-11-22). fadeTarget is recomputed on
    // the housekeeping tick, fadeNow steps towards it - both read by every member of the group.
    int fadeTarget = 255;
    int fadeNow = 255;
    // frame window + fade
    HWND hwnd = nullptr;
    RECT rc{0, 0, 0, 0};         // screen px, empty when there is nothing to frame
    int alpha = 0, alphaTarget = 0;
    HDC dc = nullptr;
    HBITMAP bmp = nullptr;
    void* bits = nullptr;
    int dibW = 0, dibH = 0;      // grow-only allocation (scaling changes the frame every message)
    int paintedW = 0, paintedH = 0;
    // state
    bool shown = false;          // latched visibility (was a function-local static per group)
    GroupScaleState scale;
    GroupDragState drag;
};
static Group g_groups[kMaxGroups];
static int g_groupCount = 1;     // how many ids are in use (1 = the default group alone)

static Group* GroupById(int id) {
    if (id < 1 || id > kMaxGroups) return nullptr;
    return &g_groups[id - 1];
}
static Group& DefaultGroup() { return g_groups[0]; }
static Group* GroupOfWindow(HWND h) {
    if (!h) return nullptr;
    int id = (int)(INT_PTR)GetWindowLongPtrW(h, GWLP_USERDATA);
    return GroupById(id);
}

static void GroupSectionName(int id, wchar_t* buf, size_t cch) {
    if (id <= 1) wcscpy_s(buf, cch, L"group");
    else swprintf_s(buf, cch, L"group.%d", id);
}

// The two group switches, asked per *window*: a companion uses its own group's flags, the strip
// uses the default group's (pass nullptr for the strip). One place decides, so the strip, the
// companions and the menus cannot disagree.
static bool GroupBlocksResize(Companion* c) {
    Group* g = c ? GroupById(c->groupId) : &DefaultGroup();
    return g ? g->blockResize : false;
}
static bool GroupBlocksMove(Companion* c) {
    Group* g = c ? GroupById(c->groupId) : &DefaultGroup();
    return g ? g->blockMove : false;
}

static void GroupLoad(Group& g) {
    wchar_t sec[32];
    GroupSectionName(g.id, sec, 32);
    g.enabled = GetInt(sec, L"enabled", 1) != 0;
    g.blockResize = GetInt(sec, L"blockResize", 0) != 0;
    g.blockMove = GetInt(sec, L"blockMove", 0) != 0;
    g.margin = GetInt(sec, L"margin", 8);
    if (g.margin < 0) g.margin = 0;
    if (g.margin > 64) g.margin = 64;
    g.lineAlpha = GetInt(sec, L"lineAlpha", 64);
    if (g.lineAlpha < 0) g.lineAlpha = 0;
    if (g.lineAlpha > 255) g.lineAlpha = 255;
    g.lineWidth = GetInt(sec, L"lineWidth", 1);
    if (g.lineWidth < 1) g.lineWidth = 1;
    if (g.lineWidth > 4) g.lineWidth = 4;
    g.radius = GetInt(sec, L"radius", 12);
    if (g.radius < 0) g.radius = 0;
    if (g.radius > 64) g.radius = 64;
    // H2b: fade distances per group; the defaults come from [dock] so an existing profile keeps
    // exactly the feel it had (they used to be global).
    g.fadeStart = GetInt(sec, L"fadeStart", g_cfg.fadeStart);
    g.fadeEnd = GetInt(sec, L"fadeEnd", g_cfg.fadeEnd);
    if (g.fadeStart < 0) g.fadeStart = 0;
    if (g.fadeEnd <= g.fadeStart) g.fadeEnd = g.fadeStart + 1;
    // task 4: 贴边隐藏 + its three sub-settings
    g.hideMode = GetInt(sec, L"hideMode", -1);
    if (g.hideMode < 0 || g.hideMode > 2) {
        // a profile from before 隐藏方案 只 has the boolean switch
        g.hideMode = GetInt(sec, L"hideEdge", 0) != 0 ? 1 : 0;
    }
    g.hideEdge = (g.hideMode == 1);
    g.wakeExt = GetInt(sec, L"wakeExt", 4);
    if (g.wakeExt < 0) g.wakeExt = 0;
    if (g.wakeExt > 10) g.wakeExt = 10;
    g.wakeVisible = GetInt(sec, L"wakeVisible", 0) != 0;
    g.wakeModeHover = GetInt(sec, L"wakeMode", 0) != 0;
    // task 4: the 唤出区域 colour; empty = follow the strip's tone (see HueFor())
    {
        std::wstring hs = GetStr(sec, L"hue");
        g.hasHue = !hs.empty();
        if (g.hasHue) g.hue = ParseHexRgb(hs, g_hue[0]) & 0x00FFFFFFu;
    }
}

static void GroupSaveFlag(Group& g, const wchar_t* key, bool value) {
    wchar_t sec[32];
    GroupSectionName(g.id, sec, 32);
    WritePrivateProfileStringW(sec, key, value ? L"1" : L"0", g_iniPath.c_str());
}

// Members in draw order: the strip (group 1 only), then the companions assigned to this group.
static int GroupMembers(Group& g, GroupMember* out) {
    int n = 0;
    if (g.id == 1 && g_hwnd && n < kGroupMaxMembers) {
        GroupMember m;
        m.hwnd = g_hwnd;
        m.comp = nullptr;
        GetWindowRect(g_hwnd, &m.rc);
        out[n++] = m;
    }
    if (g_trayBar.hwnd && g_trayBar.enabled && g_trayBar.groupId == g.id &&
        n < kGroupMaxMembers) {
        GroupMember m;
        m.hwnd = g_trayBar.hwnd;
        m.comp = &g_trayBar;
        m.rc = g_trayBar.rc;     // the intended rect: the follow path keeps it in sync
        out[n++] = m;
    }
    return n;
}

// The frame needs at least two members: a frame around one window is pure noise.
static bool GroupBoxMembers(Group& g, RECT* out) {
    GroupMember m[kGroupMaxMembers];
    int n = GroupMembers(g, m);
    if (n < 2) return false;
    *out = m[0].rc;
    for (int i = 1; i < n; i++) UnionRect(out, out, &m[i].rc);
    return true;
}

// The group's rectangle even when it holds a single member: the *frame* needs two members (a
// frame around one window is noise), but the fade distance is measured against the group for
// every group (H2b), including a one-member one.
static bool GroupBounds(Group& g, RECT* out) {
    GroupMember m[kGroupMaxMembers];
    int n = GroupMembers(g, m);
    if (n < 1) return false;
    *out = m[0].rc;
    for (int i = 1; i < n; i++) UnionRect(out, out, &m[i].rc);
    InflateRect(out, g.margin, g.margin);
    return true;
}

static bool GroupBoxRect(Group& g, RECT* out) {
    RECT r{};
    if (!GroupBoxMembers(g, &r)) return false;
    InflateRect(&r, g.margin, g.margin);
    *out = r;
    return true;
}

// Is any group being dragged or scaled right now? (visibility whitelists, bake suppression)
static bool AnyGroupScaling() {
    for (int i = 0; i < g_groupCount; i++)
        if (g_groups[i].scale.active) return true;
    return false;
}
static bool AnyGroupDragging() {
    for (int i = 0; i < g_groupCount; i++)
        if (g_groups[i].drag.active) return true;
    return false;
}
// Is the *default* group (the one that owns the strip) busy? Only that one can move the strip,
// so only that one has to suppress the backdrop capture / keep the strip opaque.
static bool DefaultGroupBusy() {
    const Group& g = DefaultGroup();
    return g.scale.active || g.drag.active;
}

// Is the pointer "in the default group"? Its frame, or a gesture that currently owns it. The
// strip uses this to stay fully opaque (Q1, §8 of PLAN_COMPANION).
static bool PointerInDefaultGroup(POINT p) {
    Group& g = DefaultGroup();
    if (g.scale.active || g.drag.active) return true;
    RECT box{};
    if (GroupBoxRect(g, &box)) return PtInRect(&box, p) != FALSE;
    return false;
}

// Grow-only DIB: a scale drag changes the frame size on every mouse message.
static void GroupEnsureDib(Group& g, int w, int h) {
    if (w <= 0 || h <= 0) return;
    if (g.bits && g.dibW >= w && g.dibH >= h) return;
    int aw = (w + 63) & ~63;
    int ah = (h + 63) & ~63;
    if (g.bmp) {
        if (g.dc && DummyBitmap()) SelectObject(g.dc, g_dummyBmp);
        DeleteObject(g.bmp);
        g.bmp = nullptr;
        g.bits = nullptr;
    }
    if (!g.dc) g.dc = CreateCompatibleDC(nullptr);
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = aw;
    bi.bmiHeader.biHeight = -ah;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    g.bmp = CreateDIBSection(g.dc, &bi, DIB_RGB_COLORS, &g.bits, nullptr, 0);
    if (g.bmp) SelectObject(g.dc, g.bmp);
    g.dibW = aw;
    g.dibH = ah;
}

// The ring the pointer may grab to scale the group: it lives *inside* the margin, so it can
// never cover a member. Painted at alpha 4 - invisible, but hit-testable.
static int GroupGrabBand(Group& g) {
    int band = g.margin;
    if (band > 10) band = 10;
    if (band < 0) band = 0;
    return band;
}

// The board: alpha 1 premultiplied white (0.4%) across the whole rounded shape. Invisible, but
// a layered window is hit-tested through its alpha, so this is what makes the empty space
// inside the frame grabbable. Rounded corners are honoured by zeroing the pixels outside the arcs.
static void GroupPaintBoard(Group& g, int w, int h, int radius) {
    if (!g.bits || w <= 0 || h <= 0) return;
    const DWORD board = 0x01010101u;
    DWORD* px = (DWORD*)g.bits;
    const int stride = g.dibW;
    for (int y = 0; y < h; y++) {
        DWORD* row = px + (size_t)y * stride;
        for (int x = 0; x < w; x++) row[x] = board;
    }
    int r = radius;
    int maxR = (w < h ? w : h) / 2;
    if (r > maxR) r = maxR;
    if (r <= 0) return;
    for (int cy = 0; cy < 2; cy++) {
        for (int cx = 0; cx < 2; cx++) {
            int ox = cx ? w - r : 0;
            int oy = cy ? h - r : 0;
            double ccx = cx ? (double)w - r : (double)r;
            double ccy = cy ? (double)h - r : (double)r;
            for (int y = oy; y < oy + r; y++) {
                for (int x = ox; x < ox + r; x++) {
                    double dx = x + 0.5 - ccx, dy = y + 0.5 - ccy;
                    if (dx * dx + dy * dy > (double)r * r) px[(size_t)y * stride + x] = 0;
                }
            }
        }
    }
}

static int GroupCornerSize(Group& g);      // defined with GroupEdgeAt below

static void GroupPaint(Group& g, int w, int h) {
    if (!g.bits || w <= 0 || h <= 0) return;
    if (w > g.dibW || h > g.dibH) return;
    void* savePaint = g_paintBits;
    int savePW = g_paintW, savePH = g_paintH;
    g_paintBits = g.bits;
    g_paintW = g.dibW;
    g_paintH = g.dibH;
    for (int y = 0; y < h; y++)
        memset((BYTE*)g.bits + (size_t)y * g.dibW * 4, 0, (size_t)w * 4);
    GroupPaintBoard(g, w, h, g.radius);
    int band = GroupGrabBand(g);
    if (band > 0) FillRoundRing(w, h, g.radius, band + g.lineWidth, 0x04FFFFFF);
    // ⛔ The corner handles used to be only whatever the rounded arc left inside the band - at
    // radius ~22 that is a sliver of a few pixels, which felt like "只有一个像素能触发"
    // (user, 2026-11-21). A layered window is hit-tested through its alpha, so the corner squares
    // have to be painted, not just tested for: 1.6 % white, invisible, but a 22x22 target.
    {
        const int cz = GroupCornerSize(g);
        const DWORD hit = 0x04FFFFFF;
        RECT c[4] = {RECT{0, 0, cz, cz}, RECT{w - cz, 0, w, cz}, RECT{0, h - cz, cz, h},
                     RECT{w - cz, h - cz, w, h}};
        for (const RECT& r : c) FillRound(g_memDC, r, 8, hit);
    }
    if (g.enabled)
        FillRoundRing(w, h, g.radius, g.lineWidth, ((DWORD)g.lineAlpha << 24) | 0x00FFFFFF);
    g_paintBits = savePaint;
    g_paintW = savePW;
    g_paintH = savePH;
    g.paintedW = w;
    g.paintedH = h;
}

static void GroupPresent(Group& g) {
    if (!g.hwnd || !g.bits) return;
    int w = g.rc.right - g.rc.left;
    int h = g.rc.bottom - g.rc.top;
    if (w <= 0 || h <= 0) return;
    POINT src{0, 0};
    SIZE size{w, h};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, (BYTE)g.alpha, AC_SRC_ALPHA};
    POINT dst{g.rc.left, g.rc.top};
    // No DwmFlush on purpose: a pure move is SetWindowPos alone, a scale is driven per mouse
    // message like the strip's own edge drag - there is no "new content at old geometry" pair
    // to keep in one composition, only the fade alpha and the ring change.
    UpdateLayeredWindow(g.hwnd, nullptr, &dst, &size, g.dc, &src, 0, &bf, ULW_ALPHA);
}

// Force a repaint with unchanged geometry (a menu toggle changed pixels only).
static void GroupRepaint(Group& g) {
    int w = g.rc.right - g.rc.left;
    int h = g.rc.bottom - g.rc.top;
    if (w <= 0 || h <= 0 || !g.hwnd) return;
    GroupEnsureDib(g, w, h);
    GroupPaint(g, w, h);
    GroupPresent(g);
}

// Repaint only when the frame's size changed: a strip drag is a pure translation (no repaint).
static void GroupPlace(Group& g) {
    int w = g.rc.right - g.rc.left;
    int h = g.rc.bottom - g.rc.top;
    if (w <= 0 || h <= 0 || !g.hwnd) return;
    bool sizeChanged = (w != g.paintedW || h != g.paintedH);
    if (sizeChanged) {
        GroupEnsureDib(g, w, h);
        GroupPaint(g, w, h);
    }
    SetWindowPos(g.hwnd, nullptr, g.rc.left, g.rc.top, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
    if (sizeChanged) GroupPresent(g);
    DLog(L"group %d: place %ld,%ld %dx%d repaint=%d painted=%dx%d alpha=%d target=%d en=%d vis=%d",
         g.id, (long)g.rc.left, (long)g.rc.top, w, h, (int)sizeChanged, g.paintedW, g.paintedH,
         g.alpha, g.alphaTarget, (int)g.enabled, (int)IsWindowVisible(g.hwnd));
}

static void GroupRecompute(Group& g) {
    RECT want{};
    if (!GroupBoxRect(g, &want)) {
        g.rc = RECT{0, 0, 0, 0};
        if (g.hwnd) ShowWindow(g.hwnd, SW_HIDE);
        DLog(L"group %d: no frame (members<2) -> hidden (alpha=%d target=%d)", g.id, g.alpha,
             g.alphaTarget);
        return;
    }
    g.rc = want;
    GroupPlace(g);
}

// The strip moved by (dx,dy): the frames/members that follow are translated by the same delta,
// so they land in the strip's composition (called from CompanionFollowTo, on the frame path).
static void GroupTranslate(Group& g, int dx, int dy) {
    if ((!dx && !dy) || g.rc.right <= g.rc.left) return;
    OffsetRect(&g.rc, dx, dy);
    if (g.hwnd && IsWindowVisible(g.hwnd))
        SetWindowPos(g.hwnd, nullptr, g.rc.left, g.rc.top, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

// ---------------------------------------------------------------- group scaling (R3)
static void GroupDragEnd(Group& g);      // GroupScaleBegin cancels a drag if both are pressed

static bool GroupScaling() { return AnyGroupScaling(); }

// Which frame edge(s) is the pointer on? The grab band is the margin ring painted at alpha 4.
// The square in each corner that acts as a two-axis resize handle. Bigger than the edge band on
// purpose: a corner is the hardest thing to hit, and the margin is the only place it can live.
static int GroupCornerSize(Group& g) {
    int cz = GroupGrabBand(g) + 10;
    if (cz < 16) cz = 16;
    if (cz > 28) cz = 28;
    return cz;
}

static int GroupEdgeAt(Group& g, POINT pClient, const RECT& client) {
    int w = client.right - client.left, h = client.bottom - client.top;
    const int cz = GroupCornerSize(g);
    const bool lx = pClient.x < cz, rx = pClient.x >= w - cz;
    const bool ty = pClient.y < cz, by = pClient.y >= h - cz;
    // A corner square is a resize handle as a whole, whatever the rounded outline does there.
    if ((lx || rx) && (ty || by)) return (lx ? 1 : 2) | (ty ? 4 : 8);
    int band = GroupGrabBand(g) + g.lineWidth;
    if (band <= 0) return 0;
    int edges = 0;
    if (pClient.x < band) edges |= 1;
    else if (pClient.x >= w - band) edges |= 2;
    if (pClient.y < band) edges |= 4;
    else if (pClient.y >= h - band) edges |= 8;
    return edges;
}

static RECT ScaleMemberRect(const RECT& m0, const RECT& bb0, const RECT& nbb, double sx,
                            double sy) {
    RECT r{};
    r.left = nbb.left + (int)floor((m0.left - bb0.left) * sx + 0.5);
    r.top = nbb.top + (int)floor((m0.top - bb0.top) * sy + 0.5);
    int w = (int)floor((m0.right - m0.left) * sx + 0.5);
    int h = (int)floor((m0.bottom - m0.top) * sy + 0.5);
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    r.right = r.left + w;
    r.bottom = r.top + h;
    return r;
}

static void GroupScaleTo(Group& g, POINT cur) {
    GroupScaleState& st = g.scale;
    const int margin = g.margin;
    RECT bb0 = st.box0;
    InflateRect(&bb0, -margin, -margin);
    int bb0w = bb0.right - bb0.left, bb0h = bb0.bottom - bb0.top;
    if (bb0w < 1 || bb0h < 1) return;

    int dx = cur.x - st.origin.x;
    int dy = cur.y - st.origin.y;
    int wantW = bb0w, wantH = bb0h;
    if (st.edges & 1) wantW -= dx;
    else if (st.edges & 2) wantW += dx;
    if (st.edges & 4) wantH -= dy;
    else if (st.edges & 8) wantH += dy;

    // No member may fall below its own minimum (same rule their own edge drags use).
    double sxMin = 0.0, syMin = 0.0;
    auto account = [&](const RECT& m0, int memberMin) {
        int w0 = m0.right - m0.left, h0 = m0.bottom - m0.top;
        if (w0 > 0) {
            double f = (double)memberMin / w0;
            if (f > sxMin) sxMin = f;
        }
        if (h0 > 0) {
            double f = (double)memberMin / h0;
            if (f > syMin) syMin = f;
        }
    };
    for (int i = 0; i < st.count; i++) {
        const GroupMember& m = st.members0[i];
        int minSide = m.comp ? (g_cfg.minIcon + CompanionPad(*m.comp) * 2)
                             : (g_cfg.minIcon + g_cfg.pad * 2);
        account(m.rc, minSide);
    }

    double sx = (double)wantW / bb0w;
    double sy = (double)wantH / bb0h;
    if (sx < sxMin) sx = sxMin;
    if (sy < syMin) sy = syMin;
    if (sx > 8.0) sx = 8.0;
    if (sy > 8.0) sy = 8.0;

    int nw = (int)floor(bb0w * sx + 0.5);
    int nh = (int)floor(bb0h * sy + 0.5);
    if (nw < 1) nw = 1;
    if (nh < 1) nh = 1;
    RECT nbb = bb0;
    if (st.edges & 1) nbb.left = nbb.right - nw;
    else nbb.right = nbb.left + nw;
    if (st.edges & 4) nbb.top = nbb.bottom - nh;
    else nbb.bottom = nbb.top + nh;

    st.lastSx1000 = (int)(sx * 1000.0 + 0.5);
    st.lastSy1000 = (int)(sy * 1000.0 + 0.5);

    for (int i = 0; i < st.count; i++) {
        const GroupMember& m = st.members0[i];
        RECT nr = ScaleMemberRect(m.rc, bb0, nbb, sx, sy);
        int nw2 = nr.right - nr.left, nh2 = nr.bottom - nr.top;
        if (m.comp) {
            CompanionSetRect(*m.comp, nr.left, nr.top, nw2, nh2, true);
            AnchorPublish(kAnchorQuickSettings, &m.comp->rc, 8);
        } else {
            g_cfg.x = nr.left;
            g_cfg.y = nr.top;
            g_cfg.w = nw2;
            g_cfg.h = nh2;
            SetWindowPos(g_hwnd, HWND_TOPMOST, nr.left, nr.top, nw2, nh2, SWP_NOACTIVATE);
        }
    }
    GroupRecompute(g);
}

static void GroupScaleBegin(Group& g, POINT cur, int edges) {
    if (g.drag.active) GroupDragEnd(g);
    g.scale.active = true;
    g.scale.edges = edges;
    g.scale.box0 = g.rc;
    g.scale.count = GroupMembers(g, g.scale.members0);
    g.scale.origin = cur;
    g.scale.lastSx1000 = g.scale.lastSy1000 = 1000;
    DLog(L"group %d: scale start edges=%d frame=%ld,%ld %ldx%ld members=%d", g.id, edges,
         (long)g.rc.left, (long)g.rc.top, (long)(g.rc.right - g.rc.left),
         (long)(g.rc.bottom - g.rc.top), g.scale.count);
}

static void GroupScaleEnd(Group& g) {
    if (!g.scale.active) return;
    g.scale.active = false;
    if (g.id == 1) {
        SavePosition();          // also writes every companion's position
        SaveSize();
    }
    GroupRecompute(g);
    DLog(L"group %d: scale done scale=%d.%03d,%d.%03d", g.id, g.scale.lastSx1000 / 1000,
         g.scale.lastSx1000 % 1000, g.scale.lastSy1000 / 1000, g.scale.lastSy1000 % 1000);
}

// ---------------------------------------------------------------- group drag (G1/G2)
static bool GroupDragging() { return AnyGroupDragging(); }

static void GroupDragBegin(Group& g, POINT screen) {
    GroupDragState& st = g.drag;
    st.active = true;
    st.moving = false;
    st.origin = screen;
    if (g.id == 1) {
        // The strip is the anchor: moving it makes everything follow in the same composition.
        st.grab.x = screen.x - g_cfg.x;
        st.grab.y = screen.y - g_cfg.y;
        st.count = 0;
    } else {
        st.count = GroupMembers(g, st.members0);
    }
}

// Move the strip (and everything attached to it) to (x,y) *right now*, inside the mouse message,
// without repainting anything.
//
// ⛔ Only correct when the pixels do not depend on where the window sits - i.e. a solid background
// (bgMode=solid) or no background at all. With the glass layer on, the baked backdrop is anchored
// to the desktop, so a move *must* repaint with the new offset, and geometry + pixels have to land
// in the same composition (that is what presentSync=2's DwmFlush is for, HANDOVER §4.1).
//
// Why it matters (user report 2026-11-20 22:33, "快速拖动整个组很卡顿，纯色也卡"):
// the drag used to be applied once per *frame tick* - capped at refreshHz (60 Hz here) - and every
// one of those frames blocked 4.3-4.4 ms in DwmFlush (measured, 144 Hz screen). At high speed the
// group therefore advanced in 60 Hz steps on a 144 Hz display (2 or 3 refresh intervals per step):
// that is the judder that was reported. Moving here makes the window follow the mouse at the
// mouse's own rate, and since nothing is repainted there is no geometry/pixel pair to sync - so no
// flush either.
static void MoveStripNow(int x, int y) {
    if (!g_hwnd) return;
    SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, 0, 0,
                 SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
    CompanionFollowTo(x, y);          // same message: the group never comes apart
    GroupRecompute(DefaultGroup());
}

// Which of the two move paths applies to this profile?
//   position-independent pixels (solid / no background) → MoveStripNow() per mouse message
//   glass                                              → the tick, so pixels and geometry pair up
static bool GlassBackdropIsPositional() {
    return g_cfg.material == 1;      // material = (bgMode == 0 && glassLayer), see LoadConfig
}

static void GroupDragTo(Group& g, POINT screen) {
    GroupDragState& st = g.drag;
    if (!st.active) return;
    if (!st.moving) {
        int dx = screen.x - st.origin.x;
        int dy = screen.y - st.origin.y;
        if (dx * dx + dy * dy < 16) return;       // same 4 px threshold as the strip
        st.moving = true;
        DLog(L"group %d: drag start", g.id);
    }
    int mx = screen.x - st.origin.x;
    int my = screen.y - st.origin.y;
    if (g.id == 1) {
        g_cfg.x = screen.x - st.grab.x;
        g_cfg.y = screen.y - st.grab.y;
        // Same split as the strip's own drag: no position-dependent pixels -> move right now,
        // otherwise let the frame tick move + present in one composition.
        if (GlassBackdropIsPositional()) g_dragMovePending = true;
        else MoveStripNow(g_cfg.x, g_cfg.y);
        return;
    }
    // A group without the strip has no anchor to drive: place every member absolutely from the
    // rects captured at press time (no drift), then re-derive the frame.
    for (int i = 0; i < st.count; i++) {
        const GroupMember& m0 = st.members0[i];
        if (!m0.comp) continue;
        CompanionSetRect(*m0.comp, m0.rc.left + mx, m0.rc.top + my,
                         m0.rc.right - m0.rc.left, m0.rc.bottom - m0.rc.top, false);
    }
    GroupRecompute(g);
}

static void GroupDragEnd(Group& g) {
    GroupDragState& st = g.drag;
    if (!st.active) return;
    bool moved = st.moving;
    st.active = false;
    st.moving = false;
    if (!moved) return;
    if (g.id == 1) {
        SavePosition();          // also writes every companion's position
    } else {
        for (int i = 0; i < st.count; i++)
            if (st.members0[i].comp) CompanionSave(*st.members0[i].comp);
    }
    if (g_trayBar.hwnd && g_trayBar.enabled)
        AnchorPublish(kAnchorQuickSettings, &g_trayBar.rc, 8);
    GroupRecompute(g);
    DLog(L"group %d: drag done", g.id);
}

// ---------------------------------------------------------------- 贴边隐藏 (task 4)
//
// A group with [group] hideEdge=1 glues itself to the screen perimeter and slides out of the
// screen when the pointer leaves it; a thin band along that screen edge (the 唤出区域) brings it
// back. Everything here is geometry applied to the members, so a group with a *single* member
// needs no special case: GroupBounds() already covers that case (GroupBoxMembers() deliberately
// does not, so a one-member group simply has no frame to slide off).
//
// User's numbers (2026-11-22): 15 px gap to the screen edge; slide out until the whole group is
// invisible plus 5 px; the edge is decided once (nearest of the four) and afterwards the group
// only travels along the perimeter (it turns the corner at a screen corner); wake/hide are
// animated but quick; the "pointer left" test gets an extra 20 px because the pointer drifts out
// of the group while scaling; the band is x px thick (0 = not painted, but still 1 px hittable)
// and flashes twice for 2 s total.
#define kHideGap 15          // how far inside the screen edge the group rests while awake
#define kHideExtra 5         // slide out until the group is this far outside the screen
#define kHideLeavePad 20     // extra margin on the "the pointer left" test
#define kHideAnimMs 160      // one slide, either direction ("动画要迅速")
#define kHideFlashMs 2000    // two flashes of one second
#define kHideFlashOnMs 550   // lit part of each 1 s cycle

// The group whose settings page is open (0 = none): its wake band is painted faintly while the
// page is up, so adjusting its width/colour can be seen at all (user, 2026-11-23: "实时设置看不见").
// Set by SettingsPaint().
static int g_previewGroupId = 0;

static RECT HideMonitorRect(HWND h) {
    MONITORINFO mi{sizeof(mi)};
    HMONITOR mon = MonitorFromWindow(h ? h : g_hwnd, MONITOR_DEFAULTTONEAREST);
    if (mon && GetMonitorInfoW(mon, &mi)) return mi.rcMonitor;
    return RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
}

// 0 top, 1 right, 2 bottom, 3 left - whichever screen edge the bounds are closest to.
static int HideNearestSide(const RECT& b, const RECT& mon) {
    int d[4] = {b.top - mon.top, mon.right - b.right, mon.bottom - b.bottom, b.left - mon.left};
    int best = 0;
    for (int i = 1; i < 4; i++)
        if (d[i] < d[best]) best = i;
    return best;
}

// The same rect `s` px further outwards along the group's edge (negative = back inside).
static RECT HideShiftRect(const RECT& r, int side, int s) {
    RECT o = r;
    switch (side) {
        case 0: OffsetRect(&o, 0, -s); break;
        case 1: OffsetRect(&o, s, 0); break;
        case 2: OffsetRect(&o, 0, s); break;
        default: OffsetRect(&o, -s, 0); break;
    }
    return o;
}

// Move every member of the group (and therefore the frame) by (dx,dy).
static void GroupMoveBy(Group& g, int dx, int dy) {
    if (!dx && !dy) return;
    if (g.id == 1 && g_hwnd) {
        // the strip is the anchor: MoveStripNow carries the followers and re-derives the frame
        g_cfg.x += dx;
        g_cfg.y += dy;
        MoveStripNow(g_cfg.x, g_cfg.y);
        return;
    }
    GroupMember m[kGroupMaxMembers];
    int n = GroupMembers(g, m);
    for (int i = 0; i < n; i++) {
        if (!m[i].comp) continue;
        CompanionSetRect(*m[i].comp, m[i].rc.left + dx, m[i].rc.top + dy,
                         m[i].rc.right - m[i].rc.left, m[i].rc.bottom - m[i].rc.top, false);
    }
    GroupRecompute(g);
}

// Put the group exactly kHideGap inside `side`, and keep it inside the screen along the other
// axis (this is also what turns the corner: dragging past one pushes the nearest edge to the
// next one, and the glue then places it along that edge).
static void HidePlaceAtGap(Group& g, int side) {
    RECT b{};
    if (!GroupBounds(g, &b)) return;
    RECT mon = HideMonitorRect(g.hwnd ? g.hwnd : g_hwnd);
    int w = b.right - b.left, h = b.bottom - b.top;
    int dx = 0, dy = 0;
    switch (side) {
        case 0: dy = (mon.top + kHideGap) - b.top; break;
        case 1: dx = (mon.right - kHideGap) - b.right; break;
        case 2: dy = (mon.bottom - kHideGap) - b.bottom; break;
        default: dx = (mon.left + kHideGap) - b.left; break;
    }
    int nl = b.left + dx, nt = b.top + dy;
    if (nl + w > mon.right - kHideGap) dx += (mon.right - kHideGap) - (nl + w);
    if (nl < mon.left + kHideGap) dx += (mon.left + kHideGap) - nl;
    if (nt + h > mon.bottom - kHideGap) dy += (mon.bottom - kHideGap) - (nt + h);
    if (nt < mon.top + kHideGap) dy += (mon.top + kHideGap) - nt;
    if (dx || dy)
        DLog(L"hide: group %d glue side=%d bounds=%ld,%ld %ldx%ld move=%d,%d", g.id, side,
             (long)b.left, (long)b.top, (long)w, (long)h, dx, dy);
    GroupMoveBy(g, dx, dy);
}

static void HideEdgeAttach(Group& g) {
    RECT b{};
    if (!GroupBounds(g, &b)) {
        g.hideSide = -1;
        return;
    }
    RECT mon = HideMonitorRect(g.hwnd ? g.hwnd : g_hwnd);
    g.hideSide = HideNearestSide(b, mon);
    // Turning the switch on from the settings panel puts the pointer on the *panel*, not on the
    // group - without this grace the group would slide out from under the user the very next
    // tick (measured 2026-11-22 02:13: attach -> hide 95 ms later). Same for a restart with the
    // feature already on: the pointer is wherever it was, which is not "the user left the group".
    if (!g.hideArmAt) g.hideArmAt = GetTickCount() + 1500;
    HidePlaceAtGap(g, g.hideSide);
    DLog(L"hide: group %d attached to side %d (bounds %ld,%ld %ldx%ld)", g.id, g.hideSide,
         (long)b.left, (long)b.top, (long)(b.right - b.left), (long)(b.bottom - b.top));
}

// The band the user clicks / moves into, built from the *awake* bounds.
static bool HideWakeRectFor(const Group& g, const RECT& awake, const RECT& mon, RECT* out) {
    int t = g.wakeExt > 0 ? g.wakeExt : 1;      // x=0: not painted, but 1 px stays hittable
    switch (g.hideSide) {
        case 0: *out = RECT{awake.left, mon.top, awake.right, mon.top + t}; break;
        case 1: *out = RECT{mon.right - t, awake.top, mon.right, awake.bottom}; break;
        case 2: *out = RECT{awake.left, mon.bottom - t, awake.right, mon.bottom}; break;
        case 3: *out = RECT{mon.left, awake.top, mon.left + t, awake.bottom}; break;
        default: return false;
    }
    return out->right > out->left && out->bottom > out->top;
}

static LRESULT CALLBACK HideWakeProc(HWND h, UINT m, WPARAM w, LPARAM l);

static void HideWakeEnsure(Group& g) {
    if (g.wakeHwnd) return;
    static bool registered = false;
    if (!registered) {
        registered = true;
        WNDCLASSEXW wc{sizeof(wc)};
        wc.lpfnWndProc = HideWakeProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = L"DockWakeWindow";
        RegisterClassExW(&wc);
    }
    DWORD ex = WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED;
    if (g.wakeModeHover) ex |= WS_EX_TRANSPARENT;   // "进入" must not eat clicks
    g.wakeHwnd = CreateWindowExW(ex, L"DockWakeWindow", L"dock wake", WS_POPUP, 0, 0, 1, 1,
                                 nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (g.wakeHwnd) {
        SetWindowLongPtrW(g.wakeHwnd, GWLP_USERDATA, (LONG_PTR)g.id);
        DLog(L"hide: group %d wake window %p", g.id, (void*)g.wakeHwnd);
    }
}

static void HideWakeSetMode(Group& g) {
    if (!g.wakeHwnd) return;
    LONG ex = GetWindowLongW(g.wakeHwnd, GWL_EXSTYLE);
    if (g.wakeModeHover) ex |= WS_EX_TRANSPARENT;
    else ex &= ~WS_EX_TRANSPARENT;
    SetWindowLongW(g.wakeHwnd, GWL_EXSTYLE, ex);
}

// Paint (or hide) the band. `alpha` 0 = hidden; alpha 1 = invisible to the eye but still
// hit-testable, which is what a layered window needs to keep receiving the click.
static void HideWakePresent(Group& g, int alpha) {
    if (!g.wakeHwnd) return;
    int w = g.wakeRc.right - g.wakeRc.left, h = g.wakeRc.bottom - g.wakeRc.top;
    if (alpha <= 0 || w <= 0 || h <= 0) {
        if (IsWindowVisible(g.wakeHwnd)) ShowWindow(g.wakeHwnd, SW_HIDE);
        return;
    }
    static HDC dc = nullptr;
    static HBITMAP bmp = nullptr;
    static void* bits = nullptr;
    static int bw = 0, bh = 0;
    if (!dc || bw != w || bh != h) {
        if (dc) { DeleteDC(dc); dc = nullptr; }
        if (bmp) { DeleteObject(bmp); bmp = nullptr; }
        HDC screen = GetDC(nullptr);
        dc = CreateCompatibleDC(screen);
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        ReleaseDC(nullptr, screen);
        if (bmp) SelectObject(dc, bmp);
        bw = w;
        bh = h;
    }
    if (!bmp || !bits) return;
    // the band's colour: the group's own 色调 when it has one, else the strip's tone
    DWORD hue = (g.hasHue ? g.hue : g_hue[0]) & 0x00FFFFFFu;
    // hue is 0x00RRGGBB (the convention every other 色调 site uses); the DIB word is 0xAARRGGBB,
    // so red goes in bits 16..23. Getting this backwards swaps red and blue - invisible for a
    // green tone, obvious for anything else (found 2026-11-22 by the two-hue band test).
    DWORD rr = ((hue >> 16) & 0xFF) * (DWORD)alpha / 255;
    DWORD gg = ((hue >> 8) & 0xFF) * (DWORD)alpha / 255;
    DWORD bb = (hue & 0xFF) * (DWORD)alpha / 255;
    DWORD px = ((DWORD)alpha << 24) | (rr << 16) | (gg << 8) | bb;
    DWORD* p = (DWORD*)bits;
    for (int i = 0; i < w * h; i++) p[i] = px;
    POINT src{0, 0};
    SIZE sz{w, h};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    POINT dst{g.wakeRc.left, g.wakeRc.top};
    SetWindowPos(g.wakeHwnd, HWND_TOPMOST, dst.x, dst.y, w, h, SWP_NOACTIVATE);
    UpdateLayeredWindow(g.wakeHwnd, nullptr, &dst, &sz, dc, &src, 0, &bf, ULW_ALPHA);
    if (!IsWindowVisible(g.wakeHwnd)) ShowWindow(g.wakeHwnd, SW_SHOWNOACTIVATE);
}

static LRESULT CALLBACK HideWakeProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_LBUTTONUP) {
        Group* g = GroupById((int)(INT_PTR)GetWindowLongPtrW(h, GWLP_USERDATA));
        if (g) g->hideWakeClick = true;      // the tick decides what to do with it
        return 0;
    }
    return DefWindowProcW(h, m, w, l);
}

static void HideBegin(Group& g, bool waking, DWORD now) {
    g.hideSlideTarget = waking ? 1.0f : 0.0f;
    DLog(L"hide: group %d %s (side=%d slide=%.2f)", g.id, waking ? L"wake" : L"hide", g.hideSide,
         g.hideSlide);
    if (!waking && !g.wakeVisible) {
        g.hideFlashStart = now;
        g.hideFlashUntil = now + kHideFlashMs;
    }
}

// Turn the feature on / off for one group. Called from the settings page and from the load path.
// Idempotent: a repeated "on" for a group that is already attached does nothing.
static void HideEdgeSet(Group& g, bool on) {
    if (on) {
        if (g.hideEdge && g.hideSide >= 0) return;
        g.hideEdge = true;
        g.hideSide = -1;
        g.hideSlide = 1.0f;
        g.hideSlideTarget = 1.0f;
        g.hideShift = 0;
        // Turning the switch on from the settings panel puts the pointer on the *panel*, not on
        // the group - without this grace the group would slide out from under the user the very
        // next tick (measured 2026-11-22 02:13: attach -> hide 95 ms later).
        g.hideArmAt = GetTickCount() + 1500;
        HideEdgeAttach(g);
        HideWakeEnsure(g);
        HideWakeSetMode(g);
    } else {
        if (!g.hideEdge && g.hideSide < 0 && !g.wakeHwnd) return;
        g.hideEdge = false;
        if (g.hideShift) {
            int d = g.hideShift;
            switch (g.hideSide) {
                case 0: GroupMoveBy(g, 0, d); break;
                case 1: GroupMoveBy(g, -d, 0); break;
                case 2: GroupMoveBy(g, 0, -d); break;
                default: GroupMoveBy(g, d, 0); break;
            }
            g.hideShift = 0;
        }
        g.hideSlide = 1.0f;
        g.hideSlideTarget = 1.0f;
        g.hideSide = -1;
        if (g.wakeHwnd) ShowWindow(g.wakeHwnd, SW_HIDE);
        DLog(L"hide: group %d disabled", g.id);
    }
}

// task 4: a reload applies the group switches as well (hand edit + dev/t_dock_reload.ps1), and
// re-glues whatever was switched on.
static void ReloadGroupsFromIni() {
    for (int i = 0; i < g_groupCount; i++) {
        Group& g = g_groups[i];
        GroupLoad(g);
        HideEdgeSet(g, g.hideEdge);
        GroupRecompute(g);
        if (g.hwnd) GroupRepaint(g);
    }
}

// Runs on the 16 ms housekeeping tick for every group.
static void HideEdgeTick(Group& g, DWORD now) {    if (!g.hideEdge) return;
    RECT b{};
    if (!GroupBounds(g, &b)) return;
    if (g.hideSide < 0) HideEdgeAttach(g);

    RECT mon = HideMonitorRect(g.hwnd ? g.hwnd : g_hwnd);
    RECT awake = HideShiftRect(b, g.hideSide, -g.hideShift);
    RECT wakeRc{};
    bool hasWake = HideWakeRectFor(g, awake, mon, &wakeRc);
    g.wakeRc = wakeRc;

    // ---- pointer: inside the group (with the 20 px wobble pad) or inside the band? ----
    POINT p{};
    GetCursorPos(&p);
    RECT pad = awake;
    InflateRect(&pad, kHideLeavePad, kHideLeavePad);
    bool inGroup = PtInRect(&pad, p) != FALSE;
    bool inWake = hasWake && PtInRect(&wakeRc, p) != FALSE;

    // "Anything that means the user is interacting with us must not fold the group up" (user,
    // 2026-11-22): our own context menus (TrackPopupMenu runs a nested loop and the render tick
    // keeps firing, so the pointer going to a menu item used to count as "left the group"), the
    // settings panel that opens right after, the tray grid, a forwarded app menu, the thumbnail
    // preview. While any of them is up the arming time is pushed forward, which also leaves a
    // grace period after it closes.
    bool interacting = g_popupOpen || g_menuOpen || g_setWnd != nullptr || g_gridVisible ||
                       (g_thumbWnd && IsWindowVisible(g_thumbWnd));
    if (interacting) g.hideArmAt = now + 600;

    if (g.hideSlide == g.hideSlideTarget) {
        if (g.hideSlideTarget >= 1.0f) {
            // "the pointer left" - not before the arming grace has passed (see HideEdgeAttach),
            // and never while the user is working with our own UI
            if (!inGroup && !inWake && !interacting && (LONG)(now - g.hideArmAt) > 0)
                HideBegin(g, false, now);
        } else {
            bool wake = g.wakeModeHover ? inWake : g.hideWakeClick;
            if (wake) {
                g.hideWakeClick = false;
                HideBegin(g, true, now);
            }
        }
    }

    // ---- glue to the perimeter whenever it is awake and at rest ----
    if (g.hideSlide >= 1.0f && !g.drag.active && !g.scale.active && !g_dragging &&
        !g_dragMovePending) {
        HidePlaceAtGap(g, HideNearestSide(awake, mon));
    }

    // ---- animate, and move the group by whatever the animation gained ----
    static DWORD lastHideTick = 0;
    float dt = lastHideTick ? (float)(now - lastHideTick) : 16.0f;
    lastHideTick = now;
    if (dt > 64.0f) dt = 64.0f;
    if (g.hideSlide != g.hideSlideTarget) {
        float stepf = dt / (float)kHideAnimMs;
        if (g.hideSlide < g.hideSlideTarget) {
            g.hideSlide += stepf;
            if (g.hideSlide > g.hideSlideTarget) g.hideSlide = g.hideSlideTarget;
        } else {
            g.hideSlide -= stepf;
            if (g.hideSlide < g.hideSlideTarget) g.hideSlide = g.hideSlideTarget;
        }
    }
    // How far it has to travel to be *completely* outside: the distance from the far side of the
    // *awake* bounds to the screen edge it hugs, plus the redundancy the user asked for. (Using
    // the bounds' own extent instead left it 15 px on screen, and using the shifted rect would
    // feed back into itself - both measured 2026-11-22 02:13.)
    int outDist = 0;
    switch (g.hideSide) {
        case 0: outDist = awake.bottom - mon.top; break;
        case 1: outDist = mon.right - awake.left; break;
        case 2: outDist = mon.bottom - awake.top; break;
        default: outDist = awake.right - mon.left; break;
    }
    outDist += kHideExtra;
    int wantShift = (int)((1.0f - g.hideSlide) * (float)outDist + 0.5f);
    if (wantShift != g.hideShift) {
        int d = wantShift - g.hideShift;
        g.hideShift = wantShift;
        switch (g.hideSide) {
            case 0: GroupMoveBy(g, 0, -d); break;
            case 1: GroupMoveBy(g, d, 0); break;
            case 2: GroupMoveBy(g, 0, d); break;
            default: GroupMoveBy(g, -d, 0); break;
        }
    }

    // ---- the band ----
    // Two things can light it up: a flash (a fixed 2 s, two 1 s cycles - armed by an auto-hide in
    // 不可见 mode, and by every 唤出区域宽度 / 色调 edit in *both* modes so the change can be seen),
    // and 常显 while the group is hidden. While its settings page is open the band is also painted
    // faintly, even in 不可见 mode, because otherwise "调完 x / 调颜色" has no visible effect at all
    // (user, 2026-11-23).
    bool flashOn = g.hideFlashUntil && now < g.hideFlashUntil &&
                   ((now - g.hideFlashStart) % 1000u) < kHideFlashOnMs;
    bool previewing = (g_setWnd != nullptr && g_previewGroupId == g.id);
    int alpha = 0;
    if (g.hideSlide <= 0.02f) {                 // hidden: the band lives
        if (g.wakeVisible) alpha = flashOn ? 96 : 40;
        else alpha = flashOn ? 96 : 1;
    } else if (flashOn) {                       // awake, just adjusted: show what changed
        alpha = 96;
    } else if (previewing) {
        alpha = 40;
    }
    HideWakeEnsure(g);
    HideWakePresent(g, alpha);
}

// ---------------------------------------------------------------- group menu (G1/G2)
#define kGCmdLine 11
#define kGCmdBlockResize 12
#define kGCmdBlockMove 13
#define kGCmdDissolve 14
#define kGCmdSettings 15

// Shared by the group's own menu and by a single-member group's menu appended to its member.
static void AppendGroupMenuItems(HMENU menu, Group& g, bool withSettings) {
    AppendMenuW(menu, MF_STRING | (g.enabled ? MF_CHECKED : 0), kGCmdLine, L"显示边框线");
    AppendMenuW(menu, MF_STRING | (g.blockResize ? MF_CHECKED : 0), kGCmdBlockResize,
                L"屏蔽缩放");
    AppendMenuW(menu, MF_STRING | (g.blockMove ? MF_CHECKED : 0), kGCmdBlockMove, L"屏蔽位移");
    if (g.id > 1) AppendMenuW(menu, MF_STRING, kGCmdDissolve, L"解散本组（成员回到默认组）");
    if (withSettings) {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kGCmdSettings, L"Dock 设置…");
    }
}

// Moves every member of `g` back to the default group (only used for groups without the strip).
static void GroupDissolve(Group& g) {
    if (g.id <= 1) return;
    // Only the tray bar exists today; a second companion plugs in here (loop over companions).
    if (g_trayBar.hwnd && g_trayBar.groupId == g.id) {
        g_trayBar.groupId = 1;
        g_trayBar.follow = true;
        CompanionSave(g_trayBar);
    }
    GroupRecompute(g);           // now empty -> the frame goes away
    GroupRecompute(DefaultGroup());
    DLog(L"group %d: dissolved", g.id);
}

static bool HandleGroupCommand(Group& g, int cmd) {
    if (cmd == kGCmdLine) {
        g.enabled = !g.enabled;
        GroupSaveFlag(g, L"enabled", g.enabled);
        GroupRepaint(g);
        DLog(L"group %d: menu -> line=%d", g.id, (int)g.enabled);
        return true;
    }
    if (cmd == kGCmdBlockResize) {
        g.blockResize = !g.blockResize;
        GroupSaveFlag(g, L"blockResize", g.blockResize);
        DLog(L"group %d: menu -> blockResize=%d", g.id, (int)g.blockResize);
        return true;
    }
    if (cmd == kGCmdBlockMove) {
        g.blockMove = !g.blockMove;
        GroupSaveFlag(g, L"blockMove", g.blockMove);
        DLog(L"group %d: menu -> blockMove=%d", g.id, (int)g.blockMove);
        return true;
    }
    if (cmd == kGCmdDissolve) {
        GroupDissolve(g);
        return true;
    }
    if (cmd == kGCmdSettings) {
        ShowSettings(kObjGroup, g.id);
        return true;
    }
    return false;
}

static void GroupShowMenu(Group& g) {
    HMENU menu = CreatePopupMenu();
    AppendGroupMenuItems(menu, g, true);
    POINT sp{};
    GetCursorPos(&sp);
    g_popupOpen = true;
    int cmd = (int)TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, sp.x, sp.y, 0, g.hwnd,
                                  nullptr);
    g_popupOpen = false;
    DestroyMenu(menu);
    if (cmd > 0) HandleGroupCommand(g, cmd);
}

static LRESULT CALLBACK GroupBoxProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    Group* gp = GroupOfWindow(h);
    if (!gp) return DefWindowProcW(h, msg, wp, lp);
    Group& g = *gp;
    switch (msg) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_NCHITTEST:
            // The alpha test already gates this window (ring alpha 4, board alpha 1). While one
            // of *our* surfaces is up the board must step aside, or it competes with the very UI
            // it sits under.
            if (g_popupOpen || g_menuOpen || g_setWnd || g_gridVisible) return HTTRANSPARENT;
            return HTCLIENT;
        case WM_SETCURSOR: {
            POINT p{};
            GetCursorPos(&p);
            ScreenToClient(h, &p);
            RECT client;
            GetClientRect(h, &client);
            int e = GroupEdgeAt(g, p, client);
            if (e) {
                LPCWSTR cur = IDC_ARROW;
                if ((e & 1) && (e & 4)) cur = IDC_SIZENWSE;
                else if ((e & 2) && (e & 4)) cur = IDC_SIZENESW;
                else if ((e & 8) && (e & 1)) cur = IDC_SIZENESW;
                else if ((e & 8) && (e & 2)) cur = IDC_SIZENWSE;
                else if ((e & 1) || (e & 2)) cur = IDC_SIZEWE;
                else cur = IDC_SIZENS;
                SetCursor(LoadCursorW(nullptr, cur));
                return TRUE;
            }
            break;
        }
        case WM_LBUTTONDOWN: {
            POINT p{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            RECT client;
            GetClientRect(h, &client);
            POINT screen{};
            GetCursorPos(&screen);
            int edges = GroupEdgeAt(g, p, client);
            if (edges) GroupScaleBegin(g, screen, edges);
            else GroupDragBegin(g, screen);
            SetCapture(h);
            return 0;
        }
        case WM_MOUSEMOVE:
            if (g.scale.active || g.drag.active) {
                POINT p{};
                GetCursorPos(&p);
                if (g.scale.active) GroupScaleTo(g, p);
                else GroupDragTo(g, p);
                return 0;
            }
            return 0;
        case WM_LBUTTONUP:
            if (g.scale.active) {
                ReleaseCapture();
                GroupScaleEnd(g);
            } else if (g.drag.active) {
                ReleaseCapture();
                GroupDragEnd(g);
            }
            return 0;
        case WM_RBUTTONUP:
            GroupShowMenu(g);
            return 0;
        case WM_CAPTURECHANGED:
            if (g.scale.active) GroupScaleEnd(g);
            if (g.drag.active) GroupDragEnd(g);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_DESTROY:
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// Creates every group window up front (hidden): the ids are stable, so a group that is created
// from a menu later behaves exactly like one that existed at startup.
static void GroupCreateAll() {
    static bool registered = false;    if (!registered) {
        registered = true;
        WNDCLASSEXW wc{sizeof(wc)};
        wc.lpfnWndProc = GroupBoxProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = L"DockGroupBoxWindow";
        RegisterClassExW(&wc);
    }
    for (int i = 0; i < kMaxGroups; i++) {
        Group& g = g_groups[i];
        g.id = i + 1;
        GroupLoad(g);
        g.hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                                     WS_EX_LAYERED,
                                 L"DockGroupBoxWindow", L"dock group", WS_POPUP, 0, 0, 10, 10,
                                 nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
        if (g.hwnd) SetWindowLongPtrW(g.hwnd, GWLP_USERDATA, (LONG_PTR)g.id);
        if (!g.hwnd) {
            DLog(L"group %d: CreateWindowEx failed err=%lu", g.id,
                 (unsigned long)GetLastError());
            continue;
        }
        g.alpha = 0;
        g.alphaTarget = 0;
        ShowWindow(g.hwnd, SW_HIDE);
    }
    // How many ids are actually in use: the default group plus whatever the companions reference.
    g_groupCount = 1;
    int maxId = g_trayBar.hwnd ? g_trayBar.groupId : 1;
    if (maxId > g_groupCount) g_groupCount = maxId;
    if (g_groupCount > kMaxGroups) g_groupCount = kMaxGroups;
    for (int i = 0; i < g_groupCount; i++) {
        Group& g = g_groups[i];
        RECT want{};
        if (GroupBoxRect(g, &want)) {
            g.rc = want;
            GroupRepaint(g);
        }
        DLog(L"group %d: frame %ld,%ld %ldx%ld (margin %d, line=%d, blockResize=%d, "
             L"blockMove=%d)",
             g.id, (long)g.rc.left, (long)g.rc.top, (long)(g.rc.right - g.rc.left),
             (long)(g.rc.bottom - g.rc.top), g.margin, (int)g.enabled, (int)g.blockResize,
             (int)g.blockMove);
    }
    DLog(L"groups: %d in use (max %d)", g_groupCount, kMaxGroups);
    // task 4: a group that was left hidden in the ini glues itself to the perimeter right away
    for (int i = 0; i < g_groupCount; i++) {
        Group& g = g_groups[i];
        if (!g.hideEdge) continue;
        HideEdgeAttach(g);
        HideWakeEnsure(g);
        HideWakeSetMode(g);
    }
}

// Moves a companion into group `id` (0 = independent), updates the ini and both frames.
static void CompanionMoveToGroup(Companion& c, int id) {
    if (id < 0) id = 0;
    if (id > kMaxGroups) id = kMaxGroups;
    int oldId = c.groupId;
    if (oldId == id) return;
    c.groupId = id;
    c.follow = (id == 1);
    CompanionSave(c);            // persists group= and follow=
    if (id > g_groupCount) g_groupCount = id;
    for (int i = 0; i < g_groupCount; i++) GroupRecompute(g_groups[i]);
    DLog(L"tray bar: group %d -> %d", oldId, id);
}

// First id > 1 that has no member yet, else 0 (menu refuses).
static int NewGroupId() {
    for (int id = 2; id <= kMaxGroups; id++) {
        bool taken = (g_trayBar.hwnd && g_trayBar.enabled && g_trayBar.groupId == id);
        if (!taken) return id;
    }
    return 0;
}

// ---------------------------------------------------------------- companion menu (R4/G2)
// Right-click on the tray bar: its own settings + which group it belongs to (G2). Everything
// here takes effect immediately and is written to the ini, so a restart keeps it.
// `显示组框` used to live here; since G1 it is the *group's* property (`显示边框线`).
#define kCmdFollow 1
#define kCmdSize 2
#define kCmdSettings 4
#define kCmdGroupBase 20          // 20 + id = "join group id" (1..kMaxGroups)
#define kCmdGroupNew 30           // "move to a brand new group"
static void CompanionShowMenu(Companion& c) {
    HMENU menu = CreatePopupMenu();
    Group* g = GroupById(c.groupId);
    bool hasFrame = false;
    if (g) {
        RECT fr{};
        hasFrame = GroupBoxRect(*g, &fr);
    }

    // `组 ▸` — the assignment itself (the old "跟随条" tick became one entry of it).
    HMENU sub = CreatePopupMenu();
    AppendMenuW(sub, MF_STRING | (c.groupId == 1 ? MF_CHECKED : 0), kCmdGroupBase + 1,
                L"默认组（跟随条）");
    for (int id = 2; id <= kMaxGroups; id++) {
        wchar_t label[32];
        swprintf_s(label, L"组 %d", id);
        AppendMenuW(sub, MF_STRING | (c.groupId == id ? MF_CHECKED : 0), kCmdGroupBase + id,
                    label);
    }
    AppendMenuW(sub, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(sub, MF_STRING, kCmdGroupNew, L"移到一个新组…");
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)sub, L"组");
    AppendMenuW(menu, MF_STRING, kCmdSize, L"重置为默认尺寸（3 格）");
    // A group with fewer than two members has no frame, so its settings are reachable from here
    // (user, 2026-11-16: "单成员组的组设置先叠加到成员的菜单里").
    if (g && !hasFrame) {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendGroupMenuItems(menu, *g, false);
    }
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kCmdSettings, L"Dock 设置…");
    POINT sp{};
    GetCursorPos(&sp);
    g_popupOpen = true;
    int cmd = (int)TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, sp.x, sp.y, 0, c.hwnd,
                                  nullptr);
    g_popupOpen = false;
    DestroyMenu(menu);
    if (cmd <= 0) return;
    if (cmd == kCmdSize) {
        int icon = g_cfg.iconSize < 40 ? 40 : g_cfg.iconSize;
        if (icon > g_cfg.maxIcon) icon = g_cfg.maxIcon;
        int pad = CompanionPad(c), gap = CompanionGap(c);
        int w = kTrayCellCount * (icon + gap) - gap + pad * 2;
        int h = icon + pad * 2;
        CompanionSetRect(c, c.rc.left, c.rc.top, w, h, true);
        CompanionSave(c);
        if (Group* gg = GroupById(c.groupId)) GroupRecompute(*gg);
        DLog(L"tray bar: menu -> default size %dx%d", w, h);
    } else if (cmd == kCmdSettings) {
        ShowSettings(kObjCompanion, 0);
    } else if (cmd == kCmdGroupNew) {
        int id = NewGroupId();
        if (id) {
            CompanionMoveToGroup(c, id);
            DLog(L"tray bar: menu -> moved to a new group %d", id);
        } else {
            DLog(L"tray bar: menu -> no free group id (max %d)", kMaxGroups);
        }
    } else if (cmd >= kCmdGroupBase + 1 && cmd <= kCmdGroupBase + kMaxGroups) {
        CompanionMoveToGroup(c, cmd - kCmdGroupBase);
        DLog(L"tray bar: menu -> group %d", c.groupId);
    } else if (g && HandleGroupCommand(*g, cmd)) {
        // the appended group items of a single-member group
    }
}

// ---------------------------------------------------------------- visibility
// Rule (user, 2026-11-15, refined 2026-11-16): only the strip fades with distance. A
// following companion (and the group frame) stays hidden until the pointer is *on the strip* -
// that is the sign the user wants to interact with the dock - then fades in fast; it goes away
// only when the pointer leaves the *frame*, so travelling from the strip to a companion through
// empty space cannot make the companion disappear under the cursor. An independent companion
// (follow=0) fades with distance like the strip and takes no part in the frame.
// Alpha for one window of a group (H2b): every member of a group shares the group's alpha.
//   * the group's latch (`shown`) wins: the pointer is on a member, inside the frame or on our
//     own popup - then everything in the group is fully opaque;
//   * otherwise the distance to the *group's* rectangle (members union + margin) fades it, using
//     that group's own fadeStart/fadeEnd. Group 1 (the strip's group) therefore fades with the
//     group box instead of the strip alone, which is what "距离相对组测算" means.
// A companion that is in no group (`groupId == 0`) keeps the old behaviour: distance to itself,
// global distances - it has no group to be measured against.
static int CompanionAlphaTarget(Companion& c, POINT p) {
    if (!c.enabled) return 0;
    Group* g = GroupById(c.groupId);
    if (g && g->shown) return 255;
    int fs = g_cfg.fadeStart, fe = g_cfg.fadeEnd;
    RECT ref = c.rc;
    if (g) {
        fs = g->fadeStart >= 0 ? g->fadeStart : g_cfg.fadeStart;
        fe = g->fadeEnd > fs ? g->fadeEnd : (fs + 1);
        RECT box{};
        if (GroupBounds(*g, &box)) ref = box;
    }
    int dx = 0, dy = 0;
    if (p.x < ref.left) dx = ref.left - p.x;
    else if (p.x > ref.right) dx = p.x - ref.right;
    if (p.y < ref.top) dy = ref.top - p.y;
    else if (p.y > ref.bottom) dy = p.y - ref.bottom;
    int d = (dx == 0 && dy == 0) ? 0 : (int)sqrt((double)dx * dx + (double)dy * dy);
    if (d <= fs) return 255;
    if (d >= fe) return 0;
    return 255 - (d - fs) * 255 / (fe - fs);
}

// The group's shared fade value (H2b/task 4): distance to the group's own bounds with the group's
// numbers, 255 while it is latched (pointer on a member / in the frame / our UI in use) and 255
// while 贴边隐藏 is on - that feature replaces the distance fade entirely, and the two together
// felt wrong (user, 2026-11-22).
static int GroupFadeTarget(Group& g, POINT p) {
    if (g.hideMode == 1 || g.hideMode == 2) return 255;   // 贴边隐藏 takes over / 从不
    if (OurUiBusy()) return 255;                          // walking to a menu item is not leaving
    if (g.shown) return 255;
    int fs = g.fadeStart >= 0 ? g.fadeStart : g_cfg.fadeStart;
    int fe = g.fadeEnd > fs ? g.fadeEnd : (fs + 1);
    RECT ref{};
    if (!GroupBounds(g, &ref)) {
        if (!g_hwnd || !GetWindowRect(g_hwnd, &ref)) return 255;
    }
    int dx = 0, dy = 0;
    if (p.x < ref.left) dx = ref.left - p.x;
    else if (p.x > ref.right) dx = p.x - ref.right;
    if (p.y < ref.top) dy = ref.top - p.y;
    else if (p.y > ref.bottom) dy = p.y - ref.bottom;
    int d = (dx == 0 && dy == 0) ? 0 : (int)sqrt((double)dx * dx + (double)dy * dy);
    if (d <= fs) return 255;
    if (d >= fe) return 0;
    return 255 - (d - fs) * 255 / (fe - fs);
}

static int DefaultGroupFadeAlpha() { return DefaultGroup().fadeNow; }

// Visibility, per group (G2). Group 1 keeps the original rule; a group without the strip latches
// on when the pointer is on one of its members (or inside its frame) and releases when it leaves.
static void CompanionVisibilityTick(DWORD now) {
    const double tEnter = NowMs();
    POINT p{};
    GetCursorPos(&p);

    // ---- groups: latch + frame windows ----
    for (int i = 0; i < g_groupCount; i++) {
        Group& g = g_groups[i];
        GroupMember m[kGroupMaxMembers];
        int n = GroupMembers(g, m);
        bool onMember = false;
        for (int k = 0; k < n; k++)
            if (PtInRect(&m[k].rc, p)) { onMember = true; break; }
        RECT box{};
        bool haveBox = GroupBoxRect(g, &box);
        bool inBox = false;
        if (haveBox) {
            RECT b = box;
            InflateRect(&b, 6, 6);            // a little hysteresis on the frame line
            inBox = PtInRect(&b, p) != FALSE;
        }
        // "the pointer is outside the frame" must not count while the user is *using* the
        // frame: a fast scale/drag outruns the box rect by a message or two, and reading that
        // as "left the group" faded everything out in the middle of the gesture (bugs
        // 2026-11-16 00:44 and the G1 drag). Group drags/scales are whitelisted here.
        //
        // Our own popups count as "inside the group" too (user 2026-11-17, §7-A4) - but only
        // while the pointer is actually *on* one of them: with the settings panel / preview /
        // forwarded menu open the pointer is on our UI and the frame used to hide, which then
        // looked like "the frame does not come back after moving the companion out of the group
        // and back in" (reported 2026-11-20).
        bool ourUi = false;
        {
            HWND ours[3] = {g_setWnd, g_thumbWnd, g_menuHwnd};
            for (HWND h : ours) {
                if (!h || !IsWindow(h) || !IsWindowVisible(h)) continue;
                RECT pr{};
                if (GetWindowRect(h, &pr) && PtInRect(&pr, p)) { ourUi = true; break; }
            }
            if (!ourUi && g_menuOpen) ourUi = true;      // a forwarded menu swallows the pointer
        }
        if (onMember || inBox || ourUi) g.shown = true;
        else if (!inBox && !g.scale.active && !g.drag.active) g.shown = false;

        // one fade for the whole group: target here, the value every member shows
        g.fadeTarget = GroupFadeTarget(g, p);
        if (g.fadeNow != g.fadeTarget) {
            int step = (int)(255 * 16 / 120);        // ~120 ms for a full fade at 60 fps
            if (step < 1) step = 1;
            int diff = g.fadeTarget - g.fadeNow;
            g.fadeNow += (diff > 0) ? (step < diff ? step : diff) : ((-step) > diff ? -step : diff);
        }

        bool wantShown = g.shown && haveBox;      // a group of one has no frame at all
        if (g.hwnd && (wantShown ? 255 : 0) != g.alphaTarget) {
            DLog(L"group %d: target -> %d (shown=%d box=%d alpha=%d)", g.id,
                 wantShown ? 255 : 0, (int)g.shown, (int)haveBox, g.alpha);
        }
        if (wantShown && g.alphaTarget == 0 && g.hwnd) {
            // The frame is (re)appearing: its geometry may be stale after members moved while
            // it was hidden, and the z-order has to be re-asserted (strip > members > frame).
            GroupRecompute(g);
            ShowWindow(g.hwnd, SW_SHOWNOACTIVATE);
            GroupPresent(g);     // a window re-shown after SW_HIDE keeps the alpha of its last
                                 // present, so assert it once with the current value
            if (g.id == 1) {
                if (g_trayBar.hwnd)
                    SetWindowPos(g_trayBar.hwnd, ZBandInsert(), 0, 0, 0, 0,
                                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                if (g_hwnd)
                    SetWindowPos(g_hwnd, ZBandInsert(), 0, 0, 0, 0,
                                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }
        g.alphaTarget = wantShown ? 255 : 0;
        if (g.hwnd) {
            bool vis = (IsWindowVisible(g.hwnd) != FALSE);
            bool shouldVis = g.alphaTarget > 0 || g.alpha > 0;
            if (vis != shouldVis)
                ShowWindow(g.hwnd, shouldVis ? SW_SHOWNOACTIVATE : SW_HIDE);
        }
    }

    // ---- companions: alpha target + show/hide ----
    Companion& c = g_trayBar;
    // The companion shows its group's fade value (one fade for the whole group). A companion
    // with no group at all (groupId 0) keeps its own distance fade.
    Group* cg = GroupById(c.groupId);
    int target = cg ? cg->fadeTarget : CompanionAlphaTarget(c, p);
    bool wasVisible = c.visible;
    c.visible = (target > 0);
    if (c.visible && !wasVisible && c.hwnd) {
        // Volume/power are cheap (a COM getter and a struct), so they are refreshed for the
        // first frame on screen. The network state must NOT be re-queried here: that is an RPC
        // into the WLAN service, and doing it on this path blocked the UI thread (and with it
        // WH_MOUSE_LL) exactly when the pointer crossed into this window - the hitch the user
        // reported on 2026-11-17, worse with glass on because the same frame also bakes. The
        // worker thread is nudged instead; its answer lands a few ms later and is invisible.
        c.stateAt = 0;
        NetQueryNudge();
        // While hidden we only moved the stored rect, so put the window where it belongs now -
        // but only when it really is somewhere else: two SetWindowPos calls here cost ~4 ms in
        // the frame the window appears, which is one more thing the pointer can feel.
        RECT now{};
        bool moved = !GetWindowRect(c.hwnd, &now) || now.left != c.rc.left || now.top != c.rc.top ||
                     now.right - now.left != c.rc.right - c.rc.left ||
                     now.bottom - now.top != c.rc.bottom - c.rc.top;
        if (moved) {
            // While the dock is yielding to a capture overlay this must be a plain move: a
            // HWND_TOPMOST insert here would lift the companion back over the selection box
            // (task 1 - "the dock pops up when the pointer wanders into the menus next to it").
            SetWindowPos(c.hwnd, g_zMode == 1 ? nullptr : HWND_TOPMOST, c.rc.left, c.rc.top,
                         c.rc.right - c.rc.left, c.rc.bottom - c.rc.top,
                         SWP_NOACTIVATE | (g_zMode == 1 ? SWP_NOZORDER : 0u));
        }
        // and publish the anchor once (the flyout may be opened before the next move).
        AnchorPublish(kAnchorQuickSettings, &c.rc, 8);
        // z-order: group frame < companion < strip. The frame asserts itself just above, so
        // both of these are needed on every show (dropping them lets the frame paint over the
        // companion).
        SetWindowPos(c.hwnd, ZBandInsert(), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        if (g_hwnd)
            SetWindowPos(g_hwnd, ZBandInsert(), 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        // The visible pixels are (re)built here and not while hidden: see the note in
        // TrayStateRefresh. ~1 ms, once per appearance.
        TrayRepaint(c);
    }
    // Visible from the moment it should show until the fade has actually reached 0, so the
    // fade-out is a fade instead of an instant disappearance (stepped in CompanionTick).
    bool shouldBeVisible = (target > 0) || c.alpha > 0;
    if (c.hwnd && ((IsWindowVisible(c.hwnd) != FALSE) != shouldBeVisible)) {
        ShowWindow(c.hwnd, shouldBeVisible ? SW_SHOWNOACTIVATE : SW_HIDE);
        if (!shouldBeVisible) CompanionTooltipShow(c, -1);
    }
    c.alphaTarget = target;
    const double dVis = NowMs() - tEnter;
    if (dVis >= 3.0) DLog(L"slow: companion visibility tick %.1f ms", dVis);
}

// ---------------------------------------------------------------- per-frame tick
// The strip's origin as the companions last saw it. Shared by both callers of
// CompanionFollowTo() so one frame can never shift a companion twice.
static int g_companionLastStripX = INT_MIN;
static int g_companionLastStripY = INT_MIN;
static int g_companionFollowMoves = 0;      // diagnostics: see the 10 s cadence line

// The strip moved to (stripX, stripY): shift every following companion by the same delta.
// Two callers, same bookkeeping:
//   * Present() - the drag/dodge path, i.e. ~139 Hz, in the same composition as the strip;
//   * CompanionTick() - once per housekeeping tick, as the catch-all for moves that never go
//     through Present() (resize, snap, restore, settings).
// A hidden companion only needs its stored rect moved: nothing is on screen, and it syncs to
// that rect the moment it becomes visible again.
static void CompanionFollowTo(int stripX, int stripY) {
    if (g_companionLastStripX == INT_MIN) {
        g_companionLastStripX = stripX;
        g_companionLastStripY = stripY;
        return;
    }
    int dx = stripX - g_companionLastStripX;
    int dy = stripY - g_companionLastStripY;
    g_companionLastStripX = stripX;
    g_companionLastStripY = stripY;
    if (!dx && !dy) return;
    // A group scale moves *and* resizes every member itself (GroupScaleTo); translating here on
    // top of that would shift everything a second time.
    if (GroupScaling()) return;
    // NOTE: a *group drag* must NOT bail out here. Group 1's drag only drives the strip
    // (`g_cfg` + `g_dragMovePending`) and this function is what carries the companion and the
    // frame along - returning early left the strip moving alone (bug 2026-11-16 15:36).
    // A group without the strip moves its own members absolutely and never reaches here.
    // Only the default group follows the strip - the others are independent (G2).
    Group& dg = DefaultGroup();
    // The frame is pure derived geometry, so a group-wide move is just a translation - and it
    // has to happen on this path (not on the 16 ms housekeeping gate) for the same reason the
    // companions do: the frame must land in the strip's composition, not a frame later.
    GroupTranslate(dg, dx, dy);
    if (!g_trayBar.hwnd || !g_trayBar.enabled || g_trayBar.groupId != 1) return;
    if (g_trayBar.dragging || g_trayBar.resizing) return;    // the pointer owns it right now
    if (g_trayBar.alpha > 0) {
        CompanionSetRect(g_trayBar, g_trayBar.rc.left + dx, g_trayBar.rc.top + dy,
                         g_trayBar.rc.right - g_trayBar.rc.left,
                         g_trayBar.rc.bottom - g_trayBar.rc.top, false);
        g_companionFollowMoves++;
    } else {
        g_trayBar.rc.left += dx;
        g_trayBar.rc.right += dx;
        g_trayBar.rc.top += dy;
        g_trayBar.rc.bottom += dy;
    }
}

static void CompanionTick(DWORD now) {
    if (!g_trayBar.hwnd) return;

    // 1. follow the strip - per frame from Present() while it is dragged; this tick only
    //    catches geometry that changed without a present (resize, snap, restore)
    RECT sr{};
    GetWindowRect(g_hwnd, &sr);
    CompanionFollowTo(sr.left, sr.top);
    // A *size* change of the strip (its own edge drag, ShrinkToIcons after a resize, a settings
    // change) moves the frame's edges too, and translation cannot express that: re-derive it
    // whenever the strip's box changed. Cheap - GroupBoxPlace only repaints on a real change.
    {
        static RECT lastStrip{};
        if (sr.right - sr.left != lastStrip.right - lastStrip.left ||
            sr.bottom - sr.top != lastStrip.bottom - lastStrip.top) {
            lastStrip = sr;
            GroupRecompute(DefaultGroup());
        }
    }

    // 2. state + fade
    {
        const double tState = NowMs();
        TrayStateRefresh(now);
        CompanionVisibilityTick(now);
        const double dState = NowMs() - tState;
        if (dState >= 3.0) DLog(L"slow: state+visibility %.1f ms", dState);
    }

    // The companion's alpha *is* its group's fade value - no independent stepping, otherwise the
    // strip (which takes the value straight away) and the companion drift apart while fading,
    // which is exactly what the user saw (2026-11-22). A companion with no group keeps the old
    // eased behaviour.
    Group* cFade = GroupById(g_trayBar.groupId);
    int wantAlpha = cFade ? cFade->fadeNow : g_trayBar.alphaTarget;
    if (!cFade && g_trayBar.alpha != g_trayBar.alphaTarget) {
        int diff = g_trayBar.alphaTarget - g_trayBar.alpha;
        int step = (int)(255 * 16 / 120);        // ~120 ms for a full fade at 60 fps
        if (step < 1) step = 1;
        if (diff > 0) g_trayBar.alpha += step < diff ? step : diff;
        else g_trayBar.alpha += (-step) > diff ? -step : diff;
    }
    if (g_trayBar.alpha != wantAlpha) {
        DLog(L"fade: tray %d -> %d", g_trayBar.alpha, wantAlpha);   // TEMP: shared group fade
        g_trayBar.alpha = wantAlpha;
        const double tPresent = NowMs();
        CompanionPresent(g_trayBar);
        const double dPresent = NowMs() - tPresent;
        if (dPresent >= 4.0) DLog(L"slow: companion fade present %.1f ms", dPresent);
        // the window is hidden only once the fade has finished, see CompanionVisibilityTick
        if (g_trayBar.alpha == 0 && g_trayBar.hwnd && IsWindowVisible(g_trayBar.hwnd))
            ShowWindow(g_trayBar.hwnd, SW_HIDE);
    }

    // 2b. task 3: the snap (贴边方角). One animation step per frame, like the strip's
    // AnimateCorners; a hidden window snaps instantly and costs nothing.
    CompanionSnapTick(g_trayBar, now);

    // 3. every group's frame fades with its members, in the same steps
    for (int i = 0; i < g_groupCount; i++) {
        Group& g = g_groups[i];
        if (g.alpha == g.alphaTarget) continue;
        int diff = g.alphaTarget - g.alpha;
        int step = (int)(255 * 16 / 120);
        if (step < 1) step = 1;
        if (diff > 0) g.alpha += step < diff ? step : diff;
        else g.alpha += (-step) > diff ? -step : diff;
        GroupPresent(g);
        if (g.alpha == 0 && g.hwnd && IsWindowVisible(g.hwnd)) ShowWindow(g.hwnd, SW_HIDE);
    }
}

// ---------------------------------------------------------------- window proc
static LRESULT CALLBACK CompanionProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    Companion& c = g_trayBar;
    switch (msg) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;

        case WM_MOUSEMOVE: {
            int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
            POINT pt{x, y};

            // `屏蔽位移`: this member is not being dragged, the whole group is.
            if (Group* dg = GroupById(c.groupId); dg && dg->drag.active) {
                POINT p{};
                GetCursorPos(&p);
                GroupDragTo(*dg, p);
                return 0;
            }

            if (c.resizing) {
                POINT p{};
                GetCursorPos(&p);
                RECT r = c.resizeRect;
                int dx = p.x - c.resizeOrigin.x;
                int dy = p.y - c.resizeOrigin.y;
                if (c.resizeEdge & 1) r.left += dx;
                if (c.resizeEdge & 2) r.right += dx;
                if (c.resizeEdge & 4) r.top += dy;
                if (c.resizeEdge & 8) r.bottom += dy;
                int minSide = g_cfg.minIcon + CompanionPad(c) * 2;
                if (r.right - r.left < minSide) {
                    if (c.resizeEdge & 1) r.left = r.right - minSide;
                    else r.right = r.left + minSide;
                }
                if (r.bottom - r.top < minSide) {
                    if (c.resizeEdge & 4) r.top = r.bottom - minSide;
                    else r.bottom = r.top + minSide;
                }
                CompanionSetRect(c, r.left, r.top, r.right - r.left, r.bottom - r.top, true);
                if (Group* g = GroupById(c.groupId)) GroupRecompute(*g);   // frame follows
                return 0;
            }
            if (c.dragging) {
                POINT p{};
                GetCursorPos(&p);
                if (!(GetKeyState(VK_LBUTTON) & 0x8000)) {
                    c.dragging = false;
                    ReleaseCapture();
                    CompanionSave(c);
                    if (Group* g = GroupById(c.groupId)) GroupRecompute(*g);
                    return 0;
                }
                CompanionSetRect(c, p.x - c.dragStart.x, p.y - c.dragStart.y,
                                 c.rc.right - c.rc.left, c.rc.bottom - c.rc.top, false);
                if (Group* g = GroupById(c.groupId)) GroupRecompute(*g);   // live
                return 0;
            }
            if (c.pressActive) {
                POINT p{};
                GetCursorPos(&p);
                int ddx = p.x - c.pressScreen.x;
                int ddy = p.y - c.pressScreen.y;
                if (ddx * ddx + ddy * ddy >= 16) {
                    c.pressActive = false;
                    // `屏蔽位移`: grabbing a member drags the whole group, exactly like grabbing
                    // the board - the member keeps its place inside the group.
                    if (GroupBlocksMove(&c)) {
                        if (Group* g = GroupById(c.groupId)) {
                            GroupDragBegin(*g, p);
                            DLog(L"tray bar: drag redirected to group %d (blockMove)", g->id);
                            return 0;
                        }
                    }
                    c.dragging = true;
                    c.dragStart.x = p.x - c.rc.left;
                    c.dragStart.y = p.y - c.rc.top;
                    SetCapture(h);
                    return 0;
                }
            }

            RECT cells[kTrayCellCount];
            TrayCells(c, cells);
            int hover = -1;
            for (int i = 0; i < kTrayCellCount; i++)
                if (PtInRect(&cells[i], pt)) { hover = i; break; }
            if (hover != c.hoverCell) {
                const double tHover = NowMs();
                c.hoverCell = hover;
                TrayRepaint(c);
                const double tPaint = NowMs();
                CompanionPresent(c);
                const double tPres = NowMs();
                CompanionTooltipShow(c, hover);
                const double tTip = NowMs();
                if (tTip - tHover >= 3.0) {
                    DLog(L"slow: companion hover cell=%d paint %.1f, present %.1f, tooltip %.1f ms",
                         hover, tPaint - tHover, tPres - tPaint, tTip - tPres);
                }
            }
            TRACKMOUSEEVENT tme{sizeof(tme), TME_LEAVE, h, 0};
            TrackMouseEvent(&tme);
            return 0;
        }

        case WM_MOUSELEAVE:
            if (c.hoverCell != -1) {
                c.hoverCell = -1;
                TrayRepaint(c);
                CompanionPresent(c);
                CompanionTooltipShow(c, -1);
            }
            return 0;

        case WM_LBUTTONDOWN: {
            int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
            POINT pt{x, y};
            RECT client;
            GetClientRect(h, &client);
            int edge = GroupBlocksResize(&c) ? 0 : EdgeAt(pt, client);
            if (edge && g_cfg.allowResize) {
                c.resizeRect = c.rc;
                GetCursorPos(&c.resizeOrigin);
                c.resizeEdge = edge;
                c.resizing = true;
                SetCapture(h);
                DLog(L"tray bar: resize start edge=%d", edge);
                return 0;
            }
            c.pressActive = true;
            GetCursorPos(&c.pressScreen);
            SetCapture(h);
            return 0;
        }

        case WM_LBUTTONUP:
            if (Group* dg = GroupById(c.groupId); dg && dg->drag.active) {
                ReleaseCapture();
                GroupDragEnd(*dg);
                return 0;
            }
            if (c.resizing) {
                c.resizing = false;
                ReleaseCapture();
                AnchorPublish(kAnchorQuickSettings, &c.rc, 8);
                CompanionSave(c);
                return 0;
            }
            if (c.dragging) {
                c.dragging = false;
                ReleaseCapture();
                AnchorPublish(kAnchorQuickSettings, &c.rc, 8);
                CompanionSave(c);
                return 0;
            }
            if (c.pressActive) {
                c.pressActive = false;
                ReleaseCapture();
                // Anywhere in the tray bar opens the same panel (user, 2026-11-15)
                RECT r = c.rc;
                AnchorPublish(kAnchorQuickSettings, &r, 8);
                QuickSettingsBeginPlacement(r);       // remember the screen before it opens
                const BYTE chord[] = {VK_LWIN, 'A'};
                DLog(L"tray bar: click -> quick settings (win+a)");
                SendChord(chord, 2);
                return 0;
            }
            return 0;

        case WM_RBUTTONUP:
            // The tray bar's own settings menu (R4). Its whole surface carries the 4% wash, so
            // a right click always lands here - unlike the strip's transparent blank space.
            CompanionShowMenu(c);
            return 0;

        case WM_MOUSEWHEEL: {
            // Wheel over the volume cell: +/- 2 % per detent (user, 2026-11-16). The wheel
            // reaches a never-focused window because this machine scrolls the window under the
            // pointer (the same reason the strip can be paged without focus).
            // Careful: WM_MOUSEWHEEL's point is in *screen* coordinates, unlike the buttons.
            POINT p{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            ScreenToClient(h, &p);
            RECT cells[kTrayCellCount];
            TrayCells(c, cells);
            int delta = GET_WHEEL_DELTA_WPARAM(wp);
            {
                // First few wheels are logged: "the wheel never arrives" and "the point is
                // outside the volume cell" look identical from the outside.
                static int wheelLogged = 0;
                if (wheelLogged < 10) {
                    wheelLogged++;
                    DLog(L"tray bar: WM_MOUSEWHEEL delta=%d at client %ld,%ld volumeCell=%d",
                         delta, (long)p.x, (long)p.y, (int)(PtInRect(&cells[1], p) != FALSE));
                }
            }
            if (delta == 0 || !PtInRect(&cells[1], p)) break;   // volume cell only
            int notches = delta / WHEEL_DELTA;
            if (notches == 0) notches = delta > 0 ? 1 : -1;
            int step = notches * kTrayVolumeStep;
            // Scrolling up while muted is a request to hear something: leave mute first,
            // otherwise the wheel looks broken.
            if (step > 0 && g_trayState.muted) SetMuted(false);
            if (SetVolumePercent(g_trayState.volPercent + step)) {
                c.stateAt = GetTickCount();      // we are the freshest value now
                TrayRepaint(c);
                CompanionPresent(c);
                CompanionTooltipShow(c, 1);      // keep the tooltip honest while scrolling
                DLog(L"tray bar: wheel %+d%% -> %d%% (mute=%d)", step, g_trayState.volPercent,
                     (int)g_trayState.muted);
            }
            return 0;
        }

        case WM_SETCURSOR: {
            POINT p{};
            GetCursorPos(&p);
            ScreenToClient(h, &p);
            RECT client;
            GetClientRect(h, &client);
            int e = GroupBlocksResize(&c) ? 0 : EdgeAt(p, client);
            if (e) {
                LPCWSTR cur = IDC_ARROW;
                if ((e & 1) && (e & 4)) cur = IDC_SIZENWSE;
                else if ((e & 2) && (e & 4)) cur = IDC_SIZENESW;
                else if ((e & 8) && (e & 1)) cur = IDC_SIZENESW;
                else if ((e & 8) && (e & 2)) cur = IDC_SIZENWSE;
                else if ((e & 1) || (e & 2)) cur = IDC_SIZEWE;
                else cur = IDC_SIZENS;
                SetCursor(LoadCursorW(nullptr, cur));
                return TRUE;
            }
            break;
        }

        case WM_CAPTURECHANGED:
            // A lost capture must end a redirected group drag, or `GroupDragging()` would stay
            // true and the group would never fade out again.
            if (Group* dg = GroupById(c.groupId); dg && dg->drag.active) GroupDragEnd(*dg);
            return 0;

        case WM_DESTROY:
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

static void CompanionCreate() {
    Companion& c = g_trayBar;
    CompanionLoad(c);
    // task 3: start already snapped - the first paint must not show rounded corners on an edge
    // the window has been hugging since the last session.
    CompanionSnapUpdate(c);
    for (int i = 0; i < 4; i++) c.snapAnim[i] = c.snapTarget[i];
    if (!c.enabled) return;

    static bool registered = false;
    if (!registered) {
        registered = true;
        WNDCLASSEXW wc{sizeof(wc)};
        wc.lpfnWndProc = CompanionProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = L"DockTrayBarWindow";
        RegisterClassExW(&wc);
    }

    int w = c.rc.right - c.rc.left, h = c.rc.bottom - c.rc.top;
    c.hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                                 WS_EX_LAYERED,
                             L"DockTrayBarWindow", L"dock tray bar", WS_POPUP, c.rc.left,
                             c.rc.top, w, h, nullptr, nullptr, GetModuleHandleW(nullptr),
                             nullptr);
    if (!c.hwnd) {
        DLog(L"tray bar: CreateWindowEx failed err=%lu", (unsigned long)GetLastError());
        return;
    }
    c.alpha = 0;
    c.alphaTarget = 0;
    CompanionEnsureDib(c, w, h);
    c.stateAt = 0;
    NetQueryStart();                     // the WLAN query has to stay off the UI thread
    NetQueryNudge();
    TrayStateRefresh(GetTickCount());    // real state first, so the first paint is correct
    TrayRepaint(c);
    CompanionPresent(c);
    CompanionTooltipEnsure(c);
    ShowWindow(c.hwnd, SW_HIDE);
    RECT r = c.rc;
    AnchorPublish(kAnchorQuickSettings, &r, 8);
    DLog(L"tray bar: created %ld,%ld %dx%d follow=%d", (long)c.rc.left, (long)c.rc.top, w, h,
         (int)c.follow);
    // Which style actually applies (R4 overrides): one line, so "did my ini key take effect"
    // never needs a screenshot.
    DLog(L"tray bar: group=%d (enabled=%d follow=%d)", c.groupId, (int)c.enabled,
         (int)c.follow);
    DLog(L"tray bar: style pad=%d gap=%d radius=%d%% -> corner %d px (overrides pad=%d gap=%d "
         L"radius=%d)",
         CompanionPad(c), CompanionGap(c), CompanionRadiusPercent(c),
         RadiusForPercent(w, h, CompanionRadiusPercent(c)), c.padOv, c.gapOv, c.radiusOv);
    // R2: the frame around "the strip + this companion". It needs the companion to exist (a
    // frame around the strip alone is not drawn), so it is created from here, not from WinMain.
    GroupCreateAll();
}

// ---------------------------------------------------------------- quick settings placement
// The quick settings flyout is a full-height side sheet (480x1020 here) whose *visible*
// content sits at the bottom of that window, so the mod can only shift it horizontally -
// moving the window vertically is possible, but the content's offset inside the window is
// what decides where it lands, and that offset changes (a media card appears above the
// panel whenever something is playing). So: measure the content, then move the window.
//   * capture the screen before the panel opens
//   * wait for the flyout, capture again, diff -> the content rectangle
//   * put the content's top just below the tray bar (flip above it if there is no room)
// Everything happens in the dock, so no round trip through the mod (which keeps doing the
// horizontal part and the initial position).
struct QuickSettingsPlace {
    bool pending = false;
    DWORD armedAt = 0;
    RECT button{};
    std::vector<uint32_t> before;
    int w = 0, h = 0;
};
static QuickSettingsPlace g_qs;

static bool CaptureScreenInto(std::vector<uint32_t>& out, int* pw, int* ph) {
    int w = GetSystemMetrics(SM_CXSCREEN), h = GetSystemMetrics(SM_CYSCREEN);
    if (w <= 0 || h <= 0) return false;
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    if (!screen) return false;
    HBITMAP bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bmp) { ReleaseDC(nullptr, screen); return false; }
    HDC dc = CreateCompatibleDC(screen);
    HGDIOBJ old = SelectObject(dc, bmp);
    BOOL ok = BitBlt(dc, 0, 0, w, h, screen, 0, 0, SRCCOPY);
    if (ok) {
        // copy *before* the bitmap goes away: `bits` points into the DIB, so reading it
        // after DeleteObject reads freed memory (that crashed the dock once already)
        out.assign((uint32_t*)bits, (uint32_t*)bits + (size_t)w * h);
        *pw = w;
        *ph = h;
    }
    SelectObject(dc, old);
    DeleteObject(bmp);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
    return ok != FALSE;
}

static void QuickSettingsBeginPlacement(const RECT& button) {
    g_qs.button = button;
    g_qs.armedAt = GetTickCount();
    g_qs.pending = CaptureScreenInto(g_qs.before, &g_qs.w, &g_qs.h);
}

// Called from the tick: wait for the flyout, measure its content, put it next to the button.
static void QuickSettingsTick(DWORD now) {
    if (!g_qs.pending) return;
    if ((DWORD)(now - g_qs.armedAt) < 420) return;      // let the open animation finish

    HWND panel = GetForegroundWindow();
    wchar_t cls[64]{};
    if (!panel || !GetClassNameW(panel, cls, 64) || _wcsicmp(cls, L"ControlCenterWindow") != 0) {
        if ((DWORD)(now - g_qs.armedAt) > 1500) g_qs.pending = false;   // never showed up
        return;
    }
    g_qs.pending = false;

    RECT wr{};
    if (!GetWindowRect(panel, &wr)) return;

    std::vector<uint32_t> after;
    int aw = 0, ah = 0;
    if (!CaptureScreenInto(after, &aw, &ah) || aw != g_qs.w || ah != g_qs.h) return;

    // bbox of everything that changed *inside the panel window* -> its visible content.
    // Restricting to the window matters: a full-screen diff also catches whatever the app
    // behind us is doing (the first version measured "1837x1029", i.e. noise).
    const int thr = 24;
    int x0 = wr.left < 0 ? 0 : wr.left;
    int y0 = wr.top < 0 ? 0 : wr.top;
    int x1 = wr.right > aw ? aw : wr.right;
    int y1 = wr.bottom > ah ? ah : wr.bottom;
    int left = INT_MAX, top = INT_MAX, right = INT_MIN, bottom = INT_MIN, changed = 0;
    for (int y = y0; y < y1; y++) {
        const uint32_t* a = &g_qs.before[(size_t)y * aw];
        const uint32_t* b = &after[(size_t)y * aw];
        for (int x = x0; x < x1; x++) {
            uint32_t p = a[x], q = b[x];
            int dr = abs((int)((p >> 16) & 0xFF) - (int)((q >> 16) & 0xFF));
            int dg = abs((int)((p >> 8) & 0xFF) - (int)((q >> 8) & 0xFF));
            int db = abs((int)(p & 0xFF) - (int)(q & 0xFF));
            if (dr + dg + db <= thr) continue;
            changed++;
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
        }
    }
    if (changed < 4000 || right <= left || bottom <= top) {
        DLog(L"qs: content not measurable (changed=%d) - panel stays where it is", changed);
        return;
    }

    int contentTop = top, contentBottom = bottom + 1;
    int contentH = contentBottom - contentTop;

    RECT work{};
    MONITORINFO mi{sizeof(mi)};
    HMONITOR mon = MonitorFromWindow(panel, MONITOR_DEFAULTTONEAREST);
    if (mon && GetMonitorInfoW(mon, &mi)) work = mi.rcWork;
    else work = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};

    const int gap = 8;
    int targetTop = g_qs.button.bottom + gap;                 // preferred: right under the button
    if (targetTop + contentH > work.bottom) {
        int above = (int)g_qs.button.top - gap - contentH;    // no room: flip above
        if (above >= work.top) targetTop = above;
    }
    if (targetTop + contentH > work.bottom) targetTop = work.bottom - contentH;
    if (targetTop < work.top) targetTop = work.top;

    int dy = targetTop - contentTop;
    if (dy == 0) {
        DLog(L"qs: content %dx%d already at %d (button %ld..%ld)", right - left + 1, contentH,
             contentTop, (long)g_qs.button.top, (long)g_qs.button.bottom);
        return;
    }
    SetWindowPos(panel, nullptr, wr.left, wr.top + dy, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSENDCHANGING);
    DLog(L"qs: content %dx%d at y=%d -> moved the panel by %d (button %ld..%ld, work %ld..%ld)",
         right - left + 1, contentH, contentTop, dy, (long)g_qs.button.top,
         (long)g_qs.button.bottom, (long)work.top, (long)work.bottom);
}

// ---------------------------------------------------------------- tray icons
// Windows 11 dropped the classic ToolbarWindow32 tray, so TB_GETBUTTON is gone.
// Explorer does keep a record of every icon it has shown under
// HKCU\Control Panel\NotifyIconSettings: owning executable, tooltip and a PNG
// snapshot of the icon. Keeping only the executables that are actually running
// gives the live tray set.
struct TrayEntry {
    std::wstring tip;
    std::wstring exe;         // full path, lower case
    std::vector<uint32_t> px; // premultiplied BGRA, cachedPx square
    int cachedPx = 0;
    // live-tray data from the Windhawk bridge mod (tray-icons-bridge)
    unsigned long long ownerHwnd = 0;
    unsigned int ownerUid = 0;
    unsigned int callbackMsg = 0;
    bool hasBridge = false;
};
static std::vector<TrayEntry> g_tray;

static bool TrayWantsDoubleClick(const TrayEntry& e);   // defined next to ForwardTrayClick

// Layout must match windhawk/tray-icons-bridge.wh.cpp exactly.
struct TrayBridgeEntry {
    unsigned long long hwnd;
    unsigned int uid;
    unsigned int cbMsg;
    unsigned int isGuid;
    unsigned int pid;
    GUID guid;
    wchar_t tip[128];
    wchar_t exe[MAX_PATH];
};
struct TrayBridgeShm {
    unsigned int magic;
    unsigned int version;
    unsigned int count;
    unsigned int capacity;
    unsigned long long updatedMs;
    TrayBridgeEntry entries[128];
};
static HANDLE g_trayMap = nullptr;
static const TrayBridgeShm* g_trayShm = nullptr;

// The shell keeps the notification-area table to itself (no API, and Win11 has no
// ToolbarWindow32 any more). The Windhawk bridge mod publishes it; without the
// mod this returns false and everything falls back to the registry set.
// The mod creates the shared block as well, but whoever creates it first decides its
// DACL: after a boot an elevated vendor helper often wins, and then every read from
// this medium-integrity process fails with "access denied" (the dock silently fell
// back to the registry list - which is how a whole session of tray bugs started).
// So create it ourselves, permissively, and keep the handle for our lifetime: that
// also stops the block from dying (and losing every registration) whenever Windhawk
// reloads the mod everywhere.
static HANDLE g_trayOwnMap = nullptr;

static void TrayBridgeEnsureExists() {
    if (g_trayOwnMap) return;
    SECURITY_DESCRIPTOR sd{};
    SECURITY_ATTRIBUTES sa{};
    if (!InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION)) return;
    if (!SetSecurityDescriptorDacl(&sd, TRUE, nullptr, FALSE)) return;
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = &sd;
    sa.bInheritHandle = FALSE;
    const wchar_t* name = L"Local\\DockTrayBridge_v1";
    g_trayOwnMap =
        CreateFileMappingW(INVALID_HANDLE_VALUE, &sa, PAGE_READWRITE, 0, sizeof(TrayBridgeShm), name);
    DLog(L"tray: bridge block %s (err=%lu)",
         g_trayOwnMap ? L"available" : L"NOT available", (unsigned long)GetLastError());
}
static bool TrayBridgeOpen() {
    if (g_trayShm) {
        if (g_trayShm->magic == 0x59415254) return true;      // still ours
        // the mod was reloaded: this view points at a dead section
        UnmapViewOfFile((LPCVOID)g_trayShm);
        g_trayShm = nullptr;
        if (g_trayMap) {
            CloseHandle(g_trayMap);
            g_trayMap = nullptr;
        }
    }
    if (!g_trayMap)
        g_trayMap = OpenFileMappingW(FILE_MAP_READ, FALSE, L"Local\\DockTrayBridge_v1");
        if (!g_trayMap && g_trayOwnMap) g_trayMap = g_trayOwnMap;   // created by us
    if (!g_trayMap) {
        DWORD err = GetLastError();
        if (err == ERROR_ACCESS_DENIED) {
            // The section exists but its DACL blocks us: it was created by an
            // elevated process before the mod started creating it with a NULL DACL.
            DLog(L"tray: bridge mapping exists but access was DENIED (error 5) - the mod "
                 L"that created it predates the permissive-DACL fix");
        } else if (err != ERROR_FILE_NOT_FOUND) {
            DLog(L"tray: OpenFileMapping failed, error %lu", (unsigned long)err);
        }
        return false;
    }
    g_trayShm =
        (const TrayBridgeShm*)MapViewOfFile(g_trayMap, FILE_MAP_READ, 0, 0, sizeof(TrayBridgeShm));
    if (!g_trayShm) {
        CloseHandle(g_trayMap);
        g_trayMap = nullptr;
        return false;
    }
    if (g_trayShm->magic != 0x59415254) {      // 'TRAY'
        UnmapViewOfFile((LPCVOID)g_trayShm);
        g_trayShm = nullptr;
        return false;
    }
    return true;
}

// "{GUID}\relative\path" -> real path (that is how the key stores known folders)
static std::wstring ExpandFolderPath(const std::wstring& raw) {
    std::wstring p = raw;
    if (!p.empty() && p[0] == L'{') {
        size_t close = p.find(L'}');
        if (close != std::wstring::npos) {
            GUID g{};
            if (SUCCEEDED(IIDFromString(p.substr(0, close + 1).c_str(), &g))) {
                PWSTR base = nullptr;
                if (SUCCEEDED(SHGetKnownFolderPath(g, 0, nullptr, &base))) {
                    std::wstring rest = p.substr(close + 1);
                    while (!rest.empty() && rest[0] == L'\\') rest.erase(0, 1);
                    std::wstring full = std::wstring(base) + L"\\" + rest;
                    CoTaskMemFree(base);
                    return full;
                }
            }
        }
    }
    wchar_t buf[MAX_PATH * 2]{};
    if (ExpandEnvironmentStringsW(p.c_str(), buf, MAX_PATH * 2)) return buf;
    return p;
}

// PNG -> premultiplied BGRA at px x px (WIC, no extra dependency)
static std::vector<uint32_t> DecodePng(const BYTE* data, DWORD size, int px) {
    std::vector<uint32_t> out;
    if (!data || !size || px <= 0) return out;
    IWICImagingFactory* fac = nullptr;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IWICImagingFactory, (void**)&fac)))
        return out;
    IWICStream* stream = nullptr;
    IWICBitmapDecoder* dec = nullptr;
    IWICBitmapFrameDecode* frame = nullptr;
    IWICFormatConverter* conv = nullptr;
    IWICBitmapScaler* scaler = nullptr;
    bool ok = false;
    if (SUCCEEDED(fac->CreateStream(&stream)) &&
        SUCCEEDED(stream->InitializeFromMemory(const_cast<BYTE*>(data), size)) &&
        SUCCEEDED(
            fac->CreateDecoderFromStream(stream, nullptr, WICDecodeMetadataCacheOnLoad, &dec)) &&
        SUCCEEDED(dec->GetFrame(0, &frame)) && SUCCEEDED(fac->CreateFormatConverter(&conv)) &&
        SUCCEEDED(conv->Initialize(frame, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone,
                                   nullptr, 0, WICBitmapPaletteTypeCustom)) &&
        SUCCEEDED(fac->CreateBitmapScaler(&scaler)) &&
        SUCCEEDED(scaler->Initialize(conv, px, px, WICBitmapInterpolationModeFant))) {
        out.resize((size_t)px * px);
        ok = SUCCEEDED(
            scaler->CopyPixels(nullptr, px * 4, (UINT)(out.size() * 4), (BYTE*)out.data()));
    }
    if (scaler) scaler->Release();
    if (conv) conv->Release();
    if (frame) frame->Release();
    if (dec) dec->Release();
    if (stream) stream->Release();
    fac->Release();
    if (!ok) out.clear();
    return out;
}

static std::vector<std::wstring> RunningExePaths() {
    std::vector<std::wstring> v;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return v;
    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe)) {
        do {
            HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID);
            if (!p) continue;
            wchar_t path[MAX_PATH * 2]{};
            DWORD sz = MAX_PATH * 2;
            if (QueryFullProcessImageNameW(p, 0, path, &sz)) v.push_back(Lower(path));
            CloseHandle(p);
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return v;
}

// Box-filter an HICON's real bitmap down to px x px (premultiplied). This is the
// same resample the strip icons use, so tray icons get identical quality.
static std::vector<uint32_t> RasterIconPx(HICON ic, int px) {
    std::vector<uint32_t> out;
    if (!ic || px <= 0) return out;
    ICONINFO ii{};
    if (!GetIconInfo(ic, &ii)) return out;
    BITMAP bm{};
    GetObject(ii.hbmColor, sizeof(bm), &bm);
    int sw = bm.bmWidth, sh = bm.bmHeight;
    if (sw <= 0 || sh <= 0) {
        if (ii.hbmColor) DeleteObject(ii.hbmColor);
        if (ii.hbmMask) DeleteObject(ii.hbmMask);
        return out;
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

    out.assign((size_t)px * px, 0);
    // Some executables (store apps, small tools) only ship a 16-32 px frame. A
    // box filter degenerates into nearest-neighbour when scaling *up*, which is
    // what turned those into 2x2 pixel blocks; bilinear keeps them smooth.
    bool upscale = (sw < px || sh < px);
    if (upscale) {
        for (int y = 0; y < px; y++) {
            double fy = (y + 0.5) * sh / px - 0.5;
            int y0 = (int)floor(fy);
            double ty = fy - y0;
            if (y0 < 0) { y0 = 0; ty = 0; }
            int y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
            if (y0 >= sh) y0 = sh - 1;
            for (int x = 0; x < px; x++) {
                double fx = (x + 0.5) * sw / px - 0.5;
                int x0 = (int)floor(fx);
                double tx = fx - x0;
                if (x0 < 0) { x0 = 0; tx = 0; }
                int x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
                if (x0 >= sw) x0 = sw - 1;
                uint32_t p00 = src[(size_t)y0 * sw + x0], p10 = src[(size_t)y0 * sw + x1];
                uint32_t p01 = src[(size_t)y1 * sw + x0], p11 = src[(size_t)y1 * sw + x1];
                double w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty,
                       w11 = tx * ty;
                auto pm = [&](uint32_t v, int shift) {          // premultiplied channel
                    int s = (int)((v >> 24) & 0xFF);
                    return ((v >> shift) & 0xFF) * s / 255.0;
                };
                auto mix = [&](int shift) {
                    double v = pm(p00, shift) * w00 + pm(p10, shift) * w10 +
                               pm(p01, shift) * w01 + pm(p11, shift) * w11;
                    int iv = (int)(v + 0.5);
                    return iv < 0 ? 0 : (iv > 255 ? 255 : iv);
                };
                double a = (((p00 >> 24) & 0xFF) * w00 + ((p10 >> 24) & 0xFF) * w10 +
                            ((p01 >> 24) & 0xFF) * w01 + ((p11 >> 24) & 0xFF) * w11);
                int ia = (int)(a + 0.5);
                if (!ia) continue;
                out[(size_t)y * px + x] =
                    (ia << 24) | (mix(16) << 16) | (mix(8) << 8) | mix(0);
            }
        }
        return out;
    }
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
            if (!n || !a) continue;
            out[(size_t)y * px + x] = ((a / n) << 24) | ((r / n) << 16) | ((g / n) << 8) | (b / n);
        }
    }
    return out;
}

static int IconBitmapWidth(HICON ic) {
    if (!ic) return 0;
    ICONINFO ii{};
    if (!GetIconInfo(ic, &ii)) return 0;
    BITMAP bm{};
    GetObject(ii.hbmColor, sizeof(bm), &bm);
    if (ii.hbmColor) DeleteObject(ii.hbmColor);
    if (ii.hbmMask) DeleteObject(ii.hbmMask);
    return bm.bmWidth;
}

// not in the SDK headers we include, but exported by user32 since XP
extern "C" __declspec(dllimport) UINT WINAPI PrivateExtractIconsW(LPCWSTR, int, int, int, HICON*,
                                                                 UINT*, UINT, UINT);

// The executable's own artwork, taken from the shell's jumbo frame exactly like
// the strip icons. The registry snapshot is only a 16-40 px thumbnail, so it
// cannot survive a 44 px cell no matter how it is scaled.
static std::vector<uint32_t> TrayIconFromPath(const std::wstring& path, int px) {
    std::vector<uint32_t> v;
    if (path.empty()) return v;
    int saveBucket = g_iconBucket;
    g_iconBucket = 256;
    HICON ic = HiResIconForPath(path);
    // The shell sometimes hands back a 16-32 px frame for store apps / obscure
    // tools. Ask the file itself for a big frame before giving up.
    if (!ic || IconBitmapWidth(ic) < px) {
        HICON big = nullptr;
        if (PrivateExtractIconsW(path.c_str(), 0, 128, 128, &big, nullptr, 1, 0) == 1 && big) {
            if (IconBitmapWidth(big) > IconBitmapWidth(ic)) {
                if (ic) DestroyIcon(ic);
                ic = big;
            } else {
                DestroyIcon(big);
            }
        }
    }
    if (ic) v = RasterIconPx(ic, px);
    if (ic) DestroyIcon(ic);
    if (v.empty()) {
        HICON ic2 = LoadIconFromPath(path);
        if (ic2) {
            v = RasterIconPx(ic2, px);
            DestroyIcon(ic2);
        }
    }
    g_iconBucket = saveBucket;
    if (!v.empty()) NormalizeIconSquare(v, px);
    return v;
}

// Names of the buttons the *native* tray currently exposes, via UI Automation on
// the taskbar's XAML tree. This is what tells "this app really has a tray icon
// right now" apart from "this app has a tray icon in its history".
static std::vector<std::wstring> TrayUiNames() {
    std::vector<std::wstring> names;
    HWND tray = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!tray) return names;
    IUIAutomation* uia = nullptr;
    if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IUIAutomation, (void**)&uia)) ||
        !uia)
        return names;
    IUIAutomationElement* root = nullptr;
    if (SUCCEEDED(uia->ElementFromHandle(tray, &root)) && root) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_I4;
        v.lVal = UIA_ButtonControlTypeId;
        IUIAutomationCondition* cond = nullptr;
        if (SUCCEEDED(uia->CreatePropertyCondition(UIA_ControlTypePropertyId, v, &cond)) && cond) {
            IUIAutomationElementArray* arr = nullptr;
            if (SUCCEEDED(root->FindAll(TreeScope_Descendants, cond, &arr)) && arr) {
                int n = 0;
                arr->get_Length(&n);
                for (int i = 0; i < n; i++) {
                    IUIAutomationElement* e = nullptr;
                    if (FAILED(arr->GetElement(i, &e)) || !e) continue;
                    BSTR name = nullptr;
                    if (SUCCEEDED(e->get_CurrentName(&name)) && name && name[0]) {
                        names.push_back(Lower(name));
                        SysFreeString(name);
                    }
                    e->Release();
                }
                arr->Release();
            }
            cond->Release();
        }
        root->Release();
    }
    uia->Release();
    return names;
}

static bool TrayNameMatches(const std::vector<std::wstring>& names, const std::wstring& tipExe) {
    for (const auto& n : names) {
        if (n.size() < 2) continue;
        if (tipExe.find(n) != std::wstring::npos) return true;
        if (n.find(tipExe) != std::wstring::npos && tipExe.size() >= 3) return true;
    }
    return false;
}

// A tray icon's callback message can be lost: many apps re-register with NIM_MODIFY
// and pass 0, which the (not yet recompiled) bridge mod stores verbatim. Remember the
// last triple that worked per executable and reuse it, so a right click keeps working
// until the app restarts (the window handle is validated before use).
struct TrayCb {
    unsigned long long hwnd;
    unsigned uid;
    unsigned msg;
};
// Some apps flap their tray icon: NVDisplay.Container removes and re-adds its icon
// within a second (it refreshes the GPU temperature in the tip), and the bridge table
// legitimately has no entry for that moment - the panel then loses the cell, which looks
// like "NVIDIA appears for a moment and vanishes". Remember the last complete set and
// keep an entry for a short grace period as long as its owner window is still alive.
struct TrayRemembered {
    TrayEntry e;
    DWORD goneAt = 0;
};
static std::map<std::wstring, TrayRemembered> g_trayRemembered;

static std::wstring TrayKey(const TrayEntry& e) {
    wchar_t b[64]{};
    _snwprintf_s(b, _countof(b), _TRUNCATE, L"|%u|%llx", e.ownerUid, e.ownerHwnd);
    return e.exe + b;
}

static std::map<std::wstring, TrayCb> g_trayCbCache;

static void StartTrayWarmup(int delayMs);
static int g_lastTrayCount = 0;      // how many icons the bridge had last time
static DWORD g_trayRetryAt = 0;      // one-shot re-read after asking apps to re-register
static bool g_trayRetryBusy = false;

// Live notification-area contents, straight from explorer via the Windhawk mod.
static bool BuildTrayFromBridge() {
    if (!TrayBridgeOpen()) {
        DLog(L"tray: bridge mapping not found (mod not running?)");
        return false;
    }
    int count = (int)g_trayShm->count;
    DLog(L"tray: bridge v%u capacity=%u count=%d", g_trayShm->version, g_trayShm->capacity, count);
    // A bridge reload (recompiled mod, Windhawk restart) recreates the shared table
    // empty and running apps only re-register when the shell asks them to. Ask once,
    // when the panel is opened and the table looks short - no background polling:
    // nothing in this program looks at the tray unless the user opens the grid.
    // This has to happen *before* the empty check, otherwise a freshly emptied table
    // silently falls back to the registry and never refills (that is exactly how a
    // reboot + recompile left every icon unclickable).
    {
        static DWORD lastAsk = 0;
        DWORD now = GetTickCount();
        if (!g_trayRetryBusy && (count <= 2 || count < g_lastTrayCount) &&
            (!lastAsk || now - lastAsk > 5000)) {
            lastAsk = now;
            DLog(L"tray: bridge has %d icon(s) (last time %d) - asking apps to re-register",
                 count, g_lastTrayCount);
            StartTrayWarmup(0);
            g_trayRetryAt = GetTickCount() + 400;   // re-read once the answers came back
        }
    }
    if (count <= 0) {
        DLog(L"tray: the bridge table is EMPTY - falling back to the registry list for now");
        return false;
    }
    g_lastTrayCount = count;
    g_iconBucket = 256;
    for (int i = 0; i < count && i < 128; i++) {
        const TrayBridgeEntry& b = g_trayShm->entries[i];
        if (!b.tip[0] && !b.exe[0]) continue;
        // The bridge table is a shared array: an app that quits (or is killed) leaves its
        // slot behind, and the native tray would have dropped that icon. The window it
        // registered from dies with the process, so "still a window" is a good liveness
        // test. Entries without a hwnd (GUID icons) are kept - they are shown, just not
        // forwardable.
        if (b.hwnd && !IsWindow((HWND)(ULONG_PTR)b.hwnd)) {
            DLog(L"tray: dropping stale bridge entry '%s' (%s) - its window is gone",
                 b.tip, b.exe);
            continue;
        }
        TrayEntry e;
        e.exe = Lower(b.exe);
        // several apps register without a tooltip: show the executable's name
        if (b.tip[0]) {
            e.tip = b.tip;
        } else if (!e.exe.empty()) {
            size_t slash = e.exe.find_last_of(L'\\');
            e.tip = e.exe.substr(slash == std::wstring::npos ? 0 : slash + 1);
        } else {
            e.tip = L" ";
        }
        e.ownerHwnd = b.hwnd;
        e.ownerUid = b.uid;
        e.callbackMsg = b.cbMsg;
        e.hasBridge = (b.hwnd != 0 && b.cbMsg != 0);
        if (e.hasBridge) {
            g_trayCbCache[e.exe] = TrayCb{b.hwnd, b.uid, b.cbMsg};
        } else if (!e.exe.empty()) {
            auto it = g_trayCbCache.find(e.exe);
            if (it != g_trayCbCache.end() && IsWindow((HWND)(ULONG_PTR)it->second.hwnd)) {
                DLog(L"tray: '%s' came back without a callback - reusing the last good one "
                     L"(hwnd=%p msg=0x%X)", e.tip.c_str(), (void*)(ULONG_PTR)it->second.hwnd,
                     it->second.msg);
                e.ownerHwnd = it->second.hwnd;
                e.ownerUid = it->second.uid;
                e.callbackMsg = it->second.msg;
                e.hasBridge = true;
            }
        }
        // No de-duplication against the strip: the grid mirrors the native
        // notification area, which legitimately holds apps that also have a
        // taskbar button (the strip). Windows itself overlaps the two.
        // same app on the strip -> its artwork (sharpest); else the exe's own
        for (const auto& it : g_items) {
            if (!it.icon || it.exePath.empty() || it.exePath != e.exe) continue;
            std::vector<uint32_t> v = RasterIconPx(it.icon, 64);
            if (!v.empty()) {
                NormalizeIconSquare(v, 64);
                e.px.swap(v);
                e.cachedPx = 64;
            }
            break;
        }
        if (e.px.empty() && !e.exe.empty()) {
            std::vector<uint32_t> v = TrayIconFromPath(e.exe, 64);
            if (!v.empty()) {
                e.px.swap(v);
                e.cachedPx = 64;
            }
        }
        bool dup = false;
        for (auto& o : g_tray) {
            if (o.exe != e.exe || o.ownerHwnd != e.ownerHwnd || o.ownerUid != e.ownerUid) continue;
            dup = true;
            // One app can register several icons (QQ: one per process). Keep a
            // single cell, but prefer the registration that actually carries a
            // callback message - otherwise the first, callback-less record would
            // hide the fact that a usable one exists.
            if (!o.hasBridge && e.hasBridge) {
                o.ownerHwnd = e.ownerHwnd;
                o.ownerUid = e.ownerUid;
                o.callbackMsg = e.callbackMsg;
                o.hasBridge = e.hasBridge;
                DLog(L"tray: '%s' duplicate upgraded to hwnd=%p msg=0x%X", o.tip.c_str(),
                     (void*)(ULONG_PTR)o.ownerHwnd, o.callbackMsg);
            }
            break;
        }
        if (!dup) {
            DLog(L"tray[%d] tip='%s' exe=%s bridge=%d", (int)g_tray.size(), e.tip.c_str(),
                 e.exe.c_str(), (int)e.hasBridge);
            g_tray.push_back(std::move(e));
        }
    }
    // remember what we saw, and give a just-vanished icon a grace period
    {
        DWORD now = GetTickCount();
        std::set<std::wstring> seen;
        for (const auto& e : g_tray) {
            seen.insert(TrayKey(e));
            g_trayRemembered[TrayKey(e)] = TrayRemembered{e, 0};
        }
        for (auto it = g_trayRemembered.begin(); it != g_trayRemembered.end();) {
            if (seen.count(it->first)) { ++it; continue; }
            if (!it->second.goneAt) it->second.goneAt = now;
            DWORD dead = now - it->second.goneAt;
            bool alive = it->second.e.ownerHwnd &&
                         IsWindow((HWND)(ULONG_PTR)it->second.e.ownerHwnd);
            if (dead < 30000 && alive) {
                DLog(L"tray: '%s' vanished %lu ms ago - keeping its cell (owner window alive)",
                     it->second.e.tip.c_str(), (unsigned long)dead);
                g_tray.push_back(it->second.e);
                ++it;
            } else {
                if (dead >= 30000)
                    DLog(L"tray: '%s' has been gone for %lu ms - dropping it",
                         it->second.e.tip.c_str(), (unsigned long)dead);
                it = g_trayRemembered.erase(it);
            }
        }
    }
    std::sort(g_tray.begin(), g_tray.end(),
              [](const TrayEntry& a, const TrayEntry& b) { return a.tip < b.tip; });
    DLog(L"tray: %d icons from the bridge (live tray, full native set)",
         (int)g_tray.size());
    // The [tray] double click settings are parsed in LoadConfig(), which runs before the log
    // file is open - so report them here, where the grid's contents are decided.
    {
        static bool logged = false;
        if (!logged) {
            logged = true;
            std::wstring list;
            for (const auto& t : g_trayDoubleClick) list += (list.empty() ? L"" : L",") + t;
            std::wstring except;
            for (const auto& t : g_trayDoubleClickExcept)
                except += (except.empty() ? L"" : L",") + t;
            DLog(L"tray: double click all=%d list=[%s] except=[%s] autoDoubleClick=%d",
                 (int)g_trayDoubleClickAll, list.c_str(), except.c_str(),
                 g_trayAutoDoubleClick);
            int n = (int)g_tray.size();
            int cols = (int)ceil(sqrt((double)n));
            if (cols < 3) cols = 3;
            if (cols > 8) cols = 8;
            DLog(L"tray: grid order %d cells, %d columns", n, cols);
            for (int i = 0; i < n; i++)
                DLog(L"tray: cell %d (r%d,c%d) '%s' (%s) twice=%d", i, i / cols, i % cols,
                     g_tray[i].tip.c_str(), g_tray[i].exe.c_str(),
                     (int)TrayWantsDoubleClick(g_tray[i]));
        }
    }
    return !g_tray.empty();
}

// One nudge after startup: tray apps answered "TaskbarCreated" long before the
// bridge mod was injected, so their icons would be missing from the table. This is
// the same message the shell sends after an explorer restart; every app answers by
// registering its icon again, in its own process, where the mod is listening.
static BOOL CALLBACK PostTaskbarCreated(HWND h, LPARAM lp) {
    PostMessageW(h, (UINT)lp, 0, 0);
    return TRUE;
}

// The shell sends "TaskbarCreated" after an explorer restart and every app answers
// by registering its icon again - in its own process, where the bridge mod lives.
static void BroadcastTaskbarCreated() {
    const UINT msg = RegisterWindowMessageW(L"TaskbarCreated");
    if (!msg) return;
    SendMessageTimeoutW(HWND_BROADCAST, msg, 0, 0, SMTO_ABORTIFHUNG | SMTO_NORMAL, 1500, nullptr);
    EnumWindows(&PostTaskbarCreated, (LPARAM)msg);
}

// delayMs == 0 -> "the bridge table looks empty, refresh it now" (see BuildTrayFromBridge)
static DWORD WINAPI TrayWarmupThread(void* param) {
    int delayMs = (int)(INT_PTR)param;
    if (delayMs > 0) Sleep((DWORD)delayMs);
    BroadcastTaskbarCreated();
    DLog(L"tray: asked apps to re-register (TaskbarCreated)");
    return 0;
}

static void StartTrayWarmup(int delayMs) {
    HANDLE th = CreateThread(nullptr, 0, TrayWarmupThread, (LPVOID)(INT_PTR)delayMs, 0, nullptr);
    if (th) CloseHandle(th);
}

static void BuildTray() {
    g_tray.clear();
    if (BuildTrayFromBridge()) return;
    std::vector<std::wstring> running = RunningExePaths();
    HKEY root = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\NotifyIconSettings", 0, KEY_READ, &root) !=
        ERROR_SUCCESS) {
        DLog(L"tray: cannot open NotifyIconSettings");
        return;
    }
    int seen = 0;
    for (DWORD i = 0;; i++) {
        wchar_t name[256]{};
        DWORD n = 256;
        if (RegEnumKeyExW(root, i, name, &n, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS)
            break;
        HKEY k = nullptr;
        if (RegOpenKeyExW(root, name, 0, KEY_READ, &k) != ERROR_SUCCESS) continue;
        seen++;
        wchar_t exe[MAX_PATH * 2]{};
        DWORD exeLen = sizeof(exe);
        bool haveExe = RegQueryValueExW(k, L"ExecutablePath", nullptr, nullptr, (BYTE*)exe,
                                        &exeLen) == ERROR_SUCCESS &&
                       exe[0];
        wchar_t tip[512]{};
        DWORD tipLen = sizeof(tip);
        RegQueryValueExW(k, L"InitialTooltip", nullptr, nullptr, (BYTE*)tip, &tipLen);
        DWORD snapLen = 0;
        RegQueryValueExW(k, L"IconSnapshot", nullptr, nullptr, nullptr, &snapLen);
        std::vector<BYTE> png;
        if (snapLen > 8 && snapLen < 4 * 1024 * 1024) {
            png.resize(snapLen);
            if (RegQueryValueExW(k, L"IconSnapshot", nullptr, nullptr, png.data(), &snapLen) !=
                ERROR_SUCCESS)
                png.clear();
        }
        RegCloseKey(k);
        if (!haveExe) continue;
        std::wstring path = Lower(ExpandFolderPath(exe));
        if (path.empty()) continue;
        if (std::find(running.begin(), running.end(), path) == running.end())
            continue;                     // history entry, not a live icon
        TrayEntry e;
        e.exe = path;
        e.tip = tip;
        if (e.tip.empty()) e.tip = path.substr(path.find_last_of(L'\\') + 1);
        // The snapshot is only a 16-40 px thumbnail; scaling it to a 44 px cell
        // is what made the tray icons look soft. Prefer the executable's own
        // artwork (shell jumbo frame, same pipeline as the strip icons) and keep
        // the snapshot only when it is already big enough to be worth it.
        int snapPx = 0;
        if (png.size() >= 24) {
            snapPx = (int)(((DWORD)png[16] << 24) | ((DWORD)png[17] << 16) |
                           ((DWORD)png[18] << 8) | (DWORD)png[19]);   // IHDR width
        }
        bool wantHiRes = true;
        bool iconSet = false;
        const wchar_t* srcName = L"none";
        // 1) The app is also on the strip: borrow its artwork. Same pipeline the
        //    strip icons use, so the tray entry is as sharp as the strip one -
        //    the tray's own snapshot is only 16-40 px.
        for (const auto& it : g_items) {
            if (!it.icon || it.exePath.empty() || it.exePath != path) continue;
            std::vector<uint32_t> v = RasterIconPx(it.icon, 64);
            if (!v.empty()) {
                NormalizeIconSquare(v, 64);
                e.px.swap(v);
                e.cachedPx = 64;
                iconSet = true;
                wantHiRes = false;
                srcName = L"dock";
            }
            break;
        }
        // 2) A snapshot that is already big enough keeps its own artwork (it may
        //    carry state the app icon does not, e.g. muted / upload progress).
        if (!iconSet && snapPx >= 48) {
            e.px = DecodePng(png.data(), (DWORD)png.size(), 64);
            if (!e.px.empty()) {
                e.cachedPx = 64;
                iconSet = true;
                wantHiRes = false;
                srcName = L"snap";
            }
        }
        // 3) Otherwise the executable's own 256 px frame.
        if (wantHiRes) {
            std::vector<uint32_t> hi = TrayIconFromPath(path, 64);
            if (!hi.empty()) {
                e.px.swap(hi);
                e.cachedPx = 64;
                iconSet = true;
                srcName = L"exe";
            }
        }
        // 4) Last resort: the 16-40 px snapshot, upscaled.
        if (!iconSet && !png.empty()) {
            e.px = DecodePng(png.data(), (DWORD)png.size(), 64);
            if (!e.px.empty()) { e.cachedPx = 64; srcName = L"snap-small"; }
        }
        bool dup = false;
        for (auto& o : g_tray)
            if (o.exe == e.exe) { dup = true; break; }   // one icon per executable
        if (!dup) {
            DLog(L"tray[%d] %s src=%s snap=%d", (int)g_tray.size(), e.tip.c_str(), srcName,
                 snapPx);
            g_tray.push_back(std::move(e));
        }
    }
    RegCloseKey(root);
    // Keep only what the native tray is showing *right now*. UI Automation gives
    // the live button names; a registry entry whose app currently has no tray
    // icon (a pinned app that is simply not running) does not match anything.
    {
        std::vector<std::wstring> uiaNames = TrayUiNames();
        if (!uiaNames.empty()) {
            std::vector<TrayEntry> kept;
            for (auto& e : g_tray) {
                std::wstring base = e.exe.substr(e.exe.find_last_of(L'\\') + 1);
                size_t dot = base.find_last_of(L'.');
                if (dot != std::wstring::npos) base.resize(dot);
                std::wstring probe = Lower(e.tip) + L" " + Lower(base);
                if (TrayNameMatches(uiaNames, probe)) kept.push_back(std::move(e));
            }
            DLog(L"tray: UIA %d buttons -> %d of %d kept", (int)uiaNames.size(),
                 (int)kept.size(), (int)g_tray.size());
            if (kept.size() >= 2) g_tray.swap(kept);
            else DLog(L"tray: UIA filter would leave %d entries - ignored", (int)kept.size());
        } else {
            DLog(L"tray: UIA sees no tray buttons - using the running-process set");
        }
    }
    std::sort(g_tray.begin(), g_tray.end(),
              [](const TrayEntry& a, const TrayEntry& b) { return a.tip < b.tip; });
    DLog(L"tray: %d live of %d recorded", (int)g_tray.size(), seen);
}

static bool LaunchPath(const std::wstring& path, const wchar_t* what) {
    if (path.empty()) return false;
    std::wstring cmd = L"\"" + path + L"\"";
    std::vector<wchar_t> cmdBuf(cmd.begin(), cmd.end());
    cmdBuf.push_back(0);
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::wstring workdir = path.substr(0, path.find_last_of(L'\\'));
    if (CreateProcessW(path.c_str(), cmdBuf.data(), nullptr, nullptr, FALSE, 0, nullptr,
                       workdir.c_str(), &si, &pi)) {
        DLog(L"launch %s: pid=%lu target=%s", what, pi.dwProcessId, path.c_str());
        CloseHandle(pi.hThread);
        if (g_launchWatch) CloseHandle(g_launchWatch);
        g_launchWatch = pi.hProcess;
        g_launchWatchPid = pi.dwProcessId;
        g_launchWatchAt = GetTickCount();
        return true;
    }
    DLog(L"launch %s: failed err=%lu target=%s", what, GetLastError(), path.c_str());
    return false;
}

// ---------------------------------------------------------------- autostart
// A shortcut in the user's Startup folder: no admin rights needed, it shows up
// in Task Manager's Startup tab, and launching from there keeps the process at
// medium integrity (a low-integrity dock cannot start other programs).
static std::wstring AutoStartPath() {
    PWSTR p = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_Startup, 0, nullptr, &p))) return L"";
    std::wstring s = std::wstring(p) + L"\\Dock.lnk";
    CoTaskMemFree(p);
    return s;
}

static bool AutoStartEnabled() {
    std::wstring lnk = AutoStartPath();
    return !lnk.empty() && PathFileExistsW(lnk.c_str());
}

static bool SetAutoStart(bool on) {
    std::wstring lnk = AutoStartPath();
    if (lnk.empty()) return false;
    if (!on) return DeleteFileW(lnk.c_str()) != 0;
    wchar_t exe[MAX_PATH]{};
    if (!GetModuleFileNameW(nullptr, exe, MAX_PATH)) return false;
    IShellLinkW* link = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW,
                                (void**)&link)))
        return false;
    link->SetPath(exe);
    std::wstring dir = exe;
    size_t slash = dir.find_last_of(L'\\');
    if (slash != std::wstring::npos) dir.resize(slash);
    link->SetWorkingDirectory(dir.c_str());
    link->SetIconLocation(exe, 0);
    link->SetDescription(L"Dock");
    IPersistFile* pf = nullptr;
    bool ok = false;
    if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, (void**)&pf))) {
        ok = SUCCEEDED(pf->Save(lnk.c_str(), TRUE));
        pf->Release();
    }
    link->Release();
    return ok;
}

// ---------------------------------------------------------------- ^ grid
// A floating panel with everything the strip cannot show at once (all windows,
// all pins) plus the tray icons. Same premultiplied drawing primitives as the
// strip, retargeted at its own DIB.
static HDC g_gridDC;
static HBITMAP g_gridBmp;
static void* g_gridBits;
static int g_gridW = 0, g_gridH = 0;
static int g_gridAllocW = 0, g_gridAllocH = 0;
static std::vector<Slot> g_gridCells;   // item >= 0 dock item, item <= -2 tray
static int g_gridHover = -1;
static DWORD g_gridOutsideAt = 0;
static LRESULT CALLBACK GridProc(HWND h, UINT msg, WPARAM wp, LPARAM lp);

static const int kGridIcon = 44;
static const int kGridCell = 60;
static const int kGridPad = 14;
static const int kGridGap = 6;
static const int kGridCapH = 10;

// Width of a string in the same font DrawTextAlpha renders with.
static int TextWidthPx(const std::wstring& s, int px) {
    if (s.empty()) return 0;
    HDC dc = GetDC(nullptr);
    HFONT f = CreateFontW(px, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                          DEFAULT_PITCH, L"Microsoft YaHei UI");
    HGDIOBJ old = SelectObject(dc, f);
    SIZE sz{};
    GetTextExtentPoint32W(dc, s.c_str(), (int)s.size(), &sz);
    SelectObject(dc, old);
    DeleteObject(f);
    ReleaseDC(nullptr, dc);
    return sz.cx;
}

// bilinear, premultiplied source -> premultiplied destination (same maths as
// BlendPremul, so it composes correctly on top of the panel)
static void BlendScaled(int x0, int y0, int dw, int dh, const uint32_t* src, int sw, int sh,
                        int clipL, int clipR) {
    if (!src || sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
    for (int y = 0; y < dh; y++) {
        double fy = (y + 0.5) * sh / dh - 0.5;
        int sy0 = (int)floor(fy);
        double ty = fy - sy0;
        if (sy0 < 0) { sy0 = 0; ty = 0; }
        int sy1 = sy0 + 1 < sh ? sy0 + 1 : sh - 1;
        if (sy0 >= sh) sy0 = sh - 1;
        for (int x = 0; x < dw; x++) {
            double fx = (x + 0.5) * sw / dw - 0.5;
            int sx0 = (int)floor(fx);
            double tx = fx - sx0;
            if (sx0 < 0) { sx0 = 0; tx = 0; }
            int sx1 = sx0 + 1 < sw ? sx0 + 1 : sw - 1;
            if (sx0 >= sw) sx0 = sw - 1;
            uint32_t p00 = src[(size_t)sy0 * sw + sx0], p10 = src[(size_t)sy0 * sw + sx1];
            uint32_t p01 = src[(size_t)sy1 * sw + sx0], p11 = src[(size_t)sy1 * sw + sx1];
            double b00 = (1 - tx) * (1 - ty), b10 = tx * (1 - ty), b01 = (1 - tx) * ty,
                   b11 = tx * ty;
            auto ch = [&](int shift) {
                double v = ((p00 >> shift) & 0xFF) * b00 + ((p10 >> shift) & 0xFF) * b10 +
                           ((p01 >> shift) & 0xFF) * b01 + ((p11 >> shift) & 0xFF) * b11;
                int iv = (int)(v + 0.5);
                return iv < 0 ? 0 : (iv > 255 ? 255 : iv);
            };
            int a = ch(24);
            if (!a) continue;
            int dx = x0 + x, dy = y0 + y;
            if (dx < 0 || dy < 0 || dx >= g_dibW || dy >= g_dibH) continue;
            if (dx < clipL || dx >= clipR) continue;      // horizontal clip for the drag icon
            BYTE* dst = (BYTE*)g_bits + ((size_t)dy * g_dibW + dx) * 4;
            dst[0] = (BYTE)(ch(0) + dst[0] * (255 - a) / 255);
            dst[1] = (BYTE)(ch(8) + dst[1] * (255 - a) / 255);
            dst[2] = (BYTE)(ch(16) + dst[2] * (255 - a) / 255);
            dst[3] = (BYTE)(a + dst[3] * (255 - a) / 255);
        }
    }
}

// The grid *is* our system tray: only what the native tray shows. The strip is
// the taskbar, and apps that live there do not belong here a second time.
static int GridCellCount() { return (int)g_tray.size(); }

static void GridLayout() {
    int n = GridCellCount();
    g_gridCells.clear();
    if (n <= 0) {
        g_gridW = g_gridH = 0;
        return;
    }
    int cols = (int)ceil(sqrt((double)n));
    if (cols < 3) cols = 3;
    if (cols > 8) cols = 8;
    int rows = (n + cols - 1) / cols;
    g_gridW = kGridPad * 2 + cols * kGridCell + (cols - 1) * kGridGap;
    g_gridH = kGridPad * 2 + rows * kGridCell + (rows - 1) * kGridGap + kGridCapH;
    for (int i = 0; i < n; i++) {
        int r = i / cols, c = i % cols;
        int x = kGridPad + c * (kGridCell + kGridGap);
        int y = kGridPad + r * (kGridCell + kGridGap);
        Slot s;
        s.rc = {x, y, x + kGridCell, y + kGridCell};
        s.item = -2 - i;              // tray entry
        g_gridCells.push_back(s);
    }
}

static void GridEnsure() {
    if (g_gridBmp && g_gridAllocW == g_gridW && g_gridAllocH == g_gridH) return;
    if (g_gridDC) { DeleteDC(g_gridDC); g_gridDC = nullptr; }
    if (g_gridBmp) { DeleteObject(g_gridBmp); g_gridBmp = nullptr; }
    HDC screen = GetDC(nullptr);
    g_gridDC = CreateCompatibleDC(screen);
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = g_gridW;
    bi.bmiHeader.biHeight = -g_gridH;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    g_gridBmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &g_gridBits, nullptr, 0);
    ReleaseDC(nullptr, screen);
    if (g_gridBmp) SelectObject(g_gridDC, g_gridBmp);
    g_gridAllocW = g_gridW;
    g_gridAllocH = g_gridH;
}

static std::wstring GridCellLabel(int i) {
    if (i < 0 || i >= (int)g_gridCells.size()) return L"";
    int ti = -2 - g_gridCells[i].item;
    if (ti >= 0 && ti < (int)g_tray.size()) return g_tray[ti].tip;
    return L"";
}

static void GridPaint() {
    if (!g_gridWnd || g_gridW <= 0 || g_gridH <= 0 || !g_gridBits) return;
    // retarget the shared helpers at the grid's DIB
    void* savePaint = g_paintBits;
    int savePW = g_paintW, savePH = g_paintH;
    void* saveBits = g_bits;
    int saveDW = g_dibW, saveDH = g_dibH;
    g_paintBits = g_gridBits;
    g_paintW = g_gridW;
    g_paintH = g_gridH;
    g_bits = g_gridBits;
    g_dibW = g_gridW;
    g_dibH = g_gridH;

    memset(g_gridBits, 0, (size_t)g_gridW * g_gridH * 4);
    RECT all{0, 0, g_gridW, g_gridH};
    DWORD panel = g_cfg.lightMode ? 0xF2F2F3F5u : 0xF21A1B1Fu;
    FillRound(g_gridDC, all, 16, panel);
    // a hairline so the panel reads as a surface on bright wallpapers
    FillRound(g_gridDC, {0, 0, g_gridW, g_gridH}, 16,
              g_cfg.lightMode ? 0x18000000u : 0x1AFFFFFFu);

    for (int i = 0; i < (int)g_gridCells.size(); i++) {
        const Slot& s = g_gridCells[i];
        if (i == g_gridHover) FillRound(g_gridDC, s.rc, 12, 0x3DFFFFFFu);
        int cx = (s.rc.left + s.rc.right) / 2, cy = (s.rc.top + s.rc.bottom) / 2;
        const std::vector<uint32_t>* px = nullptr;
        int pxs = 0;
        if (s.item >= 0) {
            if (s.item < (int)g_items.size()) {
                const Item& it = g_items[s.item];
                if (!it.px.empty()) { px = &it.px; pxs = it.cachedPx; }
                else if (it.icon) {
                    DrawIconEx(g_gridDC, cx - kGridIcon / 2, cy - kGridIcon / 2, it.icon,
                               kGridIcon, kGridIcon, 0, nullptr, DI_NORMAL);
                }
            }
        } else {
            int ti = -2 - s.item;
            if (ti >= 0 && ti < (int)g_tray.size() && !g_tray[ti].px.empty()) {
                px = &g_tray[ti].px;
                pxs = g_tray[ti].cachedPx;
            }
        }
        if (px && pxs > 0)
            BlendScaled(cx - kGridIcon / 2, cy - kGridIcon / 2, kGridIcon, kGridIcon, px->data(),
                        pxs, pxs);
    }
    // Hover tooltip: the program / window name right above the hovered cell, so
    // tray icons and long window titles are identifiable without a caption bar.
    std::wstring label = GridCellLabel(g_gridHover);
    if (!label.empty() && g_gridHover >= 0 && g_gridHover < (int)g_gridCells.size()) {
        const RECT& cell = g_gridCells[g_gridHover].rc;
        const int kTipFont = 30;
        int tw = TextWidthPx(label, kTipFont) + 40;
        int maxW = g_gridW - 8;
        if (tw > maxW) tw = maxW;
        int th = 48;
        int x = (cell.left + cell.right) / 2 - tw / 2;
        if (x < 4) x = 4;
        if (x + tw > g_gridW - 4) x = g_gridW - 4 - tw;
        int y = cell.top - th - 8;
        if (y < 4) y = cell.bottom + 8;
        if (y + th > g_gridH - 4) y = g_gridH - 4 - th;
        if (y < 4) y = 4;
        RECT bub{x, y, x + tw, y + th};
        FillRound(g_gridDC, bub, 12, 0xF00C0D10u);
        DrawTextAlpha(x + 20, y, tw - 40, th, label, kTipFont, 0xF4FFFFFFu);
    }

    POINT src{0, 0};
    SIZE size{g_gridW, g_gridH};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(g_gridWnd, nullptr, nullptr, &size, g_gridDC, &src, 0, &bf, ULW_ALPHA);

    g_paintBits = savePaint;
    g_paintW = savePW;
    g_paintH = savePH;
    g_bits = saveBits;
    g_dibW = saveDW;
    g_dibH = saveDH;
}

// Bring the panel back into the topmost band after an app's menu has been shown above
// it (the menu needs to be able to cover the panel, so the panel is demoted for it).
static void MenuRestorePanel() {
    if (g_gridWnd)
        SetWindowPos(g_gridWnd, HWND_TOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

static void CloseMenuNow(const wchar_t* why);   // defined below, needs CloseMenuWindows()

static void GridHide(const wchar_t* why = L"unspecified") {
    DLog(L"grid: hide (from %s)", why);
    // Hide FIRST: CloseMenuNow() re-promotes the panel into the topmost band, and doing
    // that while the panel is still visible made it flash above the app's menu for a
    // frame before disappearing (user saw a blink, 2026-11-12).
    if (g_gridWnd && IsWindowVisible(g_gridWnd)) ShowWindow(g_gridWnd, SW_HIDE);
    if (g_menuOpen || g_menuWatch) CloseMenuNow(L"panel hidden");
    g_gridVisible = false;
    g_gridHover = -1;
    g_gridOutsideAt = 0;
    g_menuOpen = false;
    g_menuOutsideAt = 0;
    // the panel is gone: whatever app we had made "friendly" is no longer ours to keep
    g_friendPid = 0;
    g_fgAtGridOpen = nullptr;
    MenuRestorePanel();
}

// The app's own tray menu lives in a "#32768" popup owned by that app's thread.
static HWND TrayMenuWindow() {
    return FindWindowW(L"#32768", nullptr);
}

static int DistanceToRect(const RECT& r, POINT p) {
    int dx = 0, dy = 0;
    if (p.x < r.left) dx = r.left - p.x;
    else if (p.x > r.right) dx = p.x - r.right;
    if (p.y < r.top) dy = r.top - p.y;
    else if (p.y > r.bottom) dy = p.y - r.bottom;
    if (dx == 0 && dy == 0) return 0;
    return (int)sqrt((double)dx * dx + (double)dy * dy);
}

// Called from the 30 ms timer while a forwarded tray menu is open. The menu is
// "whatever new visible window that process put on screen after we posted the
// message": a classic #32768 menu for Win32 apps, a WPF/XAML popup for others.
static std::vector<unsigned long long> g_menuBaseline;

static void CollectPidWindows(unsigned int pid, std::vector<unsigned long long>& out) {
    out.clear();
    if (!pid) return;
    struct Ctx {
        unsigned int pid;
        std::vector<unsigned long long>* out;
    } ctx{pid, &out};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            auto* c = reinterpret_cast<Ctx*>(lp);
            DWORD wpid = 0;
            GetWindowThreadProcessId(h, &wpid);
            if (wpid != c->pid || !IsWindowVisible(h)) return TRUE;
            RECT r{};
            if (!GetWindowRect(h, &r)) return TRUE;
            if (r.right - r.left <= 0 || r.bottom - r.top <= 0) return TRUE;
            c->out->push_back((unsigned long long)(ULONG_PTR)h);
            return TRUE;
        },
        (LPARAM)&ctx);
}

// A tray menu is a borderless popup of the owning app, shown at the cursor. Most
// apps recycle that window (a WPF popup keeps one HWND for its whole life, Qt
// reuses one too), so "a window that did not exist before" misses them; a
// window that is simply *there, under the cursor, without a title bar* does not.
static bool MenuLikeWindow(HWND h, unsigned int pid, const POINT& p) {
    DWORD wp = 0;
    GetWindowThreadProcessId(h, &wp);
    if (wp != pid) return false;
    if (!IsWindowVisible(h)) return false;
    LONG style = GetWindowLongW(h, GWL_STYLE);
    if (!(style & WS_POPUP) || (style & WS_CAPTION)) return false;
    RECT r{};
    if (!GetWindowRect(h, &r)) return false;
    if (r.right - r.left < 40 || r.bottom - r.top < 20) return false;
    // inflate: menus are positioned *above* the cursor, so the cursor often sits on
    // the exact bottom edge, which PtInRect() excludes
    InflateRect(&r, 6, 6);
    return PtInRect(&r, p) != FALSE;
}

static void MenuWindows(std::vector<HWND>& out) {
    out.clear();
    if (!g_menuPid) return;
    std::vector<unsigned long long> now;
    CollectPidWindows(g_menuPid, now);
    for (auto h : now) {
        bool known = false;
        for (auto b : g_menuBaseline)
            if (b == h) { known = true; break; }
        if (!known) out.push_back((HWND)(ULONG_PTR)h);
    }
    POINT p{};
    if (!GetCursorPos(&p)) return;
    struct Ctx2 {
        unsigned int pid;
        const POINT* p;
        std::vector<HWND>* out;
    } ctx{g_menuPid, &p, &out};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            auto* c = reinterpret_cast<Ctx2*>(lp);
            if (!MenuLikeWindow(h, c->pid, *c->p)) return TRUE;
            for (HWND have : *c->out)
                if (have == h) return TRUE;
            c->out->push_back(h);
            return TRUE;
        },
        (LPARAM)&ctx);
}

static void CloseMenuWindows(const std::vector<HWND>& wins) {
    for (HWND h : wins) {
        PostMessageW(h, WM_CANCELMODE, 0, 0);
        PostMessageW(h, WM_KEYDOWN, VK_ESCAPE, 0);
        PostMessageW(h, WM_KEYUP, VK_ESCAPE, 0);
        // Electron / WPF / Qt tray panels are non-activating popups: they ignore
        // Esc but go away when blurred, which is what a click elsewhere does.
        PostMessageW(h, WM_ACTIVATE, WA_INACTIVE, 0);
        PostMessageW(h, WM_KILLFOCUS, 0, 0);
    }
    HWND classic = FindWindowW(L"#32768", nullptr);
    if (classic) {
        PostMessageW(classic, WM_KEYDOWN, VK_ESCAPE, 0);
        PostMessageW(classic, WM_KEYUP, VK_ESCAPE, 0);
    }
}

// True when the window is actually *drawn* somewhere: IsWindowVisible lies for the
// reused popups tray apps keep around (they stay WS_VISIBLE while hidden behind
// everything), so probe a few points with WindowFromPoint instead.
static bool WindowOnScreen(HWND h) {
    RECT r{};
    if (!h || !GetWindowRect(h, &r)) return false;
    int w = r.right - r.left, ht = r.bottom - r.top;
    if (w <= 0 || ht <= 0) return false;
    struct Ctx {
        HWND h;
        RECT r;
        int hits;
    } ctx{h, r, 0};
    const double fx[3] = {0.25, 0.5, 0.75};
    const double fy[3] = {0.2, 0.5, 0.8};
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            POINT p{ctx.r.left + (int)(w * fx[i]), ctx.r.top + (int)(ht * fy[j])};
            HWND hit = WindowFromPoint(p);
            if (!hit) continue;
            if (hit == ctx.h || GetAncestor(hit, GA_ROOT) == ctx.h) ctx.hits++;
        }
    }
    return ctx.hits >= 2;
}

// A tray menu is positioned by the app relative to the cursor, and some of them are
// tall (QQ's is ~620px), so a menu opened from a panel near an edge can hang off the
// screen. The pointer must NOT be moved to fix that (the user sees it jump), so the
// menu window itself is shifted into the work area instead. Moving a popup does not
// affect its own hit testing: the app still resolves clicks against its client area.
static bool g_menuAdjusted = false;
static POINT g_menuCursorPt{};     // where the pointer really was when we forwarded the click

static void FitMenuToWorkArea(HWND menu) {
    if (!menu) return;
    RECT mr{};
    if (!GetWindowRect(menu, &mr)) return;
    HMONITOR mon = MonitorFromWindow(menu, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{sizeof(mi)};
    if (!GetMonitorInfoW(mon, &mi)) return;
    RECT wa = mi.rcWork;
    InflateRect(&wa, -8, -8);      // keep a visible margin instead of touching the edge
    int w = mr.right - mr.left, h = mr.bottom - mr.top;
    int nx = mr.left, ny = mr.top;
    // Only clamp along an axis the menu can actually fit into; a menu taller than the
    // work area is left where the app put it.
    if (w <= wa.right - wa.left) {
        if (nx + w > wa.right) nx = wa.right - w;
        if (nx < wa.left) nx = wa.left;
    }
    if (h <= wa.bottom - wa.top) {
        if (ny + h > wa.bottom) ny = wa.bottom - h;
        if (ny < wa.top) ny = wa.top;
    }
    if (nx == mr.left && ny == mr.top) return;      // already fully on screen
    BOOL ok = SetWindowPos(menu, HWND_TOP, nx, ny, 0, 0,
                           SWP_NOSIZE | SWP_NOSENDCHANGING | SWP_NOACTIVATE);
    DWORD err = ok ? 0 : GetLastError();
    RECT nr{};
    GetWindowRect(menu, &nr);
    DLog(L"tray: menu %ldx%ld at %ld,%ld is off screen -> moved the menu itself to "
         L"%ld,%ld (ok=%d err=%lu, now %ld,%ld)",
         (long)w, (long)h, (long)mr.left, (long)mr.top, (long)nx, (long)ny, (int)ok,
         (unsigned long)err, (long)nr.left, (long)nr.top);
}

// While a forwarded menu exists we keep watching it even after the panel is gone,
// so that a click outside it dismisses it the way the real tray does.
// A real click has a press duration; posting DOWN and UP back to back can be seen as
// a zero-length click and ignored. The UP is therefore posted a few ticks later.
// Some apps ignore the first forwarded click (measured: a real mouse click on the
// deepseek harness icon produced no menu, while the identical posted pair did). One
// automatic retry, ~250 ms later, and only when no menu showed up at all.
static bool g_menuRetried = false;
static HWND g_retryWnd = nullptr;
static unsigned g_retryMsg = 0;
static unsigned g_retryUid = 0;
static DWORD g_retryAt = 0;

static HWND g_upPendingWnd = nullptr;
static unsigned g_upPendingMsg = 0;
static unsigned g_upPendingUid = 0;
static DWORD g_upPendingAt = 0;
static UINT g_upPendingButton = WM_RBUTTONUP;   // which UP the sequence ends with
// The click is posted as a short *sequence* instead of one pair, because every app picks a
// different part of it:
//   single click only        -> reacts to WM_LBUTTONUP
//   "needs a double click"   -> reacts to WM_LBUTTONDBLCLK (WinForms' NotifyIcon.DoubleClick
//                               and friends); posted messages never produce one by themselves
// A real double click is DOWN, UP, DBLCLK, UP - that is what we post now, and both kinds of
// app react to it (measured: WorkBuddy Manager only opens on DBLCLK, Lenovo PC Manager opens
// on either). [tray] doubleClick= picks how long the sequence is.
static UINT g_postQueue[4] = {};
static int g_postLen = 0;
static int g_postPos = 0;

// ---- auto double click: did the app react to the click we just forwarded? -----------
// Only used when [tray] autoDoubleClick=1. "Reacted" = the foreground moved, or the app
// put another visible, non-minimised top-level window on screen. Both are cheap to check
// and they are what the double-click-only apps do when the second click lands.
static DWORD g_trayDblAt = 0;          // when to look (0 = not watching)
static DWORD g_trayDblPid = 0;
static HWND g_trayDblFg = nullptr;
static int g_trayDblWindows = 0;       // visible non-minimised top-level windows before
static HWND g_trayDblWnd = nullptr;    // where the extra pair goes
static unsigned g_trayDblMsg = 0;
static unsigned g_trayDblUid = 0;

static int CountAppWindows(DWORD pid) {
    struct Ctx {
        DWORD pid;
        int n;
    } ctx{pid, 0};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            auto* c = (Ctx*)lp;
            DWORD p = 0;
            GetWindowThreadProcessId(h, &p);
            if (p == c->pid && IsWindowVisible(h) && !IsIconic(h)) c->n++;
            return TRUE;
        },
        (LPARAM)&ctx);
    return ctx.n;
}

// Is this app sent two click pairs? Exceptions win, then "*" (all), then the name list.
static bool TrayWantsDoubleClick(const TrayEntry& e) {
    if (e.exe.empty()) return false;
    std::wstring base = e.exe;
    const size_t sl = base.find_last_of(L'\\');
    if (sl != std::wstring::npos) base = base.substr(sl + 1);
    auto matches = [&](const std::wstring& t) { return t == e.exe || t == base; };
    for (const auto& t : g_trayDoubleClickExcept) {
        if (matches(t)) return false;
    }
    if (g_trayDoubleClickAll) return true;
    for (const auto& t : g_trayDoubleClick) {
        if (matches(t)) return true;
    }
    return false;
}

// Post the next message of the queued sequence (see g_postQueue above). One message per
// ~70 ms tick, so the app sees a real press duration and a real double-click spacing.
static void FlushPendingUp(DWORD now) {
    if (!g_upPendingWnd || (LONG)(now - g_upPendingAt) < 0) return;
    const UINT msg = g_postQueue[g_postPos++];
    if (IsWindow(g_upPendingWnd))
        PostMessageW(g_upPendingWnd, g_upPendingMsg, (WPARAM)g_upPendingUid, msg);
    const wchar_t* name = msg == WM_LBUTTONDOWN   ? L"left down"
                          : msg == WM_LBUTTONUP   ? L"left up"
                          : msg == WM_LBUTTONDBLCLK ? L"left double-click"
                          : msg == WM_RBUTTONDOWN ? L"right down"
                                                  : L"right up";
    DLog(L"tray: %s -> %p (step %d/%d)", name, (void*)g_upPendingWnd, g_postPos, g_postLen);
    if (g_postPos < g_postLen) {
        g_upPendingAt = now + 70;
    } else {
        g_upPendingWnd = nullptr;
        g_postLen = g_postPos = 0;
    }
}

// Runs from the same 30 ms watch as FlushPendingUp: ~400 ms after the click, if the app
// showed no sign of having done anything, send the double-click sequence once more.
static void TrayAutoDoubleTick(DWORD now) {
    if (!g_trayDblAt || (LONG)(now - g_trayDblAt) < 0) return;
    g_trayDblAt = 0;
    const bool foregroundMoved = GetForegroundWindow() != g_trayDblFg;
    const int windowsNow = CountAppWindows(g_trayDblPid);
    if (foregroundMoved || windowsNow > g_trayDblWindows) {
        DLog(L"tray: auto double click not needed (fg moved=%d, windows %d -> %d)",
             (int)foregroundMoved, g_trayDblWindows, windowsNow);
        return;
    }
    DLog(L"tray: auto double click - no reaction, sending the double click sequence again");
    if (g_trayDblWnd && IsWindow(g_trayDblWnd)) {
        PostMessageW(g_trayDblWnd, g_trayDblMsg, (WPARAM)g_trayDblUid, WM_LBUTTONDOWN);
        g_upPendingWnd = g_trayDblWnd;
        g_upPendingMsg = g_trayDblMsg;
        g_upPendingUid = g_trayDblUid;
        g_upPendingButton = WM_LBUTTONUP;
        g_postQueue[0] = WM_LBUTTONUP;
        g_postQueue[1] = WM_LBUTTONDBLCLK;
        g_postQueue[2] = WM_LBUTTONUP;
        g_postLen = 3;
        g_postPos = 0;
        g_upPendingAt = now + 70;
    }
}

// Forward a click on a tray icon to the app that owns the icon - the same thing the
// shell does for a real tray click. We do NOT guess what the click should mean: the app
// decides (QQ opens that account's chat window, WorkBuddy brings up its main window...).
// Measured 2026-11-12: guessing with "activate some window of that exe, else launch it"
// opened QQ's *login* window and did nothing at all for WorkBuddy.
// A zero-length click is ignored by some apps (see HANDOVER pit 15), so the UP is
// posted ~70 ms later from the 30 ms timer instead of back to back.
static bool ForwardTrayClick(const TrayEntry& e, UINT downMsg, UINT upMsg, const wchar_t* what) {
    HWND owner = (HWND)(ULONG_PTR)e.ownerHwnd;
    if (!owner || !IsWindow(owner) || !e.callbackMsg) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(owner, &pid);
    // we are acting for this app: its window may take the foreground without the panel
    // reading it as "a third party stole the focus"
    g_friendPid = pid;
    g_focusGraceUntil = GetTickCount() + 1500;
    // the shell owns the foreground when a real tray icon is clicked; hand the same
    // permission to the app so its SetForegroundWindow is not refused
    AllowSetForegroundWindow(ASFW_ANY);
    wchar_t cls[64]{};
    GetClassNameW(owner, cls, 64);
    // Two shapes are possible (see g_postQueue): a plain click (DOWN/UP) for right clicks and
    // for apps listed as exceptions, and the double-click sequence (DOWN/UP/DBLCLK/UP) for
    // everything else. The DBLCLK step is what "needs a double click" apps actually watch for.
    const bool twice = TrayWantsDoubleClick(e) && downMsg == WM_LBUTTONDOWN;
    if (!twice && g_trayAutoDoubleClick && downMsg == WM_LBUTTONDOWN) {
        // remember what "nothing happened" looks like, for one look ~400 ms later
        g_trayDblAt = GetTickCount() + 400;
        g_trayDblPid = pid;
        g_trayDblFg = GetForegroundWindow();
        g_trayDblWindows = CountAppWindows(pid);
        g_trayDblWnd = owner;
        g_trayDblMsg = e.callbackMsg;
        g_trayDblUid = e.ownerUid;
    }
    BOOL okDown = PostMessageW(owner, e.callbackMsg, (WPARAM)e.ownerUid, downMsg);
    DWORD err = okDown ? 0 : GetLastError();
    g_upPendingWnd = owner;
    g_upPendingMsg = e.callbackMsg;
    g_upPendingUid = e.ownerUid;
    g_upPendingButton = upMsg;
    g_postPos = 0;
    if (twice) {
        g_postQueue[0] = WM_LBUTTONUP;
        g_postQueue[1] = WM_LBUTTONDBLCLK;
        g_postQueue[2] = WM_LBUTTONUP;
        g_postLen = 3;
    } else {
        g_postQueue[0] = upMsg;
        g_postLen = 1;
    }
    g_upPendingAt = GetTickCount() + 70;
    DLog(L"tray: %s click -> %p msg=0x%X uid=%u '%s' (%s) cls=%s post=%d err=%lu",
         twice ? L"left x2" : what, (void*)owner, e.callbackMsg, e.ownerUid, e.tip.c_str(),
         e.exe.c_str(), cls, (int)okDown, (unsigned long)err);
    if (twice)
        DLog(L"tray: '%s' gets the double click sequence (down/up/dblclk/up)", e.tip.c_str());
    return okDown != FALSE;
}

static int g_menuCloseTries = 0;

static void MenuWatchClear() {
    g_menuWatch = nullptr;
    g_menuCloseTries = 0;
}

// Close the app's menu because *we* decided the interaction is over (click outside,
// panel hidden, focus lost). CloseMenuWindows() is best effort: elevated apps ignore
// it, and that is fine - the menu is theirs, not ours.
static void CloseMenuNow(const wchar_t* why) {
    std::vector<HWND> one;
    HWND m = g_menuWatch ? g_menuWatch : g_menuHwnd;
    if (m && IsWindow(m)) one.push_back(m);
    if (!one.empty()) {
        CloseMenuWindows(one);
        DLog(L"tray: closing the app menu %p (%s)", (void*)m, why);
    }
    if (g_menuPid) {
        // the app is about to act on the user's behalf; let its window take the
        // foreground without that being read as "focus went to a third party"
        g_friendPid = g_menuPid;
        g_focusGraceUntil = GetTickCount() + 300;
    }
    g_menuOpen = false;
    g_menuSeen = false;
    g_menuHwnd = nullptr;
    g_menuItemPressAt = 0;
    MenuWatchClear();
    MenuRestorePanel();
}

// Is this one of our own windows (or a child of one)? Clicks on those are handled by
// the window procs, not by the "click outside" rules below.
static bool IsOwnWindow(HWND h) {
    if (!h) return false;
    HWND root = GetAncestor(h, GA_ROOT);
    if (!root) root = h;
    return root == g_hwnd || root == g_gridWnd || root == g_thumbWnd || root == g_setWnd;
}

// Is this the app's menu we are currently watching (or a child of it)?
static bool IsMenuWindow(HWND h) {
    if (!h || !g_menuOpen) return false;
    HWND root = GetAncestor(h, GA_ROOT);
    if (!root) root = h;
    return (g_menuWatch && root == g_menuWatch) || (g_menuHwnd && root == g_menuHwnd);
}

// Every press the user makes is classified here:
//   * on one of our windows      -> the window procs decide (icon click, chevron, menu)
//   * on the app's menu          -> the app decides (we never touch it)
//   * anywhere else              -> "click outside": drop the menu, drop the panel
// The strip then falls back to its distance-based fade (state 1).
// GetAsyncKeyState's low bit is "pressed since the last call", and the synthetic
// messages we post never touch it, so this only reacts to the real user.
// A press is reported by BOTH a low-level mouse hook and the GetAsyncKeyState poll.
// The poll alone turned out to be unreliable: a press that happens right after an
// app's own menu closed (Electron / WinForms context menus release their capture
// late) was sometimes never seen, and then the panel only went away a second later
// when the foreground changed - the "blink, then it stays for a second" the user
// reported. The hook sees every press no matter who holds capture.
struct PendingPress {
    bool valid;
    bool right;
    POINT pt;
    DWORD at;
};
static PendingPress g_pendingPress{};
static HHOOK g_mouseHook = nullptr;

static LRESULT CALLBACK LowLevelMouseProc(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION && (wp == WM_LBUTTONDOWN || wp == WM_RBUTTONDOWN)) {
        auto* m = reinterpret_cast<MSLLHOOKSTRUCT*>(lp);
        g_pendingPress.valid = true;
        g_pendingPress.right = (wp == WM_RBUTTONDOWN);
        g_pendingPress.pt = m->pt;
        g_pendingPress.at = GetTickCount();
    }
    return CallNextHookEx(g_mouseHook, code, wp, lp);
}

static void PressWatchTick() {
    static DWORD lastBeat = 0;
    bool l = false, r = false;
    POINT hookPt{};
    bool fromHook = false;
    if (g_pendingPress.valid) {
        fromHook = true;
        l = !g_pendingPress.right;
        r = g_pendingPress.right;
        hookPt = g_pendingPress.pt;
        g_pendingPress.valid = false;
    }
    // the poll stays as a safety net (e.g. if the hook could not be installed)
    if (!fromHook) {
        l = (GetAsyncKeyState(VK_LBUTTON) & 0x0001) != 0;
        r = (GetAsyncKeyState(VK_RBUTTON) & 0x0001) != 0;
    } else {
        GetAsyncKeyState(VK_LBUTTON);
        GetAsyncKeyState(VK_RBUTTON);
    }
    if (g_gridVisible || g_menuOpen) {          // heartbeat: is the poll even alive?
        DWORD now = GetTickCount();
        if (now - lastBeat > 1000) {
            lastBeat = now;
            // Diagnostic for "the panel vanished but we never hid it": is something
            // foreign painted over its centre? (a z-order problem, not a hide)
            if (g_gridWnd && IsWindowVisible(g_gridWnd)) {
                RECT r{};
                if (GetWindowRect(g_gridWnd, &r)) {
                    POINT c{(r.left + r.right) / 2, (r.top + r.bottom) / 2};
                    HWND under2 = WindowFromPoint(c);
                    if (under2 && !IsOwnWindow(under2)) {
                        wchar_t uc[64]{};
                        GetClassNameW(under2, uc, 64);
                        DWORD upid = 0;
                        GetWindowThreadProcessId(under2, &upid);
                        DLog(L"grid visible but covered at its centre by %p pid=%lu cls=%s "
                             L"(menuPid=%lu friendPid=%lu)",
                             (void*)under2, (unsigned long)upid, uc, (unsigned long)g_menuPid,
                             (unsigned long)g_friendPid);
                    }
                }
            }
        }
    }
    if (!l && !r) return;
    if (!g_gridVisible && !g_menuOpen) return;      // nothing to dismiss
    POINT p{};
    if (fromHook) p = hookPt;
    else if (!GetCursorPos(&p)) return;
    HWND under = WindowFromPoint(p);
    wchar_t cls[64]{};
    GetClassNameW(under, cls, 64);
    if (IsOwnWindow(under)) {
        DLog(L"press: %s on our window %p cls=%s - the window proc decides",
             r ? L"right" : L"left", (void*)under, cls);
        return;
    }
    if (IsMenuWindow(under)) {
        if (l) g_menuItemPressAt = GetTickCount();   // 3b-iv: an item is being picked
        DLog(L"press: %s on the app menu %p cls=%s - the app decides",
             r ? L"right" : L"left", (void*)under, cls);
        return;
    }
    if (IsOverflowFlyoutWindow(under)) {
        // the shell's own tray flyout, which we merely moved: it handles its own clicks
        DLog(L"press: %s on the native tray flyout %p - the shell decides",
             r ? L"right" : L"left", (void*)under);
        return;
    }
    DLog(L"%s click outside the panel+menu at %ld,%ld over %p cls=%s",
         r ? L"right" : L"left", (long)p.x, (long)p.y, (void*)under, cls);
    if (g_menuOpen) CloseMenuNow(L"click outside");
    if (g_gridVisible) GridHide(L"click outside");
    NativeTrayPark();
}

// Focus loss: the panel never holds focus itself, so "we lost it" means the foreground
// became a window that is neither ours, nor what had focus when the panel opened, nor
// an app we just acted for. Only clicks and focus changes end the panel - never the
// pointer wandering around.
static void FocusWatchTick() {
    if (!g_gridVisible && !g_menuOpen) return;
    HWND fg = GetForegroundWindow();
    if (!fg || !IsWindow(fg)) return;          // no foreground at all: do not flap
    if (IsOwnWindow(fg)) return;
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (pid && pid == GetCurrentProcessId()) return;
    if (g_menuOpen && pid && pid == g_menuPid) return;
    if (g_friendPid && pid == g_friendPid) return;
    // Same *process* as when the panel opened counts as friendly: an app that shows its
    // tray menu moves the focus to another one of its own windows (Electron does), and
    // comparing window handles treated that as "a third party stole the focus".
    if (g_fgAtGridOpen && fg == g_fgAtGridOpen) return;
    if (g_fgPidAtGridOpen && pid == g_fgPidAtGridOpen) return;
    if ((LONG)(GetTickCount() - g_focusGraceUntil) < 0) return;
    wchar_t title[96]{};
    GetWindowTextW(fg, title, 96);
    DLog(L"focus left us: foreground is %p pid=%lu '%s' -> closing panel", (void*)fg,
         (unsigned long)pid, title);
    if (g_menuOpen) CloseMenuNow(L"focus lost");
    GridHide(L"focus lost");
}

// The panel must stay in the topmost band, otherwise *any* window that gets activated
// (the app itself, when its tray menu makes it foreground) is raised above it and the
// panel simply gets covered - which looks exactly like "the grid disappeared", with no
// hide in the log. So instead of demoting the panel, lift the app's menu into the
// topmost band (it is a menu: it is supposed to float). Windows we cannot touch
// (elevated apps) fall back to demoting the panel.
static bool RaiseMenuAbovePanel(HWND menu) {
    RECT mr{};
    if (!GetWindowRect(menu, &mr)) return false;
    int w = mr.right - mr.left, h = mr.bottom - mr.top;
    HMONITOR mon = MonitorFromWindow(menu, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{sizeof(mi)};
    if (!GetMonitorInfoW(mon, &mi)) return false;
    int sw = mi.rcMonitor.right - mi.rcMonitor.left;
    int sh = mi.rcMonitor.bottom - mi.rcMonitor.top;
    if (w * 4 > sw * 3 || h * 4 > sh * 3) return false;   // too big to be a menu
    BOOL ok = SetWindowPos(menu, HWND_TOPMOST, 0, 0, 0, 0,
                           SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    DLog(L"tray: lifting menu %p %ldx%ld above the panel: ok=%d err=%lu", (void*)menu, (long)w,
         (long)h, (int)ok, (unsigned long)(ok ? 0 : GetLastError()));
    return ok != FALSE;
}

static void TrayMenuTick() {
    if (!g_menuOpen) return;
    std::vector<HWND> menus;
    // Once a menu window is known, follow that window. Re-deriving "the menu" every
    // tick is wrong: the cursor-predicate stops matching as soon as the user moves
    // onto the menu, and "no menu" would then hide the panel while the app's menu
    // is still on screen.
    if (g_menuHwnd && IsWindow(g_menuHwnd) && IsWindowVisible(g_menuHwnd)) {
        menus.push_back(g_menuHwnd);
    } else {
        g_menuHwnd = nullptr;
        MenuWindows(menus);
        if (!menus.empty()) g_menuHwnd = menus[0];
        if (g_menuHwnd && g_menuWatch != g_menuHwnd) {
            g_menuWatch = g_menuHwnd;
            DLog(L"tray: watching menu window %p for clicks outside it", (void*)g_menuWatch);
        }
    }
    if (menus.empty()) {
        if (!g_menuSeen && !g_menuRetried && g_retryWnd && (LONG)(GetTickCount() - g_retryAt) >= 0) {
            g_menuRetried = true;
            DLog(L"tray: no menu yet after %lu ms - forwarding the click once more",
                 (unsigned long)(GetTickCount() - g_menuOpenedAt));
            PostMessageW(g_retryWnd, g_retryMsg, (WPARAM)g_retryUid, WM_RBUTTONDOWN);
            g_upPendingWnd = g_retryWnd;
            g_upPendingMsg = g_retryMsg;
            g_upPendingUid = g_retryUid;
            g_upPendingButton = WM_RBUTTONUP;
            g_postQueue[0] = WM_RBUTTONUP;
            g_postLen = 1;
            g_postPos = 0;
            g_upPendingAt = GetTickCount() + 70;
            return;
        }
        if (!g_menuSeen && GetTickCount() - g_menuOpenedAt < 1500) return;   // still coming
        if (g_menuSeen) {
            // The app closed its own menu. Two very different reasons:
            //  * the user picked an item (we saw the press land on the menu): the
            //    interaction is over - panel goes too, strip falls back to distance (3b-iv)
            //  * the app dropped it by itself (mouse leave, timer, app died): the panel
            //    stays, because only a click outside / focus loss may end it (3a)
            DWORD now = GetTickCount();
            bool picked = g_menuItemPressAt && (now - g_menuItemPressAt) < 2000;
            g_menuItemPressAt = 0;
            g_menuOpen = false;
            g_menuSeen = false;
            g_menuHwnd = nullptr;
            g_menuWatch = nullptr;
            g_menuCloseTries = 0;
            if (picked) {
                DLog(L"tray: app menu is gone after a click on it - closing the panel");
                GridHide(L"menu item picked");
            } else {
                DLog(L"tray: app menu is gone - panel stays");
                // the app just acted for the user (opened a window, toggled a setting):
                // let its own window take the foreground without being read as "focus loss"
                if (g_menuPid) {
                    g_friendPid = g_menuPid;
                    g_focusGraceUntil = now + 1200;
                }
                MenuRestorePanel();
            }
        } else {
            DLog(L"tray: no menu appeared for pid %u", g_menuPid);
            // Diagnostics: what did that process put on screen at all? (class, rect,
            // topmost flag) plus what sits under the cursor. Saves a round trip when
            // an app shows its menu in a shape we do not recognise.
            {
                struct Ctx {
                    DWORD pid;
                } ctx{g_menuPid};
                EnumWindows(
                    [](HWND h, LPARAM lp) -> BOOL {
                        auto* c = reinterpret_cast<Ctx*>(lp);
                        DWORD wp = 0;
                        GetWindowThreadProcessId(h, &wp);
                        if (wp != c->pid || !IsWindowVisible(h)) return TRUE;
                        RECT r{};
                        GetWindowRect(h, &r);
                        wchar_t cls[64]{};
                        GetClassNameW(h, cls, 64);
                        LONG ex = GetWindowLongW(h, GWL_EXSTYLE);
                        DLog(L"tray:   win %p cls=%s rect=%ld,%ld-%ld,%ld topmost=%d",
                             (void*)h, cls, (long)r.left, (long)r.top, (long)r.right,
                             (long)r.bottom, (ex & WS_EX_TOPMOST) ? 1 : 0);
                        return TRUE;
                    },
                    (LPARAM)&ctx);
                POINT cp{};
                if (GetCursorPos(&cp)) {
                    HWND under = WindowFromPoint(cp);
                    wchar_t cls[64]{};
                    if (under) GetClassNameW(under, cls, 64);
                    LONG ex = under ? GetWindowLongW(under, GWL_EXSTYLE) : 0;
                    DLog(L"tray:   cursor %ld,%ld over %p cls=%s topmost=%d", (long)cp.x,
                         (long)cp.y, (void*)under, cls, (ex & WS_EX_TOPMOST) ? 1 : 0);
                }
                RECT gr{};
                if (g_gridWnd && GetWindowRect(g_gridWnd, &gr)) {
                    LONG ex = GetWindowLongW(g_gridWnd, GWL_EXSTYLE);
                    DLog(L"tray:   panel %p rect=%ld,%ld-%ld,%ld topmost=%d", (void*)g_gridWnd,
                         (long)gr.left, (long)gr.top, (long)gr.right, (long)gr.bottom,
                         (ex & WS_EX_TOPMOST) ? 1 : 0);
                }
            }
            g_menuOpen = false;
            if (g_gridWnd)
                SetWindowPos(g_gridWnd, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        return;
    }
    g_menuSeen = true;
    if (!g_menuAdjusted && g_menuHwnd) {
        g_menuAdjusted = true;
        // The pointer stays exactly where the user left it; if the app's menu hangs
        // off the screen we shift the menu window (see FitMenuToWorkArea).
        RECT mr{};
        GetWindowRect(g_menuHwnd, &mr);
        DLog(L"tray: menu %p appeared at %ld,%ld (%ldx%ld), pointer untouched at %ld,%ld",
             (void*)g_menuHwnd, (long)mr.left, (long)mr.top, (long)(mr.right - mr.left),
             (long)(mr.bottom - mr.top), (long)g_menuCursorPt.x, (long)g_menuCursorPt.y);
        if (!RaiseMenuAbovePanel(g_menuHwnd) && g_gridWnd) {
            // cannot lift the app's menu (elevated app): give the panel up instead, so
            // the menu is not painted behind it
            DLog(L"tray: could not lift the menu - demoting the panel instead");
            SetWindowPos(g_gridWnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        FitMenuToWorkArea(g_menuHwnd);
    }
    if (GetTickCount() - g_menuOpenedAt > 180000) {
        CloseMenuWindows(menus);
        GridHide(L"menu timeout");
        return;
    }
    // No cursor-distance rule here any more: while a menu exists the strip, the panel
    // and the menu all stay put (real tray behaviour, and what the user asked for).
    // Dismissal is click/focus driven - see PressWatchTick() / FocusWatchTick().
}

// Where the panel goes. It belongs next to the "^" button (that is where the eye and the
// pointer already are), not next to the middle of the strip.
//   * hard rule   - the whole panel stays inside the monitor work area
//   * best effort - it does not overlap the strip: it goes to whichever short side has
//     room, and when both have room the default is right (vertical strip) / below
//     (horizontal strip)
// A strip that is bigger than the free space wins over the overlap rule, never over the
// screen rule.
// Everything the placement needs, taken once on the window thread: the worker that opens the
// flyout must not read g_slots (the strip may rearrange under it).
struct PanelCtx {
    RECT strip;
    RECT chev;
};

static RECT ChevronRect(const RECT& dr) {
    RECT chev = dr;
    POINT org{0, 0};
    ClientToScreen(g_hwnd, &org);
    for (const Slot& s : g_slots) {
        if (s.item == kSlotChevron) {
            chev = RECT{org.x + s.rc.left, org.y + s.rc.top, org.x + s.rc.right,
                        org.y + s.rc.bottom};
            break;
        }
    }
    return chev;
}

static void PanelPlacementIn(const PanelCtx& ctx, int w, int h, int* outX, int* outY) {
    const RECT dr = ctx.strip;
    const RECT chev = ctx.chev;
    RECT wa{};
    MONITORINFO mi{sizeof(mi)};
    HMONITOR mon = MonitorFromWindow(g_hwnd, MONITOR_DEFAULTTONEAREST);
    if (mon && GetMonitorInfoW(mon, &mi)) {
        wa = mi.rcWork;
    } else {
        wa = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
    }

    const int gap = 8;
    bool vertical = (dr.bottom - dr.top) > (dr.right - dr.left);
    int x = 0, y = 0;
    if (vertical) {
        int right = dr.right + gap;
        int left = dr.left - gap - w;
        bool fitsRight = right + w <= wa.right;
        bool fitsLeft = left >= wa.left;
        if (fitsRight) x = right;
        else if (fitsLeft) x = left;
        else x = (wa.right - dr.right >= dr.left - wa.left) ? right : left;
        y = chev.bottom - h;             // grow upwards from the button
    } else {
        int below = dr.bottom + gap;
        int above = dr.top - gap - h;
        bool fitsBelow = below + h <= wa.bottom;
        bool fitsAbove = above >= wa.top;
        if (fitsBelow) y = below;
        else if (fitsAbove) y = above;
        else y = (wa.bottom - dr.bottom >= dr.top - wa.top) ? below : above;
        x = chev.right - w;              // end at the button's outer edge
    }

    // hard rule: never hang over the work area
    if (x + w > wa.right) x = wa.right - w;
    if (y + h > wa.bottom) y = wa.bottom - h;
    if (x < wa.left) x = wa.left;
    if (y < wa.top) y = wa.top;
    *outX = x;
    *outY = y;
    DLog(L"panel: place strip=%ld,%ld-%ld,%ld chevron=%ld,%ld-%ld,%ld -> %d,%d (%dx%d) "
         L"work=%ld,%ld-%ld,%ld",
         dr.left, dr.top, dr.right, dr.bottom, chev.left, chev.top, chev.right, chev.bottom, x,
         y, w, h, wa.left, wa.top, wa.right, wa.bottom);
}

static void PanelPlacement(const RECT& dr, int w, int h, int* outX, int* outY) {
    PanelCtx ctx{dr, ChevronRect(dr)};
    PanelPlacementIn(ctx, w, h, outX, outY);
}

static void GridPlacement(const RECT& dr, int* outX, int* outY) {
    PanelPlacement(dr, g_gridW, g_gridH, outX, outY);
}

static void GridShow() {
    if (!g_gridWnd) {
        WNDCLASSEXW wc{sizeof(wc)};
        wc.lpfnWndProc = GridProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = L"DockGridWindow";
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        RegisterClassExW(&wc);
        g_gridWnd = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED, L"DockGridWindow",
            L"", WS_POPUP, 0, 0, 10, 10, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    }
    if (!g_gridWnd) return;
    if (g_gridVisible) { GridHide(L"toggle"); return; }
    BuildTray();
    GridLayout();
    if (GridCellCount() <= 0) { DLog(L"grid: nothing to show"); return; }
    GridEnsure();
    if (!g_gridBits) return;

    RECT dr{};
    GetWindowRect(g_hwnd, &dr);
    int x = 0, y = 0;
    GridPlacement(dr, &x, &y);
    SetWindowPos(g_gridWnd, HWND_TOPMOST, x, y, g_gridW, g_gridH,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    g_gridVisible = true;
    g_gridHover = -1;
    g_gridOutsideAt = 0;
    // Remember who had the focus when the panel appeared: that window is allowed to
    // keep it. Only a *different* owner later on counts as "focus went elsewhere".
    g_fgAtGridOpen = GetForegroundWindow();
    g_fgPidAtGridOpen = 0;
    if (g_fgAtGridOpen) GetWindowThreadProcessId(g_fgAtGridOpen, &g_fgPidAtGridOpen);
    {   // diagnostics: who had the focus, and did the panel get raised at all
        wchar_t t[96]{};
        if (g_fgAtGridOpen) GetWindowTextW(g_fgAtGridOpen, t, 96);
        DLog(L"grid: focus at open = %p pid=%lu '%s'", (void*)g_fgAtGridOpen,
             (unsigned long)g_fgPidAtGridOpen, t);
    }
    g_friendPid = 0;
    g_focusGraceUntil = GetTickCount() + 300;
    GridPaint();
    DLog(L"grid: %dx%d at %d,%d, %d dock + %d tray", g_gridW, g_gridH, x, y, (int)g_items.size(),
         (int)g_tray.size());
}

// ---------------------------------------------------------------- native tray flyout
// [tray] native=1 (default): the "^" slot opens the *shell's own* overflow flyout (the
// "hidden icons" popup) and we only move it under the button. Whatever the user does next
// - double click, right-click menu, an app that hooks the mouse - is the shell's business,
// so nothing has to be emulated. Measured 2026-11-16: Windhawk (which ignores every posted
// message) opens fine from the moved flyout, because the click is a real one.
//
// The flyout has to be opened by clicking the taskbar's own "^", and taskbar-hidden-until-win
// only lets the taskbar onto the screen for a Win press - that is the flash the user accepted.
// Once it is up, the flyout is an independent top level window: hiding the taskbar again
// leaves it where we put it.

static HWND FindOverflowFlyout() {
    HWND found = nullptr;
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            wchar_t cls[64]{};
            if (!GetClassNameW(h, cls, 64)) return TRUE;
            if (_wcsicmp(cls, L"TopLevelWindowForOverflowXamlIsland") != 0) return TRUE;
            *(HWND*)lp = h;
            return FALSE;
        },
        (LPARAM)&found);
    return found;
}

// The "show hidden icons" chevron sits at the left edge of the notification area.
static bool TrayChevronPoint(POINT* out) {
    HWND tray = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!tray) return false;
    HWND notify = FindWindowExW(tray, nullptr, L"TrayNotifyWnd", nullptr);
    if (!notify) return false;
    RECT r{};
    if (!GetWindowRect(notify, &r)) return false;
    if (r.right <= r.left) return false;
    out->x = r.left + 13;
    out->y = (r.top + r.bottom) / 2;
    return true;
}

static void ClickScreenPoint(int x, int y) {
    SetCursorPos(x, y);
    Sleep(40);
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    Sleep(60);
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
}

// Is the shell's flyout on screen right now (a parked one does not count)?
static bool OverflowFlyoutOnScreen() {
    if (!g_trayNative) return false;
    HWND f = FindOverflowFlyout();
    if (!f || !IsWindowVisible(f)) return false;
    RECT fr{};
    if (!GetWindowRect(f, &fr)) return false;
    return fr.top > -1000 && fr.top < GetSystemMetrics(SM_CYSCREEN);
}

// Move the shell's flyout under our "^" and keep it there while it finishes opening: the
// shell draws it at its own place first and re-positions it at the end of its slide-in, so a
// single SetWindowPos right after the key press is not enough (measured: it jumped back).
// Returns true when the flyout was found at all.
static bool SettleFlyout(const PanelCtx& ctx, int ms) {
    HWND flyout = nullptr;
    int tx = 0, ty = 0, tw = 0, th = 0;
    bool havePlan = false;
    bool seen = false;
    for (int elapsed = 0; elapsed < ms; elapsed += 15) {
        if (!flyout || !IsWindow(flyout)) flyout = FindOverflowFlyout();
        if (flyout && IsWindowVisible(flyout)) {
            RECT fr{};
            if (GetWindowRect(flyout, &fr)) {
                seen = true;
                if (!havePlan) {
                    tw = (int)(fr.right - fr.left);
                    th = (int)(fr.bottom - fr.top);
                    PanelPlacementIn(ctx, tw, th, &tx, &ty);
                    havePlan = true;
                }
                if (havePlan && (fr.left != tx || fr.top != ty)) {
                    SetWindowPos(flyout, HWND_TOPMOST, tx, ty, 0, 0,
                                 SWP_NOSIZE | SWP_NOACTIVATE);
                    DLog(L"tray: native flyout %p moved %ld,%ld -> %d,%d (%dx%d)",
                         (void*)flyout, (long)fr.left, (long)fr.top, tx, ty, tw, th);
                }
            }
        }
        Sleep(15);
    }
    return seen;
}

// Bring the taskbar up and toggle the overflow flyout, then put the taskbar back down.
//
// Win+B is "focus the notification area": unlike a plain Win press it does **not** open the
// Start menu, and the shell puts the keyboard focus on the "show hidden icons" chevron, so a
// single Space opens the flyout (measured by the user 2026-11-16 23:0x). It also needs no
// screen coordinates. Falls back to "Win + click the chevron" if the taskbar never shows up.
static bool NativeTrayPageKeyboard(const PanelCtx& ctx) {
    // ⛔ STABLE (HANDOVER_NEXT.md §3.19): three things in here are load-bearing.
    //   1. the deny below: the shell expands the taskbar for its flyout, and an expanded bar
    //      is what later shows up as "the taskbar appears when the tray closes and stays";
    //   2. no "wait for the bar to rise" loop: the bar does not rise any more, and that loop
    //      cost a flat 500 ms on every "^" click;
    //   3. closing: Space, then park - never fall through into the open path (that toggled
    //      the shell's flyout back open: "it closes and then opens by itself").
    HWND tray = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!tray) return false;
    // Closing: while the flyout is in front of the user it owns the keyboard focus, so a plain
    // Space toggles it shut (measured twice). If Space does nothing (the XAML focus may have
    // wandered), park it: that is the same "closed" the outside-click handler uses, and it is
    // immediate - falling through into the Win+B path made a close take 3+ seconds and could
    // toggle the shell's flyout back open ("it pops up again by itself").
    {
        HWND fg = GetForegroundWindow();
        if (OverflowFlyoutOnScreen() && IsOverflowFlyoutWindow(fg)) {
            DLog(L"tray: native flyout - close with Space (the flyout owns the focus)");
            keybd_event(VK_SPACE, 0, 0, 0);
            Sleep(50);
            keybd_event(VK_SPACE, 0, KEYEVENTF_KEYUP, 0);
            for (int i = 0; i < 15; i++) {
                Sleep(20);
                HWND f = FindOverflowFlyout();
                if (!f || !IsWindowVisible(f)) {
                    DLog(L"tray: native flyout - closed by Space");
                    return true;
                }
            }
            DLog(L"tray: native flyout - Space did not close it, parking it instead");
            NativeTrayPark();
            return true;
        }
    }
    const int screenH = GetSystemMetrics(SM_CYSCREEN);
    RECT before{};
    if (!GetWindowRect(tray, &before)) return false;
    const bool alreadyUp = (before.top + before.bottom) / 2 < screenH;

    // No cloak, and **no rise either**: this whole path only needs the tray to take the
    // keyboard focus, and Space opens the flyout with the bar still sitting off screen
    // (measured 2026-11-17). Letting the shell expand the bar here is what produced the
    // user's "tray opens / taskbar hides, tray closes / taskbar appears and then sits there".
    TaskbarDenyExpansion(2000);

    keybd_event(VK_LWIN, 0, 0, 0);
    Sleep(40);
    keybd_event('B', 0, 0, 0);
    Sleep(40);
    keybd_event('B', 0, KEYEVENTF_KEYUP, 0);
    Sleep(40);
    keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, 0);

    // What Win+B has to achieve is the *keyboard focus* on the tray, not an expanded bar:
    // waiting for the bar rect used to cost a full 500 ms on every "^" (the bar never rises
    // here) and the focus arrives well before that.
    bool focus = false;
    for (int i = 0; i < 30 && !focus; i++) {
        if (GetForegroundWindow() == tray) { focus = true; break; }
        Sleep(10);
    }
    bool up = alreadyUp;
    if (!up) {
        RECT tr{};
        if (GetWindowRect(tray, &tr) && (tr.top + tr.bottom) / 2 < screenH) up = true;
    }
    DLog(L"tray: native flyout - bar %s, focus=%s", up ? L"up" : L"still down",
         focus ? L"tray" : L"elsewhere");
    // Space is harmless when it goes nowhere, so press it regardless: Win+B itself is
    // unreliable on this build (measured 2026-11-17: 0-1 out of 5, unaffected by scan codes,
    // by the mod's permission or by the cloak) and a late focus still gets activated.
    keybd_event(VK_SPACE, 0, 0, 0);
    Sleep(50);
    keybd_event(VK_SPACE, 0, KEYEVENTF_KEYUP, 0);
    bool seen = false;
    for (int i = 0; i < 15 && !seen; i++) {
        Sleep(20);
        HWND f = FindOverflowFlyout();
        seen = f && IsWindowVisible(f);
    }
    // On success the deny stays: the render tick keeps it alive for as long as the flyout is on
    // screen and drops it 700 ms after the flyout goes. Only a failed open gives it back right
    // away, so a Win press is not blocked by a stale request.
    if (!seen) TaskbarDenyExpansion(0);
    if (seen) SettleFlyout(ctx, 400);
    DLog(L"tray: native flyout - keyboard path done, flyout %s", seen ? L"open" : L"MISSING");
    return true;
}

// Old path, kept as a fallback: Win press (which also opens Start - the flash) + a real
// click on the chevron.
static bool NativeTrayPageMouse(const PanelCtx& ctx) {
    HWND tray = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!tray) return false;
    TaskbarDenyExpansion(0);           // a live Win+X deny must not block this Win press
    // This path raises the real taskbar and clicks its chevron, so the bar must not be drawn:
    // cloak it before the Win press goes out.
    g_cloakGraceUntil = GetTickCount() + 2500;
    TaskbarCloakForce();
    keybd_event(VK_LWIN, 0, 0, 0);
    Sleep(30);
    keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, 0);
    const int screenH = GetSystemMetrics(SM_CYSCREEN);
    for (int i = 0; i < 16; i++) {
        Sleep(30);
        RECT tr{};
        if (!GetWindowRect(tray, &tr)) continue;
        if ((tr.top + tr.bottom) / 2 >= screenH) continue;      // still off screen
        POINT pt{};
        if (!TrayChevronPoint(&pt)) continue;
        DLog(L"tray: native flyout - taskbar up (%ld,%ld-%ld,%ld), clicking its chevron at "
             L"%ld,%ld", (long)tr.left, (long)tr.top, (long)tr.right, (long)tr.bottom,
             (long)pt.x, (long)pt.y);
        ClickScreenPoint(pt.x, pt.y);
        Sleep(60);
        const bool seen = SettleFlyout(ctx, 400);
        HideNativeTaskbar();      // the flyout does not need it any more
        DLog(L"tray: native flyout - mouse path done, flyout %s", seen ? L"open" : L"MISSING");
        return true;
    }
    DLog(L"tray: native flyout - the taskbar never came up, nothing clicked");
    return false;
}

static bool NativeTrayPage(const PanelCtx& ctx) {
    if (NativeTrayPageKeyboard(ctx)) return true;
    return NativeTrayPageMouse(ctx);
}

// The whole open/close sequence needs ~0.5-1 s of waits. Running that on the window thread
// starves our low level mouse hook, and a hook that does not answer within
// LowLevelHooksTimeout stalls the *whole system's* pointer - measured as "the mouse is very
// choppy for a second after clicking ^". So the waiting happens on a worker thread; it only
// touches the shell's flyout window and posts a message back if it needs help.
#define WM_APP_TRAY_FELL_BACK (WM_APP + 21)

static HANDLE g_trayJobThread = nullptr;
static volatile LONG g_trayJobBusy = 0;
static PanelCtx g_trayJobCtx{};
static bool g_trayJobWasOpen = false;

static DWORD WINAPI TrayJobProc(LPVOID) {
    // ⛔ STABLE: no built-in-grid fallback (HANDOVER_NEXT.md §3.19). Showing our own grid after
    // a failed open costs another second and fights the shell for the next click; the user
    // asked for "just wait, or press Win and use the tray by hand" instead.
    const PanelCtx ctx = g_trayJobCtx;
    const bool wasOpen = g_trayJobWasOpen;
    if (!wasOpen) g_fgBeforeTray = GetForegroundWindow();
    bool ok = NativeTrayPage(ctx);
    if (ok && !wasOpen) {
        // give it a moment to actually show up before deciding it failed
        for (int i = 0; i < 10; i++) {
            HWND f = FindOverflowFlyout();
            if (f && IsWindowVisible(f)) break;
            Sleep(30);
        }
    }
    if (!ok || (!wasOpen && !OverflowFlyoutOnScreen())) {
        // No built-in-grid fallback on purpose (user 2026-11-17): the shell's flyout is the real
        // thing and it only ever needs a moment longer than we are willing to wait. Showing our
        // own grid instead costs another second and then fights the shell for the next click,
        // so waiting (or pressing Win and clicking the tray by hand) is simply better.
        // `[tray] native=0` is still the explicit way to get the grid.
        DLog(L"tray: native flyout did not show up - no grid fallback, leaving it to the user");
    }
    InterlockedExchange(&g_trayJobBusy, 0);
    return 0;
}

static void NativeTrayToggle() {
    if (InterlockedCompareExchange(&g_trayJobBusy, 1, 0) != 0) {
        DLog(L"tray: native flyout toggle ignored (previous one is still running)");
        return;
    }
    HWND flyout = FindOverflowFlyout();
    g_trayJobWasOpen = flyout && IsWindowVisible(flyout);
    RECT dr{};
    GetWindowRect(g_hwnd, &dr);
    g_trayJobCtx.strip = dr;
    g_trayJobCtx.chev = ChevronRect(dr);
    g_fgBeforeTray = GetForegroundWindow();
    DLog(L"tray: native flyout toggle (wasOpen=%d flyout=%p)", (int)g_trayJobWasOpen,
         (void*)flyout);
    if (!g_trayJobThread) {
        g_trayJobThread = CreateThread(nullptr, 0, TrayJobProc, nullptr, 0, nullptr);
    } else {
        // reuse the finished thread's slot by starting a fresh one (the old handle is done)
        CloseHandle(g_trayJobThread);
        g_trayJobThread = CreateThread(nullptr, 0, TrayJobProc, nullptr, 0, nullptr);
    }
    if (!g_trayJobThread) {
        InterlockedExchange(&g_trayJobBusy, 0);
        DLog(L"tray: could not start the flyout worker thread");
    }
}

// The shell does not dismiss the flyout on an outside click once it has been moved away from
// the taskbar (measured), and our own "^" toggle expects "visible == open", so park it off
// screen instead of trying to close it: the next "^" click then closes it for real.
static void NativeTrayPark() {
    if (!g_trayNative) return;
    HWND flyout = FindOverflowFlyout();
    if (!flyout || !IsWindowVisible(flyout)) return;
    RECT fr{};
    if (!GetWindowRect(flyout, &fr)) return;
    if (fr.top > 2000) return;                 // already parked
    SetWindowPos(flyout, nullptr, 0, 2000, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    DLog(L"tray: native flyout %p parked off screen (was %ld,%ld)", (void*)flyout,
         (long)fr.left, (long)fr.top);
}

static bool IsOverflowFlyoutWindow(HWND h) {
    if (!h || !g_trayNative) return false;
    HWND root = GetAncestor(h, GA_ROOT);
    if (!root) root = h;
    HWND flyout = FindOverflowFlyout();
    return flyout && root == flyout;
}

// ---------------------------------------------------------------- app "tasks" menu// A native taskbar right-click menu shows the app's own tasks (VSCode's "New Window",
// Windows Terminal's profiles, Edge's "New window/InPrivate"...). Windows has no public
// API to *ask* the shell for another app's jump list, so read what the shell itself
// keeps on disk:
//   %APPDATA%\Microsoft\Windows\Recent\CustomDestinations\*.customDestinations-ms
// Those files are not OLE compound documents: they are a flat sequence of shell link
// structures with a small header, so scan for the link header magic and load every hit.
struct JumpTask {
    std::wstring title;
    std::wstring target;
    std::wstring args;
    ULONGLONG fileTime = 0;      // when the destination file was last written
};

static std::vector<JumpTask> g_jumpTasks;    // cached parse of every custom destination
static std::wstring g_jumpSig;               // "count:maxWriteTime" of the folder
static DWORD g_jumpSigChecked = 0;

static std::wstring JumpDir() {
    wchar_t appdata[MAX_PATH]{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appdata))) return L"";
    return std::wstring(appdata) + L"\\Microsoft\\Windows\\Recent\\CustomDestinations";
}

static std::wstring JumpLinkTitle(IShellLinkW* lnk) {
    std::wstring out;
    IPropertyStore* ps = nullptr;
    if (SUCCEEDED(lnk->QueryInterface(IID_IPropertyStore, (void**)&ps))) {
        PROPVARIANT v;
        PropVariantInit(&v);
        if (SUCCEEDED(ps->GetValue(PKEY_Title, &v))) {
            if (v.vt == VT_LPWSTR && v.pwszVal) out = v.pwszVal;
            else if (v.vt == VT_BSTR && v.bstrVal) out = v.bstrVal;
        }
        PropVariantClear(&v);
        ps->Release();
    }
    return out;
}

// Parse a single .customDestinations-ms file into tasks.
static void ParseCustomDestination(const std::wstring& path, ULONGLONG fileTime,
                                   std::vector<JumpTask>& out) {
    HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) return;
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(f, &size) || size.QuadPart <= 0 || size.QuadPart > (16 << 20)) {
        CloseHandle(f);
        return;
    }
    std::vector<BYTE> buf((size_t)size.QuadPart);
    DWORD read = 0;
    ReadFile(f, buf.data(), (DWORD)buf.size(), &read, nullptr);
    CloseHandle(f);
    if (read < 24) return;

    static const BYTE magic[] = {0x4C, 0x00, 0x00, 0x00, 0x01, 0x14, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46};
    for (size_t i = 0; i + sizeof(magic) < (size_t)read; i++) {
        if (memcmp(buf.data() + i, magic, sizeof(magic)) != 0) continue;
        IStream* st = SHCreateMemStream(buf.data() + i, (UINT)(read - i));
        if (!st) continue;
        IShellLinkW* lnk = nullptr;
        if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                       IID_IShellLinkW, (void**)&lnk))) {
            IPersistStream* ps = nullptr;
            if (SUCCEEDED(lnk->QueryInterface(IID_IPersistStream, (void**)&ps))) {
                if (SUCCEEDED(ps->Load(st))) {
                    wchar_t target[MAX_PATH]{};
                    WIN32_FIND_DATAW fd{};
                    wchar_t args[1024]{};
                    lnk->GetPath(target, MAX_PATH, &fd, SLGP_RAWPATH);
                    lnk->GetArguments(args, 1024);
                    std::wstring title = JumpLinkTitle(lnk);
                    if (target[0] && !title.empty()) {
                        JumpTask t;
                        t.title = title;
                        t.target = Lower(target);
                        t.args = args;
                        t.fileTime = fileTime;
                        bool dup = false;
                        for (const auto& o : out) {
                            if (o.title == t.title && o.target == t.target && o.args == t.args) {
                                dup = true;
                                break;
                            }
                        }
                        if (!dup) out.push_back(std::move(t));
                    }
                }
                ps->Release();
            }
            lnk->Release();
        }
        st->Release();
    }
}

// Refresh the cache at most once a second, and only when the folder changed.
static void JumpTasksEnsure() {
    std::wstring dir = JumpDir();
    if (dir.empty()) return;
    DWORD now = GetTickCount();
    if (g_jumpSigChecked && now - g_jumpSigChecked < 1000) return;
    g_jumpSigChecked = now;
    std::wstring sig;
    {
        WIN32_FIND_DATAW fd{};
        HANDLE h = FindFirstFileW((dir + L"\\*.customDestinations-ms").c_str(), &fd);
        int count = 0;
        ULONGLONG newest = 0;
        if (h != INVALID_HANDLE_VALUE) {
            do {
                count++;
                ULONGLONG t = ((ULONGLONG)fd.ftLastWriteTime.dwHighDateTime << 32) |
                              fd.ftLastWriteTime.dwLowDateTime;
                if (t > newest) newest = t;
            } while (FindNextFileW(h, &fd));
            FindClose(h);
        }
        wchar_t b[64]{};
        _snwprintf_s(b, _countof(b), _TRUNCATE, L"%d:%llu", count, newest);
        sig = b;
    }
    if (sig == g_jumpSig && !g_jumpTasks.empty()) return;
    g_jumpSig = sig;
    std::vector<JumpTask> all;
    WIN32_FIND_DATAW fd{};
    HANDLE h = FindFirstFileW((dir + L"\\*.customDestinations-ms").c_str(), &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            ULONGLONG mt = ((ULONGLONG)fd.ftLastWriteTime.dwHighDateTime << 32) |
                           fd.ftLastWriteTime.dwLowDateTime;
            ParseCustomDestination(dir + L"\\" + fd.cFileName, mt, all);
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    DLog(L"menu: %d jump-list task(s) parsed from %s", (int)all.size(), sig.c_str());
    g_jumpTasks.swap(all);
}

static std::vector<JumpTask> JumpTasksForExe(const std::wstring& exe) {
    std::vector<JumpTask> out;
    if (exe.empty()) return out;
    JumpTasksEnsure();
    std::wstring want = Lower(exe);
    for (const auto& t : g_jumpTasks) {
        if (t.target == want) out.push_back(t);
    }
    // Several destination files can exist for one exe (Edge/Chrome create one per
    // profile or automation run). The native menu lists each task once, so keep the
    // newest file's copy of each title and drop the rest.
    std::stable_sort(out.begin(), out.end(),
                     [](const JumpTask& a, const JumpTask& b) { return a.fileTime > b.fileTime; });
    std::vector<JumpTask> uniq;
    for (const auto& t : out) {
        bool dup = false;
        for (const auto& o : uniq) {
            if (_wcsicmp(o.title.c_str(), t.title.c_str()) == 0) {
                dup = true;
                break;
            }
        }
        if (!dup) uniq.push_back(t);
    }
    return uniq;
}

static void RunJumpTask(const JumpTask& t) {
    DLog(L"menu: running task '%s' -> %s %s", t.title.c_str(), t.target.c_str(), t.args.c_str());
    HINSTANCE r = ShellExecuteW(nullptr, L"open", t.target.c_str(),
                                t.args.empty() ? nullptr : t.args.c_str(), nullptr, SW_SHOWNORMAL);
    if ((INT_PTR)r <= 32) DLog(L"menu: ShellExecute failed (%lld)", (long long)(INT_PTR)r);
}

// focus an existing window of that executable, otherwise start it
static void TrayActivate(const TrayEntry& e) {
    for (HWND h = GetTopWindow(nullptr); h; h = GetWindow(h, GW_HWNDNEXT)) {
        if (!IsWindowVisible(h) || IsIconic(h) || h == g_hwnd) continue;
        if (IsDockWindow(h)) continue;
        if (WindowExe(h) == e.exe) {
            ActivateWindow(h);
            return;
        }
    }
    LaunchPath(e.exe, L"tray");
}

// A left click on a cell opens what the cell stands for. The panel does NOT close:
// "click an icon -> the window opens, the strip and the grid keep their state" is the
// behaviour the user asked for (and what the native tray does).
static void GridClick(int cell) {
    if (cell < 0 || cell >= (int)g_gridCells.size()) return;
    const Slot s = g_gridCells[cell];
    if (g_menuOpen) CloseMenuNow(L"icon clicked");
    g_focusGraceUntil = GetTickCount() + 300;
    if (s.item >= 0) {
        if (s.item >= (int)g_items.size()) return;
        Item& it = g_items[s.item];
        if (it.hwnd && IsWindow(it.hwnd)) ActivateWindow(it.hwnd);
        else if (!it.lnkPath.empty()) LaunchShortcut(it.lnkPath, s.item);
        else if (!it.exePath.empty()) LaunchPath(it.exePath, L"grid pin");
        return;
    }
    int ti = -2 - s.item;
    if (ti < 0 || ti >= (int)g_tray.size()) return;
    const TrayEntry& e = g_tray[ti];
    // Native behaviour: the app decides what a left click on its tray icon means.
    if (ForwardTrayClick(e, WM_LBUTTONDOWN, WM_LBUTTONUP, L"left")) return;
    // No callback message to forward (a registry-fallback entry, or the icon died):
    // the app never gave us a way to talk to it, so fall back to the old guess.
    DLog(L"tray: left click on '%s' has no callback message - falling back to activate",
         e.tip.c_str());
    TrayActivate(e);
}

static LRESULT CALLBACK GridProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_MOUSEMOVE: {
            POINT pt{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            int hover = -1;
            for (int i = 0; i < (int)g_gridCells.size(); i++)
                if (PtInRect(&g_gridCells[i].rc, pt)) { hover = i; break; }
            TRACKMOUSEEVENT tme{sizeof(tme), TME_LEAVE, h, 0};
            TrackMouseEvent(&tme);
            if (hover != g_gridHover) {
                g_gridHover = hover;
                g_gridOutsideAt = 0;
                GridPaint();
            }
            return 0;
        }
        case WM_MOUSELEAVE:
            if (g_gridHover != -1) {
                g_gridHover = -1;
                GridPaint();
            }
            return 0;
        case WM_LBUTTONUP: {
            POINT pt{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            for (int i = 0; i < (int)g_gridCells.size(); i++) {
                if (PtInRect(&g_gridCells[i].rc, pt)) {
                    GridClick(i);
                    return 0;
                }
            }
            // Empty space in the panel: the menu (if any) goes, the panel stays.
            if (g_menuOpen) CloseMenuNow(L"click on empty panel space");
            return 0;
        }
        case WM_RBUTTONUP: {
            POINT pt{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            // Every right click inside the panel first puts the current menu away:
            // on another icon that replaces it, on the same icon it refreshes the
            // position (same path), on empty space it just closes it.
            if (g_menuOpen || g_menuWatch) CloseMenuNow(L"another right click in the panel");
            for (int i = 0; i < (int)g_gridCells.size(); i++) {
                if (!PtInRect(&g_gridCells[i].rc, pt)) continue;
                int ti = g_gridCells[i].item <= -2 ? (-2 - g_gridCells[i].item) : -1;
                if (ti >= 0 && ti < (int)g_tray.size() && g_tray[ti].hasBridge) {
                    const TrayEntry e = g_tray[ti];
                    RECT r = g_gridCells[i].rc;
                    POINT c{(r.left + r.right) / 2, (r.top + r.bottom) / 2};
                    ClientToScreen(h, &c);
                    // The panel stays in the topmost band: demoting it here meant that
                    // the app, activating itself for its own menu, was raised above the
                    // panel and simply covered it (looked like "the grid vanished").
                    // The menu is lifted instead, as soon as we spot it.
                    g_menuOpen = true;
                    g_menuSeen = false;
                    g_menuHwnd = nullptr;
                    g_menuItemPressAt = 0;
                    // the previous menu (if any) was already closed above
                    // swallow the press that opened us so it is not read as "click outside"
                    GetAsyncKeyState(VK_LBUTTON);
                    GetAsyncKeyState(VK_RBUTTON);
                    g_menuOpenedAt = GetTickCount();
                    g_menuOutsideAt = 0;
                    // The app pops its own menu at the pointer, exactly as if the icon
                    // had been right-clicked in the real tray - and the pointer is
                    // never moved for that. A menu that ends up partly off screen is
                    // shifted afterwards (FitMenuToWorkArea), not pre-empted by a
                    // SetCursorPos: that made the user's mouse visibly jump.
                    POINT target{c.x, c.y};
                    GetCursorPos(&target);
                    g_menuCursorPt = target;
                    g_menuAdjusted = false;
                    HWND owner = (HWND)(ULONG_PTR)e.ownerHwnd;
                    g_menuPid = 0;
                    g_menuBaseline.clear();
                    if (IsWindow(owner)) {
                        DWORD pid = 0;
                        GetWindowThreadProcessId(owner, &pid);
                        g_menuPid = pid;
                        CollectPidWindows(g_menuPid, g_menuBaseline);
                    }
                    DLog(L"tray: cell %d -> tray[%d] '%s' (%s) bridge=%d owner=%p", i, ti,
                         e.tip.c_str(), e.exe.c_str(), (int)e.hasBridge, (void*)owner);
                    if (IsWindow(owner)) {
                        // Post the press as well as the release. A lone
                        // WM_RBUTTONUP is ignored by apps whose tray handler arms
                        // its menu on the button-down: measured on 2026-11-10,
                        // QQ (Electron notify-icon host) and 网易UU远程 (Qt tray)
                        // open their menu only for the down+up pair.
                        // Electron's tray menu calls SetForegroundWindow on its own
                        // window before showing the menu. A process that is not the
                        // foreground app is normally not allowed to do that, so the
                        // menu silently never appears (measured: the same post works
                        // when some window is foreground, fails when there is none).
                        // Grant the permission for the next caller - this is exactly
                        // what the shell does for a real tray click.
                        AllowSetForegroundWindow(ASFW_ANY);
                        // With no foreground window at all, an Electron tray menu never
                        // shows up (its own SetForegroundWindow is refused). Give the
                        // app a window to activate first; it is also what happens when
                        // the real tray icon is clicked (the shell owns the foreground).
                        if (!GetForegroundWindow()) {
                            DWORD opid = 0;
                            GetWindowThreadProcessId(owner, &opid);
                            struct Ctx {
                                DWORD pid;
                                HWND found;
                            } fctx{opid, nullptr};
                            EnumWindows(
                                [](HWND h, LPARAM lp) -> BOOL {
                                    auto* c = reinterpret_cast<Ctx*>(lp);
                                    DWORD wp = 0;
                                    GetWindowThreadProcessId(h, &wp);
                                    if (wp != c->pid || !IsWindowVisible(h)) return TRUE;
                                    if (GetWindow(h, GW_OWNER)) return TRUE;
                                    RECT r{};
                                    if (!GetWindowRect(h, &r)) return TRUE;
                                    if (r.right - r.left < 120 || r.bottom - r.top < 80)
                                        return TRUE;
                                    c->found = h;
                                    return FALSE;
                                },
                                (LPARAM)&fctx);
                            if (fctx.found) {
                                SetForegroundWindow(fctx.found);
                                DLog(L"tray: no foreground window - activated %p first",
                                     (void*)fctx.found);
                            }
                        }
                        wchar_t cls[64]{};
                        GetClassNameW(owner, cls, 64);
                        BOOL okDown = PostMessageW(owner, e.callbackMsg, (WPARAM)e.ownerUid,
                                                   WM_RBUTTONDOWN);
                        DWORD errDown = GetLastError();
                        g_upPendingWnd = owner;
                        g_upPendingMsg = e.callbackMsg;
                        g_upPendingUid = e.ownerUid;
                        g_upPendingButton = WM_RBUTTONUP;
                        g_postQueue[0] = WM_RBUTTONUP;
                        g_postLen = 1;
                        g_postPos = 0;
                        g_upPendingAt = GetTickCount() + 70;
                        g_menuRetried = false;
                        g_retryWnd = owner;
                        g_retryMsg = e.callbackMsg;
                        g_retryUid = e.ownerUid;
                        g_retryAt = GetTickCount() + 300;
                        BOOL okUp = TRUE;
                        DWORD errUp = 0;
                        HWND fg = GetForegroundWindow();
                        wchar_t fgCls[64]{};
                        if (fg) GetClassNameW(fg, fgCls, 64);
                        DLog(L"tray: right click -> %p msg=0x%X uid=%u (down+up) cls=%s "
                             L"post=%d/%d err=%lu/%lu fg=%p(%s) cursor=%ld,%ld",
                             (void*)owner, e.callbackMsg, e.ownerUid, cls, (int)okDown, (int)okUp,
                             (unsigned long)errDown, (unsigned long)errUp, (void*)fg, fgCls,
                             (long)target.x, (long)target.y);
                    }
                    return 0;
                }
                if (ti >= 0 && ti < (int)g_tray.size()) {
                    // known icon, but the app never gave us a callback message (or it
                    // vanished): do what the real tray does - nothing - and keep the
                    // panel open instead of making it disappear under the cursor.
                    DLog(L"tray: right click on '%s' ignored (no callback message)",
                         g_tray[ti].tip.c_str());
                    return 0;
                }
                break;
            }
            // Right click on empty space in the panel: the panel stays (2c-ii). The old
            // menu was already closed above.
            DLog(L"tray: right click on empty panel space - panel stays");
            return 0;
        }
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_DESTROY:
            g_gridWnd = nullptr;
            g_gridVisible = false;
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// The panel is never closed by the pointer wandering off any more: only a click
// outside it (PressWatchTick) or losing the foreground (FocusWatchTick) ends it.
// Anything else - moving over the strip, over the app's menu, to another monitor -
// keeps the strip and the panel up, which is how the real tray flyout behaves.

// ---------------------------------------------------------------- thumbnails
// DWM live thumbnails cannot be composited onto a layered window, so the preview
// lives in its own small topmost popup. Its position is recomputed from the
// hovered button's screen rect every time it is shown, so it follows the dock
// wherever it is dragged.

static HTHUMBNAIL g_thumb = nullptr;
static HWND g_thumbTarget = nullptr;
static int g_thumbIndex = -1;
static int g_thumbItem = -1;    // item behind the preview: slot index != item index when scrolled

static const int kThumbPad = 10;
static const int kTitleH = 22;

static void ThumbHide() {
    if (g_thumb) {
        DwmUnregisterThumbnail(g_thumb);
        g_thumb = nullptr;
        g_thumbTarget = nullptr;
    }
    if (g_thumbWnd && IsWindowVisible(g_thumbWnd)) ShowWindow(g_thumbWnd, SW_HIDE);
    g_thumbIndex = -1;
    g_thumbItem = -1;
}

static void ThumbPaint(HWND h) {
    PAINTSTRUCT ps{};
    HDC dc = BeginPaint(h, &ps);
    RECT rc{};
    GetClientRect(h, &rc);
    HBRUSH b = CreateSolidBrush(RGB(32, 32, 32));
    FillRect(dc, &rc, b);
    DeleteObject(b);

    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(235, 235, 235));
    HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
    HGDIOBJ old = SelectObject(dc, font);
    // g_thumbItem, not g_thumbIndex: the slot index only equals the item index at scroll 0
    std::wstring title = (g_thumbItem >= 0 && g_thumbItem < (int)g_items.size())
                             ? g_items[g_thumbItem].title
                             : L"";
    RECT tr{kThumbPad, 3, rc.right - kThumbPad, kTitleH};
    DrawTextW(dc, title.c_str(), -1, &tr, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_LEFT);
    SelectObject(dc, old);
    EndPaint(h, &ps);
}

static LRESULT CALLBACK ThumbProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_PAINT:
            ThumbPaint(h);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_DESTROY:
            ThumbHide();
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

static void ThumbShow(int index) {
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
    RECT btn = slot.rc;
    POINT tl{btn.left, btn.top};
    POINT br{btn.right, btn.bottom};
    ClientToScreen(g_hwnd, &tl);
    ClientToScreen(g_hwnd, &br);

    int w = g_cfg.thumbWidth + kThumbPad * 2;
    int h = kTitleH + kThumbPad * 2 + g_cfg.thumbHeight;

    RECT dockRect{};
    GetWindowRect(g_hwnd, &dockRect);
    bool vertical = (dockRect.bottom - dockRect.top) > (dockRect.right - dockRect.left);

    int x, y;
    if (vertical) {
        // vertical dock: put the preview beside it, not on top of it
        x = dockRect.left - w - 6;
        y = tl.y + (br.y - tl.y) / 2 - h / 2;
    } else {
        x = tl.x + (br.x - tl.x) / 2 - w / 2;
        y = tl.y - h - 6;
    }

    HMONITOR mon = MonitorFromPoint({(tl.x + br.x) / 2, tl.y}, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{sizeof(mi)};
    if (GetMonitorInfoW(mon, &mi)) {
        if (vertical) {
            if (x < mi.rcWork.left) x = dockRect.right + 6;
            if (x + w > mi.rcWork.right) x = mi.rcWork.right - w;
        } else if (y < mi.rcWork.top) {
            y = br.y + 6;                              // no space above: go below
        }
        if (x + w > mi.rcWork.right) x = mi.rcWork.right - w;
        if (x < mi.rcWork.left) x = mi.rcWork.left;
        if (y + h > mi.rcWork.bottom) y = mi.rcWork.bottom - h;
    }

    SetWindowPos(g_thumbWnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);

    if (g_thumbTarget != it.hwnd) {
        if (g_thumb) {
            DwmUnregisterThumbnail(g_thumb);
            g_thumb = nullptr;
        }
        g_thumbTarget = nullptr;
        if (SUCCEEDED(DwmRegisterThumbnail(g_thumbWnd, it.hwnd, &g_thumb))) g_thumbTarget = it.hwnd;
        else g_thumb = nullptr;
    }
    if (g_thumb) {
        DWM_THUMBNAIL_PROPERTIES props{};
        props.dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY |
                        DWM_TNP_SOURCECLIENTAREAONLY;
        props.rcDestination = {kThumbPad, kTitleH + kThumbPad, kThumbPad + g_cfg.thumbWidth,
                               kTitleH + kThumbPad + g_cfg.thumbHeight};
        props.opacity = 255;
        props.fVisible = TRUE;
        props.fSourceClientAreaOnly = TRUE;
        DwmUpdateThumbnailProperties(g_thumb, &props);
    }
    g_thumbIndex = index;
    g_thumbItem = itemIndex;
    InvalidateRect(g_thumbWnd, nullptr, TRUE);
}

// Default size for a fresh install: one row/column sized by the configured icon.
static void ComputeLayout(int* pw, int* ph) {
    // +1: the Windows button always owns a cell, even with no items at all
    int n = (int)g_items.size() + 1;
    if (n < 1) n = 1;
    int icon = g_cfg.iconSize < 40 ? 40 : g_cfg.iconSize;
    int cell = icon + g_cfg.gap;
    int pad = g_cfg.pad;
    if (pw) *pw = n * cell - g_cfg.gap + pad * 2;
    if (ph) *ph = icon + pad * 2;
}

static bool g_pressActive = false;
static int g_pressSlot = -1;
static HWND g_pressHwnd = nullptr;
static std::wstring g_pressLnk;
static POINT g_pressPos{};
static POINT g_pressScreen{};
static int g_resizeEdge = 0;
static RECT g_resizeRect{};
static POINT g_resizeOrigin{};

// Which edge/corner is under the point? Two zones, because one is not enough:
//  * a generous square at each window corner - always easy to hit, and it is
//    what makes diagonal resizes feel natural at small radii
//  * the painted rounded outline itself - needed at radius=100, where the
//    visible "corner" is a round cap far away from the window corner (those
//    rect corners are transparent, so no mouse input ever arrives there)
static void PaintAndPresent();      // defined further down
static bool FullyTransparent();     // defined further down

// A fully transparent strip draws nothing over its padding, so a window wider than the
// icons leaves the resize band on an invisible edge. Snap the window back to the box the
// icons actually occupy (+pad) once a resize finishes: the edge band then sits on the ring
// just outside the icons and the corner zones on the end icons' corners, and because the box
// is derived from the icons, neither their size nor their count changes.
static void ShrinkToIcons() {
    if (!g_hwnd) return;
    if (!FullyTransparent()) return;                    // only when invisible
    RECT wr{};
    if (!GetWindowRect(g_hwnd, &wr)) return;
    int oldW = wr.right - wr.left, oldH = wr.bottom - wr.top;
    ComputeButtons();
    int cells = (int)g_slots.size();
    if (cells < 1) return;
    const int pad = g_cfg.pad, gap = g_cfg.gap;
    int span = cells * (g_iconPx + gap) - gap;
    // Orientation comes from the shape that was just dragged, NOT from the ini key: the
    // strip is rotated by resizing it, and the ini value is only what the last session
    // ended with (nothing updates it while dragging). Reading the key here made a tall
    // strip snap back to a wide one the moment the button was released.
    bool vertical = (oldH > oldW);
    g_cfg.vertical = vertical ? 1 : 0;
    int tw, th;
    if (vertical) { th = span + pad * 2; tw = g_iconPx + pad * 2; }
    else { tw = span + pad * 2; th = g_iconPx + pad * 2; }
    if (tw == oldW && th == oldH) return;
    if (tw <= 0 || th <= 0) return;
    // keep the centre where it was, so the strip settles instead of jumping to one side
    int x = wr.left + (oldW - tw) / 2;
    int y = wr.top + (oldH - th) / 2;
    DLog(L"shrink: %dx%d -> %dx%d at %d,%d (transparent strip hugs its icons, vertical=%d)",
         oldW, oldH, tw, th, x, y, (int)vertical);
    g_cfg.x = x;
    g_cfg.y = y;
    g_cfg.w = tw;
    g_cfg.h = th;
    SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, tw, th, SWP_NOACTIVATE);
    ComputeButtons();
    g_bakeDirty = true;
    SavePosition();
    SaveSize();
    PaintAndPresent();
}

// Union of the icon cells, in client coordinates. With no glass the padding is alpha 0, and a
// layered window gets no mouse input on transparent pixels - so the resize zones have to sit
// on the icons themselves, not on the invisible margin. Using the icons' own box puts the
// 10 px band over the icons' outer edge (top/bottom) and the corner squares on the end icons'
// corners, which is exactly where the user can see something to grab.
static RECT IconBox() {
    RECT r{INT_MAX, INT_MAX, INT_MIN, INT_MIN};
    for (size_t i = 0; i < g_slots.size(); i++) {
        const RECT& s = g_slots[i].rc;
        if (s.left < r.left) r.left = s.left;
        if (s.top < r.top) r.top = s.top;
        if (s.right > r.right) r.right = s.right;
        if (s.bottom > r.bottom) r.bottom = s.bottom;
    }
    return r;
}

static bool FullyTransparent() {
    return g_glass[0].glassOpacity == 0 && g_glass[0].tintStrength == 0;
}

static int EdgeAt(POINT p, const RECT& rcIn) {
    if (!g_cfg.allowResize) return 0;
    RECT rc = rcIn;
    if (FullyTransparent()) {
        // Deflate by the padding instead of using the slot bounding box: a hovered icon is
        // drawn 1.34x and would drag the box around under the cursor, while the padding ring
        // is exactly the part of the window that has no icons in it. After ShrinkToIcons()
        // the window is icons+pad, so this is precisely the icon box.
        rc.left += g_cfg.pad;
        rc.top += g_cfg.pad;
        rc.right -= g_cfg.pad;
        rc.bottom -= g_cfg.pad;
        if (rc.right - rc.left < 24 || rc.bottom - rc.top < 24) rc = rcIn;
    }
    int w = rc.right - rc.left, h = rc.bottom - rc.top;
    if (w <= 0 || h <= 0) return 0;
    p.x -= rc.left;
    p.y -= rc.top;

    const int cz = 24;                     // corner square
    bool cx = (p.x < cz) || (p.x >= w - cz);
    bool cy = (p.y < cz) || (p.y >= h - cz);
    if (cx && cy) return (p.x < w / 2 ? 1 : 2) | (p.y < h / 2 ? 4 : 8);

    int rr = CornerRadiusAt(p.x, p.y, w, h, RadiusFor(w, h));
    double mx = w / 2.0, my = h / 2.0, hw = w / 2.0, hh = h / 2.0;
    double dx = fabs(p.x + 0.5 - mx) - (hw - rr);
    double dy = fabs(p.y + 0.5 - my) - (hh - rr);
    bool corner = (dx > 0 && dy > 0);
    if (dx < 0) dx = 0;
    if (dy < 0) dy = 0;
    double d = sqrt(dx * dx + dy * dy) - rr;      // signed distance to the outline
    const int band = 10;
    if (d > band || d < -band) return 0;
    if (corner) return (p.x < mx ? 1 : 2) | (p.y < my ? 4 : 8);
    int e = 0;
    if (p.x < band) e |= 1;
    else if (p.x >= w - band) e |= 2;
    if (p.y < band) e |= 4;
    else if (p.y >= h - band) e |= 8;
    return e;
}

// Acrylic/blur needs a normal (non-layered) window, and our icon layer must stay
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
    if (!setAttr) {
        static bool logged = false;
        if (!logged) { logged = true; DLog(L"accent: SetWindowCompositionAttribute not found"); }
        return;
    }
    ACCENTPOLICY policy{state, state == ACCENT_ENABLE_TRANSPARENTGRADIENT ? 0x13 : 0, color, 0};
    WINCOMPATTRDATA data{WCA_ACCENT_POLICY, &policy, sizeof(policy)};
    BOOL ok = setAttr(hwnd, &data);
    static int logged = 0;
    if (logged < 3) { logged++; DLog(L"accent: state=%d color=%08X ok=%d", state, color, (int)ok); }
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

    SetWindowPos(g_bgWnd, ZBandInsert(), wr.left, wr.top, wr.right - wr.left,
                 wr.bottom - wr.top, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // rounded corners
    HRGN rgn = CreateRoundRectRgn(0, 0, wr.right - wr.left + 1, wr.bottom - wr.top + 1,
                                  g_cfg.radius * 2, g_cfg.radius * 2);
    SetWindowRgn(g_bgWnd, rgn, TRUE);
    // fade: the tint alpha follows the strip opacity
    DWORD alpha = (g_cfg.tint >> 24) & 0xFF;
    DWORD rr = (g_cfg.tint >> 16) & 0xFF, gg = (g_cfg.tint >> 8) & 0xFF, bb = g_cfg.tint & 0xFF;
    DWORD tint = (((DWORD)alpha * g_alpha / 255) << 24) | (bb << 16) | (gg << 8) | rr;
    ApplyAccent(g_bgWnd, g_cfg.material == 2 ? ACCENT_ENABLE_ACRYLICBLURBEHIND
                                             : ACCENT_ENABLE_BLURBEHIND,
                tint);
    // keep the icon layer above the background
    // ZBandInsert: this runs on *every* alpha change, so a fade-in (the pointer coming back to
    // the dock) used to re-promote the strip in the middle of a snip - that is the "something of
    // ours re-asserted topmost during a capture" the QQ flow produced (2026-11-22 01:20:17).
    SetWindowPos(g_hwnd, ZBandInsert(), 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

// Glass backdrop, following what GlassBoard does:
//  * capture the window *underneath* with PrintWindow (never hide ourselves,
//    so there is nothing to flicker), cached for 160 ms
//  * downscale to 1/4, box-blur twice with a radius capped at 64 (cheap), then
//    upscale into the draw buffer
static void FreeGlass(GlassTarget& t) {
    if (t.bmp) { DeleteObject(t.bmp); t.bmp = nullptr; }
    t.bits = nullptr;
    t.w = t.h = 0;
    t.valid = false;
    t.dirty = true;
}
static void FreeBake() { FreeGlass(g_stripGlass); }

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

// ---- diagnostics -------------------------------------------------------
// Dump a 32bpp top-down buffer as a BMP next to dock.ini so the captured
// backdrop can actually be looked at instead of guessed about.
static void SaveBmp(const wchar_t* name, const uint32_t* px, int w, int h) {
    if (!px || w <= 0 || h <= 0) return;
    std::wstring path = g_iniPath;
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) path.resize(slash + 1);
    else path.clear();
    path += name;

    BITMAPFILEHEADER fh{};
    BITMAPINFOHEADER ih{};
    ih.biSize = sizeof(ih);
    ih.biWidth = w;
    ih.biHeight = -h;
    ih.biPlanes = 1;
    ih.biBitCount = 32;
    ih.biCompression = BI_RGB;
    ih.biSizeImage = (DWORD)((size_t)w * h * 4);
    fh.bfType = 0x4D42;
    fh.bfOffBits = sizeof(fh) + sizeof(ih);
    fh.bfSize = fh.bfOffBits + ih.biSizeImage;

    HANDLE f = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) { DLog(L"bake: dump failed err=%lu", GetLastError()); return; }
    DWORD wr = 0;
    WriteFile(f, &fh, sizeof(fh), &wr, nullptr);
    WriteFile(f, &ih, sizeof(ih), &wr, nullptr);
    WriteFile(f, px, ih.biSizeImage, &wr, nullptr);
    CloseHandle(f);
    DLog(L"bake: dumped %s", path.c_str());
}

// Mean |luminance difference| between horizontally adjacent pixels: a hard
// number for "is there still sharp detail in here". Blur drives this to ~0.
static int DetailScore(const uint32_t* px, int w, int h) {
    if (!px || w < 2 || h < 2) return -1;
    long long sum = 0, n = 0;
    for (int y = 0; y < h; y += 2) {
        for (int x = 0; x + 1 < w; x += 2) {
            uint32_t a = px[(size_t)y * w + x], b = px[(size_t)y * w + x + 1];
            int la = ((int)(a & 0xFF) * 29 + (int)((a >> 8) & 0xFF) * 150 +
                      (int)((a >> 16) & 0xFF) * 77) >> 8;
            int lb = ((int)(b & 0xFF) * 29 + (int)((b >> 8) & 0xFF) * 150 +
                      (int)((b >> 16) & 0xFF) * 77) >> 8;
            sum += la > lb ? la - lb : lb - la;
            n++;
        }
    }
    return n ? (int)(sum / n) : -1;
}

// fraction of pixels that are not pure black (a blank PrintWindow capture)
static int NonBlackPct(const uint32_t* px, int w, int h) {
    if (!px || w <= 0 || h <= 0) return -1;
    long long n = 0, tot = 0;
    for (int y = 0; y < h; y += 2) {
        for (int x = 0; x < w; x += 2) {
            if (px[(size_t)y * w + x] & 0x00FFFFFF) n++;
            tot++;
        }
    }
    return tot ? (int)(n * 100 / tot) : -1;
}

// Every window this process puts on screen. A backdrop capture must never photograph one of
// them: with the strip as the only glass window that was just "skip g_hwnd", but as soon as a
// second glass window exists, the one would end up baked into the other's glass (H3).
static bool IsOurWindow(HWND h) {
    if (!h) return false;
    return h == g_hwnd || h == g_trayBar.hwnd || h == g_gridWnd || h == g_thumbWnd ||
           h == g_setWnd || h == g_menuHwnd || h == g_bgWnd;
}

// The list a capture has to keep out of the picture, most important first.
static int CollectOurWindows(HWND* out, int max) {
    int n = 0;
    HWND list[] = {g_hwnd, g_trayBar.hwnd, g_gridWnd, g_thumbWnd, g_setWnd, g_menuHwnd, g_bgWnd};
    for (HWND h : list) {
        if (h && IsWindowVisible(h) && n < max) out[n++] = h;
    }
    return n;
}

// ---------------------------------------------------------------- z-order policy (task 1)
//
// MEASURED with dev/t_ztry.ps1 (2026-11-22), do not "simplify" this back:
//   * WS_EX_TOPMOST is band *membership*, not a rank. A window created or raised *after* ours
//     that claims topmost legally lands above us (probe: our strip z#20, the new window z#17),
//     and nothing here ever took it back - Present()/CompanionSetRect()/GroupPlace() all pass
//     SWP_NOZORDER on purpose. That is the user's report: "for a while, whatever I just opened
//     covers the dock; the same app in the same place is fine again later". The cause comes and
//     goes with the *other* window, not with the dock.
//   * The way back is one SetWindowPos(HWND_TOPMOST, NOMOVE|NOSIZE|NOACTIVATE) on a window that
//     is *already* topmost: probe z#20 -> z#17, back on top. Promoting a window that LOST the
//     flag does not do that - it lands at the *bottom* of the topmost band (probe: z#73, still
//     under the other topmost window) - so the restore path asserts twice.
//   * Everything else here is a consequence: never fight the shell (the taskbar is topmost and
//     the whole tray logic in HANDOVER_NEXT.md §3.19 depends on it), never fight a menu, and
//     step *below* a capture tool (below).
//
// The capture half. QQ / WeChat / SnippingTool put a topmost full-screen window in front and
// draw the selection box in it. While that session is live the dock must sit *below* it: it
// would otherwise take the drag and paint itself over the box (measured: with the snip overlay
// up, our strip was the only window above it). Demoting hides nothing - the dock keeps being
// part of the picture, which is exactly what the user wants (2026-11-22): screenshots and
// screen recordings must show it. Only the z relationship to the capture tool changes, and only
// while that tool is in front. A recorder never puts a topmost full-screen window in front, so
// recording keeps the normal behaviour bit for bit.
// (g_zMode itself is declared up with ZBandInsert - the automatic show paths need it.)
static DWORD g_zCapturePid = 0;         // the capture tool we are yielding to
static DWORD g_zCaptureSeenAt = 0;      // last poll that still looked like that session
static HWND g_zLastCulprit = nullptr;   // diagnostics: log a given offender once per 10 s
static DWORD g_zLastLogAt = 0;
static int g_zReasserts = 0;            // diagnostics
static int g_zYields = 0;               // diagnostics

// System UI that is allowed to stay above the dock, i.e. never fought. The taskbar is topmost
// and *older* than us, but the shell re-raises it all the time; covering it would break the
// tray/taskbar state in HANDOVER_NEXT.md §3.19, which was expensive to get right.
static bool ZExemptClass(const wchar_t* cls) {
    static const wchar_t* list[] = {
        // shell: taskbar, its XAML islands, start/search/Win+X, IME + notification hosts
        L"Shell_TrayWnd", L"Shell_SecondaryTrayWnd", L"XamlExplorerHostIslandWindow_WASDK",
        L"Windows.UI.Core.CoreWindow", L"Shell_InputSwitchTopLevelWindow",
        L"MultitaskingViewFrame", L"Windows.Internal.Shell.TabProxyWindow",
        L"NotifyIconOverflowWindow", L"TopLevelWindowForOverflowXamlIsland",
        L"TaskListThumbnailWnd", L"ForegroundStaging",
        // transient UI that is *meant* to be above everything (menus, tooltips, balloon tips)
        L"#32768", L"#32769", L"tooltips_class32", L"DockTooltip",
        // WinUI/XAML popups (flyouts, combo drops, the shell's own menus on Win11)
        L"Xaml_WindowedPopupClass", L"Windows.UI.Composition.DesktopWindowContentBridge",
        // the desktop itself
        L"Progman", L"WorkerW", L"SysListView32",
    };
    for (auto s : list)
        if (!_wcsicmp(cls, s)) return true;
    return false;
}

static bool ZIsOurs(HWND h) {
    if (IsOurWindow(h)) return true;      // strip/companion/panel/settings/menu/thumb
    for (int i = 0; i < g_groupCount; i++)
        if (g_groups[i].hwnd == h) return true;   // the group frames are ours too
    return false;
}

// The shell's own process owns the taskbar, the start menu, quick settings, the notification
// host and the XAML popups/menus. Their class names change between Windows builds (measured
// 2026-11-22: `Xaml_WindowedPopupClass` from explorer.exe was fought and covered by the dock),
// so key on the process of GetShellWindow() instead of on an ever-growing class list.
static bool ZIsShellWindow(HWND h) {
    static HWND shellWnd = nullptr;
    static DWORD shellPid = 0;
    if (!shellWnd || !IsWindow(shellWnd)) {
        shellWnd = GetShellWindow();
        shellPid = 0;
        if (shellWnd) GetWindowThreadProcessId(shellWnd, &shellPid);
    }
    if (!shellPid) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    return pid == shellPid;
}

// One entry per on-screen window of ours.
struct ZMine {
    HWND h;
    int idx;        // index in the global top-to-bottom order
    RECT rc;
    bool topmost;
};

struct ZScanOut {
    HWND culprit = nullptr;      // a window above one of ours that overlaps it
    HWND mine = nullptr;         // the window of ours it covers
    wchar_t cls[64]{};
    DWORD pid = 0;
    bool culpritTopmost = false;
    bool culpritFullscreen = false;
    bool demoted = false;        // one of our on-screen windows lost WS_EX_TOPMOST
    HWND demotedHwnd = nullptr;
};

struct ZScanCtx {
    ZMine mine[8];
    int nMine = 0;
    RECT uni{};
    bool haveUni = false;
    int idx = 0;
    ZScanOut out;
};

static BOOL CALLBACK ZCollectProc(HWND h, LPARAM lp) {
    auto* c = reinterpret_cast<ZScanCtx*>(lp);
    int i = c->idx++;
    if (!IsWindowVisible(h) || !ZIsOurs(h)) return TRUE;
    RECT r{};
    if (!GetWindowRect(h, &r)) return TRUE;
    if (c->nMine < 8) {
        ZMine& m = c->mine[c->nMine++];
        m.h = h;
        m.idx = i;
        m.rc = r;
        m.topmost = (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
        if (!c->haveUni) {
            c->uni = r;
            c->haveUni = true;
        } else {
            UnionRect(&c->uni, &c->uni, &r);
        }
    }
    return TRUE;
}

static BOOL CALLBACK ZScanProc(HWND h, LPARAM lp) {
    auto* c = reinterpret_cast<ZScanCtx*>(lp);
    int i = c->idx++;
    if (c->out.culprit || !c->haveUni) return TRUE;      // the highest offender is the answer
    if (!IsWindowVisible(h) || IsIconic(h) || ZIsOurs(h)) return TRUE;
    RECT r{};
    if (!GetWindowRect(h, &r)) return TRUE;
    // cheap reject first: does it come near the area our windows live in at all?
    if (r.right <= c->uni.left || r.left >= c->uni.right || r.bottom <= c->uni.top ||
        r.top >= c->uni.bottom)
        return TRUE;
    // a closed UWP/app window stays WS_VISIBLE and is only cloaked by DWM: not on screen
    if (IsCloaked(h)) return TRUE;
    wchar_t cls[64]{};
    GetClassNameW(h, cls, 64);
    if (ZExemptClass(cls)) return TRUE;
    if (ZIsShellWindow(h)) return TRUE;
    for (int k = 0; k < c->nMine; k++) {
        const ZMine& m = c->mine[k];
        if (i >= m.idx) continue;                        // below that window of ours
        if (r.right <= m.rc.left || r.left >= m.rc.right || r.bottom <= m.rc.top ||
            r.top >= m.rc.bottom)
            continue;
        c->out.culprit = h;
        c->out.mine = m.h;
        wcscpy_s(c->out.cls, cls);
        GetWindowThreadProcessId(h, &c->out.pid);
        c->out.culpritTopmost = (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
        // A window that owns (nearly) a whole monitor is a fullscreen app: a game, a video, a
        // presentation. The dock must stay behind it, and it also stays behind the capture
        // tool - see ZCaptureActive().
        HMONITOR mon = MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi{sizeof(mi)};
        if (GetMonitorInfoW(mon, &mi)) {
            int mw = mi.rcMonitor.right - mi.rcMonitor.left;
            int mh = mi.rcMonitor.bottom - mi.rcMonitor.top;
            c->out.culpritFullscreen = (r.right - r.left) * 10 >= mw * 9 &&
                                       (r.bottom - r.top) * 10 >= mh * 9;
        }
        break;
    }
    return TRUE;
}

// What is above us that should not be, and did we lose the topmost flag anywhere?
static void ZScan(ZScanOut* out) {
    ZScanCtx c;
    EnumWindows(ZCollectProc, (LPARAM)&c);
    for (int k = 0; k < c.nMine; k++) {
        if (!c.mine[k].topmost) {
            c.out.demoted = true;
            c.out.demotedHwnd = c.mine[k].h;
            break;
        }
    }
    c.idx = 0;
    EnumWindows(ZScanProc, (LPARAM)&c);
    *out = c.out;
}

// Put our own stack back on top of the topmost band, bottom-most first: the order inside the
// stack is group frames < companion < strip < panel/settings/thumbnail, and every SetWindowPos
// moves the window to the top of the band, so the last one asserted ends up highest.
// `twice`: needed after a demote (the first call only lifts us off the non-topmost band).
static void ZAssertOurs(bool twice) {
    const int passes = twice ? 2 : 1;
    for (int p = 0; p < passes; p++) {
        for (int i = 0; i < g_groupCount; i++) {
            HWND h = g_groups[i].hwnd;
            if (h && IsWindowVisible(h))
                SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        if (g_trayBar.hwnd && IsWindowVisible(g_trayBar.hwnd))
            SetWindowPos(g_trayBar.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        if (g_hwnd && IsWindowVisible(g_hwnd))
            SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        // The panel, the settings page and the thumbnail preview belong above the strip - but NOT
        // while a foreign menu is up: TrayMenuTick() demotes the panel on purpose when it cannot
        // lift that menu above it (RaiseMenuAbovePanel), and asserting here would paint the panel
        // back over the app's menu.
        if (!g_menuOpen) {
            if (g_gridWnd && IsWindowVisible(g_gridWnd))
                SetWindowPos(g_gridWnd, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            if (g_setWnd && IsWindowVisible(g_setWnd))
                SetWindowPos(g_setWnd, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            if (g_thumbWnd && IsWindowVisible(g_thumbWnd))
                SetWindowPos(g_thumbWnd, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        g_zReasserts++;
    }
}

// Step *below* everything topmost (the capture tool), without hiding anything.
static void ZDemoteOurs() {
    HWND list[8]{};
    int n = CollectOurWindows(list, 8);
    for (int i = 0; i < n; i++)
        SetWindowPos(list[i], HWND_NOTOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    for (int i = 0; i < g_groupCount; i++) {
        HWND h = g_groups[i].hwnd;
        if (h && IsWindowVisible(h))
            SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    g_zYields++;
}

// Did anything of ours end up back in the topmost band while we are supposed to be below an
// overlay? ~10 GetWindowLong calls, cheap enough for every tick.
static bool ZAnyOursTopmost() {
    HWND list[8]{};
    int n = CollectOurWindows(list, 8);
    for (int i = 0; i < n; i++)
        if (GetWindowLongW(list[i], GWL_EXSTYLE) & WS_EX_TOPMOST) return true;
    for (int i = 0; i < g_groupCount; i++) {
        HWND h = g_groups[i].hwnd;
        if (h && IsWindowVisible(h) && (GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_TOPMOST))
            return true;
    }
    return false;
}

// A capture tool in its "pick a region" state: topmost, and owning (nearly) a whole monitor.
// Every snipping UI looks like this; a recorder does not.
// NOTE (measured 2026-11-22): the window that actually holds the foreground while the snip is up
// is SnippingTool's `SnipOverlayRootWindow`, and DWM reports it *cloaked* (the visible part is its
// child `XamlWindow`) - so do NOT test IsCloaked() on the foreground here, or the whole capture
// branch never runs and the dock only "happens" to be behind, until some other code path
// re-asserts it and it pops up over the selection box.
static bool ZIsCaptureWindow(HWND h) {
    if (!h || !IsWindow(h) || h == GetShellWindow()) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (!pid || pid == GetCurrentProcessId()) return false;
    // The start menu / search host are topmost full-screen `Windows.UI.Core.CoreWindow`s too
    // (measured 2026-11-22: the dock yielded to pid 17616, which was the shell). Anything the
    // shell owns is not a capture tool - the exempt list is exactly that distinction.
    wchar_t cls[64]{};
    if (!GetClassNameW(h, cls, 64)) return false;
    if (ZExemptClass(cls)) return false;
    if (!(GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_TOPMOST)) return false;
    RECT r{};
    if (!GetWindowRect(h, &r)) return false;
    HMONITOR mon = MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{sizeof(mi)};
    if (!GetMonitorInfoW(mon, &mi)) return false;
    int mw = mi.rcMonitor.right - mi.rcMonitor.left;
    int mh = mi.rcMonitor.bottom - mi.rcMonitor.top;
    return (r.right - r.left) * 10 >= mw * 9 && (r.bottom - r.top) * 10 >= mh * 9;
}

// Any window of `pid` still floating above everything? That is what a capture tool looks like
// once the region is picked: the box disappears and a small topmost toolbar ("more settings")
// stays. Cloaked windows do not count - the overlay host keeps a cloaked root window around
// after the session, and that must not keep us demoted forever.
static bool ZPidTopmostVisible(DWORD pid) {
    struct Ctx {
        DWORD pid;
        bool found;
    } c{pid, false};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            auto* c = reinterpret_cast<Ctx*>(lp);
            DWORD p = 0;
            GetWindowThreadProcessId(h, &p);
            if (p != c->pid) return TRUE;
            if (!IsWindowVisible(h) || IsCloaked(h)) return TRUE;
            if (!(GetWindowLongW(h, GWL_EXSTYLE) & WS_EX_TOPMOST)) return TRUE;
            c->found = true;
            return FALSE;
        },
        (LPARAM)&c);
    return c.found;
}

// Are we inside a capture session? Two independent signals, because neither alone is reliable:
//   * `overlayAboveUs` - the z-order scan found a fullscreen topmost window above one of ours
//     (measured: SnippingTool's overlay takes the foreground only intermittently, so the
//     foreground alone was not enough - a snip once went by with the dock still topmost);
//   * the foreground window itself looks like one (the case where we happen to be on top of it).
// Once detected the tool's pid is latched, which covers the phase *after* the box is drawn (a
// small topmost toolbar, not a full-screen window any more). Released as soon as that process
// has nothing floating any more - i.e. "the snip is done, here is the editor".
static bool ZCaptureActive(DWORD now, bool overlayAboveUs, DWORD overlayPid) {
    if (overlayAboveUs && overlayPid) {
        if (g_zCapturePid != overlayPid) {
            wchar_t cls[64]{};
            HWND fg = GetForegroundWindow();
            GetClassNameW(fg, cls, 64);
            DLog(L"zwatch: capture/fullscreen overlay above us (pid=%u, fg=%s) - stepping below it",
                 overlayPid, cls);
        }
        g_zCapturePid = overlayPid;
        g_zCaptureSeenAt = now;
        return true;
    }
    HWND fg = GetForegroundWindow();
    if (fg && ZIsCaptureWindow(fg)) {
        DWORD fgPid = 0;
        GetWindowThreadProcessId(fg, &fgPid);
        if (g_zCapturePid != fgPid) {
            wchar_t cls[64]{};
            GetClassNameW(fg, cls, 64);
            DLog(L"zwatch: capture overlay in front (cls=%s pid=%u) - stepping below it", cls, fgPid);
        }
        g_zCapturePid = fgPid;
        g_zCaptureSeenAt = now;
        return true;
    }
    if (g_zCapturePid) {
        if (ZPidTopmostVisible(g_zCapturePid)) {
            g_zCaptureSeenAt = now;
            return true;
        }
        // Grace: a tool blinks its own windows while it switches phases, and flapping would cost
        // two z-order round trips for nothing.
        if (now - g_zCaptureSeenAt < 900) return true;
        g_zCapturePid = 0;
    }
    return false;
}

// Runs on the 16 ms housekeeping gate, itself gated to ~450 ms: an EnumWindows of the top level
// costs a few hundred microseconds, and z-order does not move that fast.
static void ZWatchTick(DWORD now) {
    if (!g_cfg.zWatch) return;

    // While yielding, undo any re-assert immediately. This is the case the user hit with QQ's
    // snip: the selection toolbar and its menus sit right next to the dock, moving onto them
    // fades the companion in, and that show path lifted the whole dock back over the selection
    // box. Guarding the two automatic show paths (ZBandInsert) covers the known ones - this is
    // the net under all of them, and it runs on every tick (~16 ms) rather than on the 450 ms
    // poll, so the dock is never above the overlay long enough to be seen.
    if (g_zMode == 1) {
        static DWORD lastRedemote = 0;
        static DWORD lastRedemoteLog = 0;
        if (ZAnyOursTopmost() && (!lastRedemote || now - lastRedemote >= 150)) {
            lastRedemote = now;
            ZDemoteOurs();
            if (!lastRedemoteLog || now - lastRedemoteLog >= 5000) {
                lastRedemoteLog = now;
                DLog(L"zwatch: something of ours re-asserted topmost during a capture - demoted "
                     L"again");
            }
        }
    }

    static DWORD lastPoll = 0;
    if (lastPoll && now - lastPoll < 450) return;
    lastPoll = now;

    ZScanOut out;
    LARGE_INTEGER q0{}, q1{};
    QueryPerformanceCounter(&q0);
    ZScan(&out);
    QueryPerformanceCounter(&q1);
    const double scanMs = QpcMs(q0, q1);
    if (scanMs >= 3.0) DLog(L"slow: zwatch scan %.1f ms", scanMs);

    // A fullscreen *topmost* window above us is either a snipping UI or a fullscreen app. The
    // topmost requirement matters: while we are demoted every maximized window is "above us",
    // and without it a plain browser window would be mistaken for a capture tool (and latch its
    // pid). The right answer is the same for both real cases - the dock belongs *below* it - so
    // this needs no further distinction. What it does need is the demote: without it our own
    // show paths (CompanionVisibilityTick, the group show path) re-assert HWND_TOPMOST and the
    // dock pops up over the selection box in the middle of a drag.
    if (ZCaptureActive(now, out.culprit && out.culpritFullscreen && out.culpritTopmost, out.pid)) {
        if (g_zMode != 1) {
            g_zMode = 1;
            ZDemoteOurs();
            DLog(L"zwatch: yielding to a capture/fullscreen overlay (pid=%u) - our windows are "
                 L"non-topmost until it goes, still fully visible in the picture", g_zCapturePid);
        }
        return;
    }
    if (g_zMode == 1) {
        g_zMode = 0;
        ZAssertOurs(true);
        DLog(L"zwatch: overlay gone - topmost restored (%d asserts total)", g_zReasserts);
        return;
    }
    // Never move the band while the shell's tray flyout or a forwarded app menu is on screen:
    // both are topmost and have to stay above the dock (HANDOVER_NEXT.md §3.19 - the tray and
    // taskbar state is what the whole shell integration rests on). They live a few seconds.
    if (OverflowFlyoutOnScreen() || g_menuOpen) return;

    if (!out.culprit && !out.demoted) return;
    // Never fight a drag: the window is moving, its band is asserted again when it lands.
    if (g_dragging || g_dragMovePending || GroupDragging() || GroupScaling()) return;
    ZAssertOurs(out.demoted);
    if (out.culprit != g_zLastCulprit || !g_zLastLogAt || now - g_zLastLogAt > 10000) {
        g_zLastCulprit = out.culprit;
        g_zLastLogAt = now;
        if (out.culprit)
            DLog(L"zwatch: re-asserted topmost - %s (pid=%u topmost=%d) was above %p",
                 out.cls, out.pid, out.culpritTopmost ? 1 : 0, (void*)out.mine);
        else
            DLog(L"zwatch: re-asserted topmost - %p had lost WS_EX_TOPMOST", (void*)out.demotedHwnd);
    }
}

static HWND WindowUnderUs(const RECT& wr) {
    struct Ctx {
        const RECT* wr;
        HWND found;
    } ctx{&wr, nullptr};
    EnumWindows(
        [](HWND h, LPARAM lp) -> BOOL {
            auto* c = reinterpret_cast<Ctx*>(lp);
            if (IsOurWindow(h) || !IsWindowVisible(h) || IsIconic(h)) return TRUE;
            // A closed UWP/app window usually stays WS_VISIBLE and is only *cloaked* by
            // DWM. PrintWindow on one still renders its last frame, which is how a closed
            // Settings page kept showing up inside the glass: it was picked as "the window
            // under us" and photographed. Skip cloaked windows entirely.
            if (IsCloaked(h)) return TRUE;
            LONG ex = GetWindowLongW(h, GWL_EXSTYLE);
            if (ex & WS_EX_TOOLWINDOW) return TRUE;
            // The desktop window is not content: PrintWindow on Progman/WorkerW
            // gives a blank frame, which used to be turned into a black strip.
            wchar_t ucls[64]{};
            GetClassNameW(h, ucls, 64);
            if (!_wcsicmp(ucls, L"Progman") || !_wcsicmp(ucls, L"WorkerW") ||
                !_wcsicmp(ucls, L"SysListView32"))
                return TRUE;
            RECT r{};
            if (!GetWindowRect(h, &r)) return TRUE;
            if (r.right <= c->wr->left || r.left >= c->wr->right || r.bottom <= c->wr->top ||
                r.top >= c->wr->bottom)
                return TRUE;
            c->found = h;
            return FALSE;      // first visible, overlapping window in z-order
        },
        (LPARAM)&ctx);
    return ctx.found;
}

// Cost of the last WDA_EXCLUDEFROMCAPTURE toggle round (two calls per excluded window).
static DWORD g_lastAffinityMs = 0;
// Read the screen area we cover while keeping ourselves out of the picture.
// WDA_EXCLUDEFROMCAPTURE makes the compositor skip our window in captures, so
// what comes back is the real backdrop (wallpaper, UWP, video - anything that
// PrintWindow cannot render) and nothing on screen changes, so no flicker.
// Older systems do not support it: there we hide the window for the grab, which
// costs a possible one-frame blink but only on machines without the flag.
//
// H3: it is now *every* window of ours, not just the one being baked. Two glass windows
// overlap all the time (the float window sits under the strip); excluding only the one being
// captured would bake the other one's glass into the picture it shows, and the error would be
// permanent (each bake would re-photograph the wrong copy).
static bool GrabScreenExcluding(const HWND* exclude, int nExclude, std::vector<uint32_t>& out,
                                int w, int h, POINT origin) {
    if (w <= 0 || h <= 0) return false;

    // one reusable DIB: creating it per grab was most of the cost
    static HDC mdc = nullptr;
    static HBITMAP bmp = nullptr;
    static void* bits = nullptr;
    static int bw = 0, bh = 0;
    if (!mdc || bw != w || bh != h) {
        if (mdc) { DeleteDC(mdc); mdc = nullptr; }
        if (bmp) { DeleteObject(bmp); bmp = nullptr; }
        HDC screen = GetDC(nullptr);
        mdc = CreateCompatibleDC(screen);
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        ReleaseDC(nullptr, screen);
        if (bmp) SelectObject(mdc, bmp);
        bw = w;
        bh = h;
    }
    if (!bmp || !bits) return false;

    // H3 §3.1-4 policy, now narrow on purpose:
    //  * only the windows that actually overlap the captured rectangle get the flag - excluding
    //    all of them made the whole dock disappear from *other* programs' screenshots/video
    //    during every capture, for no benefit;
    //  * the affinity each window had before is restored, not blindly reset to WDA_NONE;
    //  * the toggling cost is measured (it is two trips to the compositor per window per grab).
    struct AffinitySave {
        HWND h;
        DWORD prev;
    };
    AffinitySave saved[8];
    int nSaved = 0;
    bool excluded = true;
    const DWORD tAff0 = GetTickCount();
    for (int i = 0; i < nExclude && nSaved < 8; i++) {
        RECT r{};
        if (!GetWindowRect(exclude[i], &r)) continue;
        if (r.right <= origin.x || r.left >= origin.x + w || r.bottom <= origin.y ||
            r.top >= origin.y + h)
            continue;                     // not in the picture at all: leave it untouched
        DWORD prev = WDA_NONE;
        GetWindowDisplayAffinity(exclude[i], &prev);
        if (!SetWindowDisplayAffinity(exclude[i], WDA_EXCLUDEFROMCAPTURE)) {
            excluded = false;
            break;
        }
        saved[nSaved].h = exclude[i];
        saved[nSaved].prev = prev;
        nSaved++;
    }
    if (!excluded) {
        for (int i = 0; i < nSaved; i++) SetWindowDisplayAffinity(saved[i].h, saved[i].prev);
        nSaved = 0;
        // Without the capture-exclusion flag the only way to keep ourselves out of the
        // picture is to hide the window for the grab. That is a visible blink, so it was
        // fine at 3 grabs/s and is not fine now that the snapshot refreshes 25-30x/s:
        // rather than flicker, keep the previous bake until the next slow moment. Only the
        // strip can do that (it is the window the picture is for); a companion would blink,
        // and skipping its capture is better than a capture nobody can look at.
        bool stripInList = false;
        for (int i = 0; i < nExclude; i++)
            if (exclude[i] == g_hwnd) stripInList = true;
        if (!stripInList) return false;
        static DWORD lastHideGrab = 0;
        DWORD t = GetTickCount();
        if (lastHideGrab && t - lastHideGrab < 500) return false;
        lastHideGrab = t;
        ShowWindow(g_hwnd, SW_HIDE);
    }

    HDC screen = GetDC(nullptr);
    bool ok = BitBlt(mdc, 0, 0, w, h, screen, origin.x, origin.y, SRCCOPY | CAPTUREBLT) != 0;
    ReleaseDC(nullptr, screen);

    for (int i = 0; i < nSaved; i++) SetWindowDisplayAffinity(saved[i].h, saved[i].prev);
    if (!excluded) {
        ShowWindow(g_hwnd, SW_SHOWNA);
        Present();
    }
    g_lastAffinityMs = GetTickCount() - tAff0;

    if (ok) {
        auto* src = (uint32_t*)bits;
        out.assign(src, src + (size_t)w * h);
        for (auto& v : out) v |= 0xFF000000;
    }
    static int logged = 0;
    if (logged < 3) {
        logged++;
        DLog(L"bake: screen grab via %s ok=%d (excluded %d of %d window(s), %lu ms)",
             excluded ? L"capture exclusion" : L"hide/show", (int)ok, nSaved, nExclude,
             (unsigned long)g_lastAffinityMs);
    }
    return ok;
}

// One full-window capture, reused for a short while. PrintWindow of the whole window
// (1938x1098 on this machine) dominates the cost of a bake, and while the strip moves
// the window under it stays the same - only the offset changes. Re-cropping that
// snapshot is a memcpy, so dragging can re-bake every frame instead of ~3x/s.
// The fallback path (no window under us: desktop / video wallpaper) used to grab the
// screen on *every* re-bake - 20ms each, which is what made dragging stutter. Cache the
// padded grab just like a window capture.
struct ScrCache {
    RECT rect{};
    DWORD at = 0;
    int w = 0, h = 0;
    std::vector<uint32_t> px;
};
static ScrCache g_scrCache;

static DWORD ScreenCacheTtl() {
    // This used to be 1500 ms while dragging, on the assumption that dragging never
    // re-grabs. It does now, and a 1.5 s cached snapshot in the middle of a drag is
    // exactly the frozen backdrop the glass was being blamed for.
    DWORD t;
    if (g_cfg.captureHz > 0) t = (DWORD)(1000 / g_cfg.captureHz);
    else t = 3600000;
    return t < 50 ? 50 : t;
}

struct UnderCache {
    HWND hwnd = nullptr;
    RECT rect{};
    DWORD at = 0;
    int w = 0, h = 0;
    std::vector<uint32_t> px;
};
static UnderCache g_underCache;

// H3 §3.3: is there room in this frame for one more capture? The *first* capture of a frame
// always runs (used = 0); a second one only if the frame is still under the budget. Two glass
// windows therefore take turns instead of stacking up in the same tick.
static bool BakeBudgetAllows() {
    if (g_bakeBudgetUsedMs <= 0) return true;
    return g_bakeBudgetUsedMs < g_cfg.captureBudgetMs;
}

// ---- H3c: the frozen work-area picture taken when a glass window starts moving -------------
// The plan (PLAN_COMPONENTS.md §3.2, user decision 2026-11-16 19:4x) is: at rest every glass
// window grabs only its own small area; the moment one *moves*, the dock takes ONE picture of
// the whole work area and freezes it, and only the moving window reads from it. That removes
// the two things a mid-drag screen read costs: the ~15 ms hitch, and a backdrop that jumps
// between frames (every grab catches a different instant).
// `dragNoCapture = 1` ("拖动时不更新背景", the user's own choice on 2026-11-17) means the
// opposite: take no picture at all and run the drag on the old bake.
struct GlassFrozen {
    bool valid = false;
    RECT rect{};                 // screen area it covers (the dragged window's work area)
    int w = 0, h = 0;
    DWORD at = 0;
    std::vector<uint32_t> px;    // raw desktop; blur/tint stay per window
};
static GlassFrozen g_frozen;
static int g_frozenCount = 0;        // frozen pictures taken since the last cadence line
static int g_frozenHits = 0;         // ... and bakes served out of one
static DWORD g_frozenTakenMs = 0;    // cost of the last one

static bool AnyGlassWindowOnScreen() {
    if (g_cfg.material == 1 && g_alpha > 0) return true;
    if (g_trayBar.hwnd && g_trayBar.alpha > 0 && CompanionUsesGlass(g_trayBar)) return true;
    return false;
}

// Copy w x h out of the frozen picture at capR; false when the two do not overlap at all.
// The overlap is clamped, not required: a bake is padded by up to 256 px, so the padded rect of
// a window near the screen edge sticks out of the work area - and those pixels are off screen,
// i.e. they can never be looked at. They simply stay at the neutral fill.
static bool FrozenCropInto(uint32_t* dst, int w, int h, const RECT& capR) {
    if (!g_frozen.valid || !dst) return false;
    RECT ov{};
    if (!IntersectRect(&ov, &capR, &g_frozen.rect)) return false;
    const int dx = ov.left - capR.left, dy = ov.top - capR.top;
    const int sx = ov.left - g_frozen.rect.left, sy = ov.top - g_frozen.rect.top;
    const int cw = ov.right - ov.left, ch = ov.bottom - ov.top;
    if (cw <= 0 || ch <= 0) return false;
    for (int y = 0; y < ch; y++)
        memcpy(dst + (size_t)(dy + y) * w + dx,
               &g_frozen.px[(size_t)(sy + y) * g_frozen.w + sx], (size_t)cw * 4);
    g_frozenHits++;
    return true;
}

static void FrozenBegin() {
    g_frozen.valid = false;      // never read a picture left over from an earlier drag
    if (g_cfg.dragNoCapture) {
        static DWORD lastLog = 0;
        DWORD t = GetTickCount();
        if (t - lastLog > 5000) {
            lastLog = t;
            DLog(L"glass: drag started with dragNoCapture=1 - no picture taken (the old bake "
                 L"stays frozen, as chosen)");
        }
        return;
    }
    if (!g_hwnd || !AnyGlassWindowOnScreen()) return;
    RECT wa = WorkAreaFor(g_hwnd);
    const int w = wa.right - wa.left, h = wa.bottom - wa.top;
    if (w <= 0 || h <= 0) return;
    HWND excl[8];
    const int nExclude = CollectOurWindows(excl, 8);
    const DWORD t0 = GetTickCount();
    // Straight into the buffer that is already allocated: GrabScreenExcluding() assigns into it,
    // so the 8 MB copy that a fresh vector would cost (3-5 ms on the first drag) only happens once.
    g_frozen.px.clear();
    if (!GrabScreenExcluding(excl, nExclude, g_frozen.px, w, h, POINT{wa.left, wa.top})) {
        DLog(L"glass: could not freeze the work area for this drag (small bakes stay in use)");
        return;
    }
    g_frozen.rect = wa;
    g_frozen.w = w;
    g_frozen.h = h;
    g_frozen.at = GetTickCount();
    g_frozen.valid = true;
    g_frozenCount++;
    g_frozenTakenMs = GetTickCount() - t0;
    g_bakeBudgetUsedMs += (int)g_frozenTakenMs;      // it is a capture: it counts for this frame
    DLog(L"glass: froze the work area %dx%d at %ld,%ld for this drag (%lu ms)", w, h,
         (long)wa.left, (long)wa.top, (unsigned long)g_frozenTakenMs);
}

static void FrozenEnd() { g_frozen.valid = false; }

// "A glass window is being moved right now" - one predicate, so the frozen picture starts and
// ends with the gesture instead of every drag path having to remember it.
static bool GlassDragActive() {
    return g_dragging || g_resizeEdge || DefaultGroupBusy() || GroupScaling() ||
           g_trayBar.dragging || g_trayBar.resizing;
}

// Rising/falling edge of GlassDragActive(): freeze the work area on the way in, drop it on the
// way out. On release both bakes are marked dirty, because the window now sits somewhere new
// and its picture is only valid for the position it was grabbed at.
static void GlassDragTick() {
    static bool prev = false;
    const bool active = GlassDragActive();
    if (active == prev) return;
    prev = active;
    if (active) {
        FrozenBegin();
    } else {
        FrozenEnd();
        g_bakeDirty = true;
        g_trayBar.glass.dirty = true;
    }
}

// What a BakeGlass() call did. The three cases need different handling by the caller, and the
// difference matters: a *failed* capture must not be retried every frame (that is a busy loop
// of 15 ms grabs), while one skipped for the budget *must* be retried on the next frame.
enum BakeResult {
    kBakeOk = 0,        // the target now holds a real capture
    kBakeFailed = 1,    // nothing usable was read; the target kept its previous picture
    kBakeNoBudget = 2,  // skipped on purpose (H3 §3.3): try again on a later frame
};

// Read + blur + tint the desktop behind `winRect` into `t`. `margin` pads the capture on every
// side, so a window that moves a little keeps reading the same picture at a new offset.
// `allowFrozen` is for windows that are *moving*: they read the frozen work-area picture
// (H3c) instead of paying for a screen read in the middle of the gesture.
static BakeResult BakeGlass(GlassTarget& t, const RECT& winRect, int margin, const wchar_t* tag,
                            DWORD tintRgb, const GlassCfg& gc, bool allowFrozen = false) {
    LARGE_INTEGER bq0{}, bq1{};
    QueryPerformanceCounter(&bq0);
    DWORD bakeT0 = GetTickCount();
    const int cw = winRect.right - winRect.left, ch = winRect.bottom - winRect.top;
    if (cw <= 0 || ch <= 0) return kBakeFailed;
    if (!BakeBudgetAllows()) return kBakeNoBudget;
    // wide margin while dragging, tight otherwise (the caller knows whether it is moving).
    // A resize grows the window, so the bake has to be big enough that the next few
    // hundred pixels of growth are already inside it - otherwise every frame re-grabs.
    // A *group* drag (board / 屏蔽位移) moves the strip exactly like its own drag does, so it
    // must get the same margin; without it the snapshot was 0 px wide and every frame was
    // painted from a picture that no longer covered the window ("背景抖动", 2026-11-16 14:48).
    const int M = margin;
    t.marginUsed = M;
    int w = cw + 2 * M, h = ch + 2 * M;

    if (w != t.w || h != t.h || !t.bmp) {
        FreeGlass(t);
        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        HDC screen = GetDC(nullptr);
        t.bmp = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &t.bits, nullptr, 0);
        ReleaseDC(nullptr, screen);
        t.w = w;
        t.h = h;
    }
    if (!t.bmp || !t.bits) return kBakeFailed;

    RECT capR{winRect.left - M, winRect.top - M, winRect.right + M, winRect.bottom + M};
    t.origin.x = capR.left;
    t.origin.y = capR.top;
    // everything of ours that must not appear in the picture (see GrabScreenExcluding)
    HWND excl[8];
    const int nExclude = CollectOurWindows(excl, 8);

    // Grab our (padded) rect out of whatever we are covering.
    // Source order matters for cost: reading the composited screen is one BitBlt of the
    // padded rect (~7 ms measured here), while PrintWindow of the window underneath costs
    // 31-39 ms - it makes that app re-render its *entire* window (1938x1098 here) so we
    // can keep a 1940x631 crop of it. The screen grab is also the more truthful source:
    // it is literally what is on screen now (video, UWP, layered widgets and all).
    // PrintWindow still wins in exactly one case: when one of *our own* popups is over the
    // window (hover preview, a tray menu, the grid, the settings panel). A screen grab would
    // bake that popup into the glass, while PrintWindow of the window underneath ignores it.
    const bool ownPopup = g_popupOpen || g_menuOpen || g_gridVisible || g_setWnd ||
                          (g_thumbWnd && IsWindowVisible(g_thumbWnd));
    std::vector<uint32_t> fbuf((size_t)w * h, 0xFF202020);
    bool got = false;
    int pwOk = 0;               // PrintWindow's return value
    int grabbed = 0;            // 1 = the fallback screen grab was used, 2 = its cache, 3 = frozen
    int copied = 0;             // pixels actually copied out of the capture
    int cacheHits = 0;          // 1 = re-cropped the cached full-window capture
    int underW = 0, underH = 0;
    wchar_t ucls[64] = L"-";
    // H3c: a moving window reads the picture that was frozen when the gesture started. This is
    // both cheaper (a memcpy instead of a BitBlt of the screen) and steadier (the backdrop is
    // the same instant for every frame of the drag).
    if (allowFrozen && FrozenCropInto(fbuf.data(), w, h, capR)) {
        got = true;
        grabbed = 3;
        copied = w * h;
    }
    HWND under = (!got && ownPopup) ? WindowUnderUs(capR) : nullptr;
    if (under) {
        RECT ur{};
        if (GetWindowRect(under, &ur)) {
            int uw = ur.right - ur.left, uh = ur.bottom - ur.top;
            underW = uw; underH = uh;
            GetClassNameW(under, ucls, 64);
            if (uw > 0 && uh > 0 && uw < 8000 && uh < 8000) {
                DWORD now = GetTickCount();
                bool cached = g_underCache.hwnd == under && g_underCache.w == uw &&
                              g_underCache.h == uh && g_underCache.at != 0 &&
                              now - g_underCache.at < 10000u &&
                              g_underCache.rect.left == ur.left &&
                              g_underCache.rect.top == ur.top &&
                              g_underCache.rect.right == ur.right &&
                              g_underCache.rect.bottom == ur.bottom &&
                              (int)g_underCache.px.size() == uw * uh;
                if (cached) {
                    pwOk = 1;          // it *was* captured, just not this time
                    cacheHits++;
                } else {
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
                        pwOk = 1;
                        g_underCache.hwnd = under;
                        g_underCache.rect = ur;
                        g_underCache.w = uw;
                        g_underCache.h = uh;
                        g_underCache.at = now;
                        g_underCache.px.assign((uint32_t*)bits,
                                               (uint32_t*)bits + (size_t)uw * uh);
                    } else {
                        g_underCache.at = 0;      // never trust a failed capture
                    }
                    SelectObject(mdc, old);
                    DeleteObject(bmp);
                    DeleteDC(mdc);
                    ReleaseDC(nullptr, screen);
                }
                if (pwOk && (int)g_underCache.px.size() == uw * uh) {
                    const uint32_t* src = g_underCache.px.data();
                    int lit = 0;         // copied pixels that are not pure black
                    for (int y = 0; y < h; y++) {
                        int sy = capR.top + y - ur.top;
                        if (sy < 0 || sy >= uh) continue;
                        for (int x = 0; x < w; x++) {
                            int sx = x + (capR.left - ur.left);
                            if (sx < 0 || sx >= uw) continue;
                            uint32_t c = src[(size_t)sy * uw + sx];
                            fbuf[(size_t)y * w + x] = c | 0xFF000000;
                            copied++;
                            if (c & 0x00FFFFFF) lit++;
                        }
                    }
                    // A capture that copied nothing is not a capture; neither is
                    // one that came back black. Only the *copied* pixels may be
                    // judged: the rest of fbuf still holds its neutral fill, and
                    // counting that is what let a black UWP frame through.
                    got = copied > 0 && (long long)lit * 100 / copied > 1;
                }
            }
        }
    }
    if (!got) {
        // No usable window underneath (bare desktop, or a UWP / compositor-drawn
        // window whose PrintWindow is a black frame). Read the real screen with
        // ourselves taken out of the picture instead.
        DWORD nowScr = GetTickCount();
        bool scrHit = g_scrCache.w == w && g_scrCache.h == h && g_scrCache.at != 0 &&
                      nowScr - g_scrCache.at < ScreenCacheTtl() &&
                      g_scrCache.rect.left == capR.left && g_scrCache.rect.top == capR.top &&
                      (int)g_scrCache.px.size() == w * h;
        if (scrHit) {
            memcpy(fbuf.data(), g_scrCache.px.data(), (size_t)w * h * 4);
            got = true;
            grabbed = 2;               // 2 = reused the cached screen grab
            copied = w * h;
        } else if (GrabScreenExcluding(excl, nExclude, fbuf, w, h,
                                       POINT{capR.left, capR.top})) {
            got = true;
            grabbed = 1;
            copied = w * h;
            g_scrCache.rect = capR;
            g_scrCache.at = nowScr;
            g_scrCache.w = w;
            g_scrCache.h = h;
            g_scrCache.px = fbuf;
        }
    }
    if (!got) {
        if (t.valid) {
            static DWORD lastQuiet = 0;
            DWORD t2 = GetTickCount();
            if (t2 - lastQuiet > 5000) {
                lastQuiet = t2;
                DLog(L"bake[%s]: nothing usable under us (under=%p cls=%s pw=%d) - keeping "
                     L"the previous bake",
                     tag, (void*)under, ucls, pwOk);
            }
            return kBakeFailed;
        }
        // First ever capture and no backdrop: neutral grey so the window is still
        // readable; the next successful capture replaces it.
    }

    // The blur runs on a downsampled copy, which is what keeps it cheap. The
    // downsample factor follows the radius: at 0 it is 1:1 (a clear, pixel-exact
    // backdrop - "blur 0" used to still look soft because it always went through
    // the 1/4 pipeline), at small radii 1/2, and 1/4 only where it pays off.
    int step = 4;
    if (gc.blurRadius <= 0) step = 1;
    else if (gc.blurRadius < 12) step = 2;
    int sw = (w + step - 1) / step, sh = (h + step - 1) / step;
    std::vector<uint32_t> qbuf;
    if (step == 1) {
        // blur is off, so the "downsample" below would average 1x1 blocks - a copy
        // through a nested loop with bounds checks, over the whole padded bake
        // (1.2 M px at margin 256). ~10 ms per capture for nothing.
        qbuf = fbuf;
    } else {
    qbuf.assign((size_t)sw * sh, 0xFF202020);
    for (int y = 0; y < sh; y++) {
        for (int x = 0; x < sw; x++) {
            uint32_t r = 0, g = 0, b = 0, n = 0;
            for (int yy = 0; yy < step; yy++) {
                int sy = y * step + yy;
                if (sy >= h) break;
                for (int xx = 0; xx < step; xx++) {
                    int sx = x * step + xx;
                    if (sx >= w) break;
                    uint32_t c = fbuf[(size_t)sy * w + sx];
                    b += c & 0xFF; g += (c >> 8) & 0xFF; r += (c >> 16) & 0xFF; n++;
                }
            }
            if (n) qbuf[(size_t)y * sw + x] = ((r / n) << 16) | ((g / n) << 8) | (b / n) | 0xFF000000;
        }
    }
    }

    // blurRadius is a full-resolution pixel radius (what the slider says); the
    // kernel works in the downsampled space, so divide by the step. Feeding the
    // raw value straight in made every setting above ~8 average the whole strip
    // into one flat colour.
    int rWide = 0;
    if (gc.blurRadius > 0) {
        rWide = (gc.blurRadius + step - 1) / step;      // ceil
        if (rWide < 1) rWide = 1;
        if (rWide > 64) rWide = 64;
        BoxBlurSmall(qbuf, sw, sh, rWide);
        BoxBlurSmall(qbuf, sw, sh, rWide);          // twice ~= gaussian
        int rFine = rWide / 3;
        if (rFine > 0) BoxBlurSmall(qbuf, sw, sh, rFine);
    }

    // upscale back into the draw buffer: bilinear, otherwise the 4x4 blocks of
    // the quarter-resolution buffer show up as a visible grid at low radii
    auto* dst = (uint32_t*)t.bits;
    if (step == 1) {
        // blur off -> step 1: the downscale above was a 1:1 copy and this "bilinear
        // upscale" is an identity, but it still ran a lambda per pixel over the whole
        // padded bake (1.2 M px at margin 256). That was ~10 ms of pure waste per capture.
        memcpy(dst, fbuf.data(), (size_t)w * h * 4);
    } else
    for (int y = 0; y < h; y++) {
        double fy = (y + 0.5) * sh / h - 0.5;
        int y0 = (int)floor(fy);
        double ty = fy - y0;
        if (y0 < 0) { y0 = 0; ty = 0; }
        int y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
        if (y0 >= sh) y0 = sh - 1;
        for (int x = 0; x < w; x++) {
            double fx = (x + 0.5) * sw / w - 0.5;
            int x0 = (int)floor(fx);
            double tx = fx - x0;
            if (x0 < 0) { x0 = 0; tx = 0; }
            int x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
            if (x0 >= sw) x0 = sw - 1;
            uint32_t p00 = qbuf[(size_t)y0 * sw + x0], p10 = qbuf[(size_t)y0 * sw + x1];
            uint32_t p01 = qbuf[(size_t)y1 * sw + x0], p11 = qbuf[(size_t)y1 * sw + x1];
            double w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty);
            double w01 = (1 - tx) * ty, w11 = tx * ty;
            auto chan = [&](int shift) {
                double v = (p00 >> shift & 0xFF) * w00 + (p10 >> shift & 0xFF) * w10 +
                           (p01 >> shift & 0xFF) * w01 + (p11 >> shift & 0xFF) * w11;
                int iv = (int)(v + 0.5);
                return (uint32_t)(iv < 0 ? 0 : (iv > 255 ? 255 : iv));
            };
            dst[(size_t)y * w + x] = (chan(16) << 16) | (chan(8) << 8) | chan(0) | 0xFF000000;
        }
    }

    // One line that says whether we captured, whether we blurred, and how much
    // detail survived. detail pre >> post means the blur really ran. Logged when
    // something changes (or as a 5 s heartbeat): the bake itself runs ~3x/s.
    int cx = w / 2, cy = h / 2;
    uint32_t pre = fbuf[(size_t)cy * w + cx], post = dst[(size_t)cy * w + cx];
    int covPct = (w > 0 && h > 0) ? (int)((long long)copied * 100 / ((long long)w * h)) : 0;
    {
        static DWORD lastLog = 0;
        static long long lastSig = -1;
        long long sig = (long long)got * 1000000000LL + (long long)pwOk * 100000000LL +
                        (long long)grabbed * 10000000LL + (long long)rWide * 10000 +
                        (long long)w * 100 + h;
        DWORD t2 = GetTickCount();
        // `grabbed` is part of the signature and flips between 1 (fresh grab) and 2
        // (cached), so this line used to fire on every capture - and each firing runs
        // DetailScore twice over the whole padded bake. Rate-limit it.
        if (((sig != lastSig || !got) && t2 - lastLog > 1500) || t2 - lastLog > 5000) {
            lastSig = sig;
            lastLog = t2;
            DLog(L"bake[%s]: under=%p cls=%s got=%d pw=%d grab=%d cover=%d%% under=%dx%d "
                 L"size=%dx%d small=%dx%d r=%d crop=%d took=%lu",
                 tag, (void*)under, ucls, (int)got, pwOk, grabbed, covPct, underW, underH, w, h,
                 sw, sh, rWide, cacheHits, (unsigned long)(GetTickCount() - bakeT0));
            DLog(L"bake[%s]: pre=%08X post=%08X detail %d -> %d (tint=%d op=%d hue=%06X)", tag,
                 pre, post, DetailScore(fbuf.data(), w, h), DetailScore(dst, w, h),
                 g_cfg.tintStrength, g_cfg.glassOpacity, tintRgb & 0x00FFFFFFu);
        }
    }
    if (g_cfg.dumpBake) {
        wchar_t n1[64], n2[64];
        swprintf_s(n1, L"dock_bake_%s_pre.bmp", tag);
        swprintf_s(n2, L"dock_bake_%s_post.bmp", tag);
        SaveBmp(n1, fbuf.data(), w, h);
        SaveBmp(n2, dst, w, h);
    }

    // Lift + tint + glassOpacity are a pure function of this pixel, so they are applied
    // here - once per capture - instead of once per frame in Paint().
    {
        double a = gc.glassOpacity / 255.0;
        double tintK = gc.tintStrength / 255.0;
        // The window's 色调 is the glass tint colour (2026-11-21: it replaced `tint` + 浅色/深色).
        DWORD tr = (tintRgb >> 16) & 0xFF, tg = (tintRgb >> 8) & 0xFF, tb = tintRgb & 0xFF;
        uint32_t* px = (uint32_t*)t.bits;
        const size_t n = (size_t)w * h;
        for (size_t i = 0; i < n; i++) {
            uint32_t v = px[i];
            double bl = v & 0xFF, gn = (v >> 8) & 0xFF, rd = (v >> 16) & 0xFF;
            double lum = rd * 0.2126 + gn * 0.7152 + bl * 0.0722;
            double lift = (128.0 - lum) * 0.16;
            rd += lift; gn += lift; bl += lift;
            if (rd < 0) rd = 0; if (rd > 255) rd = 255;
            if (gn < 0) gn = 0; if (gn > 255) gn = 255;
            if (bl < 0) bl = 0; if (bl > 255) bl = 255;
            double gr = rd * (1 - tintK) + tr * tintK;
            double gg = gn * (1 - tintK) + tg * tintK;
            double gb = bl * (1 - tintK) + tb * tintK;
            gr = gr * a + rd * (1 - a);
            gg = gg * a + gn * (1 - a);
            gb = gb * a + bl * (1 - a);
            px[i] = 0xFF000000u | ((DWORD)gr << 16) | ((DWORD)gg << 8) | (DWORD)gb;
        }
    }

    const DWORD costMs = GetTickCount() - bakeT0;
    t.at = GetTickCount();
    t.lastMs = costMs;
    t.valid = true;
    t.dirty = false;              // only after a successful capture
    g_lastBakeMs = costMs;
    g_bakeBudgetUsedMs += (int)costMs;      // H3 §3.3: the rest of this frame may be out of budget
    g_captureCount++;
    QueryPerformanceCounter(&bq1);
    g_statBake += QpcMs(bq0, bq1);
    g_statBakes++;
    return kBakeOk;
}

// Bake the strip's own backdrop. Kept as its own function because two things here are the
// strip's alone: the margin (a drag re-crops the same picture instead of re-grabbing) and the
// g_bakeDirty flag the paint path keys off.
static void CaptureBackdrop() {
    if (!g_hwnd) return;
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    if (rc.right <= 0 || rc.bottom <= 0) return;
    const bool moving = g_dragging || g_resizeEdge || DefaultGroupBusy() || GroupScaling();
    // H3c: with "拖动时不更新背景" on, a drag updates nothing at all - the bake stays exactly as
    // it was and the glass slides along with the window until the button comes back up. That is
    // the user's pick (2026-11-17): cheaper and predictable, at the cost of the picture "sticking"
    // to the window for the length of the drag.
    if (moving && g_cfg.dragNoCapture) {
        g_bakeDirty = false;
        return;
    }
    const int M = moving ? g_bakeMargin : (g_glass[0].blurRadius > 0 ? 64 : 0);
    RECT wr{};
    GetWindowRect(g_hwnd, &wr);
    const BakeResult r = BakeGlass(g_stripGlass, wr, M, L"strip", g_hue[0], g_glass[0], moving);
    // ⛔ A *failed* capture clears the flag even though nothing was captured (the previous
    // bake is still good). Leaving it set would retry a 15 ms grab on every single frame.
    // One skipped for the frame budget keeps it set, so the next frame picks it up again.
    if (r != kBakeNoBudget) g_bakeDirty = false;
}

static void PaintAndPresent() {
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


// ---------------------------------------------------------------- settings UI (G3)
// Self-drawn panel: same layered/alpha pipeline as the dock, so it gets the same rounded,
// translucent look, and every change is applied while you drag.
//
// Since G3 the panel is **paged**: every window (the strip, each companion, each group) has its
// own page, and every row is bound to "an ini section + a key". The pages are rebuilt when the
// panel opens, so a group created from a menu shows up immediately.

struct SRow {
    const wchar_t* key;
    const wchar_t* label;
    int minv;
    int maxv;
    int colorAlpha;             // 1 = edits the alpha of a colour value
    int isToggle;               // 1 = segmented buttons instead of a slider
    const wchar_t* onText;      // toggle label of value 1 (left pill); nullptr = 开
    const wchar_t* offText;     // toggle label of value 0 (right pill); nullptr = 关
    // N-way choice (H2): labels for the values 0..N-1, drawn left to right. Replaces the slider
    // for things like "background type". nullptr = not a choice row.
    const wchar_t* const* choices = nullptr;
    int choiceCount = 0;
    // Value to show while the key is still absent from the ini (a fresh profile). It has to agree
    // with the default in LoadConfig(), or the panel disagrees with the running program - the
    // trap the dodge switch fell into (behaviour on, panel reading 关). 0 = "same as before".
    int defv = 0;
};

struct SPage {
    std::wstring title;
    std::wstring section;       // ini section the rows read/write ("" for group pages)
    const SRow* rows;
    int count;
    int kind;
    int groupId;                // kPageGroupKind only
};

// forward declarations for the picture row / row state helpers (defined with SettingsPaint below)
static std::wstring GalleryNewest();
static void WriteImagePath(const std::wstring& section, const std::wstring& path);
// The two picture buttons must never open a dialog from inside a mouse message.
// ⛔ Reported 2026-11-21 02:0x: picking a picture then closing the dialog made it reopen, forever.
// Cause: WM_LBUTTONDOWN set g_dragRow + capture and called RowFromX() straight away; the modal
// file dialog keeps pumping our messages, so every WM_MOUSEMOVE with the row still "dragged" ran
// RowFromX() again - and for the picture row that means "open the dialog again". A queued action
// plus a re-entry guard makes the click return before any dialog exists.
static const UINT kSetMsgPickImage = WM_APP + 7;
static int g_setPickAction = 0;        // 1 = from the gallery, 2 = add a new picture
static bool g_pickBusy = false;        // a dialog is up right now

static void SettingsPaint();
static void SettingsPickFromGallery();
static void SettingsPickNewImage();
static void SetHueFor(int which, DWORD rgb);
static void PickHue(int which);
static bool SettingsRowVisible(const SPage* p, int i);
static bool SettingsRowDisabled(const SPage* p, int i);
static bool AnyScreenBackdrop();      // defined with the component helpers further down

// ---------------------------------------------------------------- H2: pages by component
// A page belongs to a *component*, not to a window kind: the strip has (float + bar + glass),
// a glass companion has (float + glass), a plain companion only (float). The tab set of an
// object is therefore "the pages of the components it owns" (PLAN_COMPONENTS.md §2.2).
enum Component { kCompFloat = 1, kCompBar = 2, kCompGlass = 4 };

static const wchar_t* const kBgNames[] = {L"透过背后", L"图片", L"纯色"};
static const wchar_t* const kColorNames[] = {L"黑", L"白"};
// 隐藏方案 (group page): the three ways a group may get out of the way.
static const wchar_t* const kHideModeNames[] = {L"距离", L"贴边", L"从不"};

// 色调 presets: soft macaron colours plus one dark, so a fresh profile can still look like the
// old dark glass (user picked "预设七八种马卡龙淡色 + 一个调色盘", 2026-11-21).
static const DWORD kHuePresets[] = {0xF7C8D0, 0xFAD7B0, 0xF6EDA8, 0xBFE6D0,
                                    0xBBDDE8, 0xCFC7E8, 0xD8D8DC, 0x2B2B30};
static const int kHueCount = (int)(sizeof(kHuePresets) / sizeof(kHuePresets[0]));

// ---- 玻璃页 (component: kCompGlass; global, one copy for every glass window) --------------
static const SRow kRowsGlass[] = {
    {L"glassOpacity", L"玻璃不透明度", 0, 255, 0, 0, nullptr, nullptr},
    {L"tintStrength", L"色调浓度", 0, 255, 0, 0, nullptr, nullptr},
    {L"blurRadius", L"背景模糊半径 (px)", 0, 64, 0, 0, nullptr, nullptr},
    {L"refreshHz", L"背景刷新帧率 (Hz)（共享）", 0, 180, 0, 0, nullptr, nullptr},
    {L"captureHz", L"背景截取频率 (Hz)（共享）", 0, 180, 0, 0, nullptr, nullptr},
    // H3 §3.3: how much of one frame may be spent starting captures (see Config).
    {L"captureBudgetMs", L"每帧截取预算 (ms)（共享）", 0, 100, 0, 0, nullptr, nullptr},
    // H3: off = keep the frozen backdrop while dragging (the user picked that on 2026-11-17,
    // knowing the background "sticks" to the window for the length of the drag).
    {L"dragNoCapture", L"拖动时不更新背景（共享）", 0, 1, 0, 1, L"不更新", L"更新"},
};

// 玻璃页 for a *companion*: the appearance rows are its own (-1 = inherit the strip's), the
// cadence rows are machine-wide and are therefore not repeated here (user, 2026-11-21).
static const SRow kRowsGlassTray[] = {
    {L"glassOpacity", L"玻璃不透明度（覆盖）", -1, 255, 0, 0, nullptr, nullptr},
    {L"tintStrength", L"色调浓度（覆盖）", -1, 255, 0, 0, nullptr, nullptr},
    {L"blurRadius", L"背景模糊半径（覆盖）", -1, 64, 0, 0, nullptr, nullptr},
    // The machine-wide cadence keys are shown here too (one config, editable from any glass
    // window); they always read/write [dock], see IsSharedGlassKey(). They are locked unless this
    // very window bakes a screen backdrop, because a picture background needs no captures.
    {L"refreshHz", L"背景刷新帧率 (Hz)（共享）", 0, 180, 0, 0, nullptr, nullptr},
    {L"captureHz", L"背景截取频率 (Hz)（共享）", 0, 180, 0, 0, nullptr, nullptr},
    {L"captureBudgetMs", L"每帧截取预算 (ms)（共享）", 0, 100, 0, 0, nullptr, nullptr},
    {L"dragNoCapture", L"拖动时不更新背景（共享）", 0, 1, 0, 1, L"不更新", L"更新"},
};

// ---- 浮窗页 for the strip (component: kCompFloat; section [dock]) -------------------------
static const SRow kRowsFloatDock[] = {
    {L"bgMode", L"背景", 0, 2, 0, 0, nullptr, nullptr, kBgNames, 3},
    {L"glassLayer", L"玻璃层", 0, 1, 0, 1, L"开", L"关"},
    // 色调 (H3, 2026-11-21): the window's colour - paints the solid background AND is the glass
    // layer's tint colour. It replaced the old black/white switch and the glass page's 浅色/深色.
    {L"hue", L"色调", 0, 0, 0, 0, nullptr, nullptr},
    {L"solidOpacity", L"纯色不透明度", 0, 255, 0, 0, nullptr, nullptr},
    // Only shown while the background *is* a picture (see SettingsRowVisible); its two buttons
    // open the gallery / add a new picture - there is no numeric value behind it.
    {L"image", L"背景图片", 0, 0, 0, 0, nullptr, nullptr},
    {L"radius", L"圆角 (0 直角 / 100 半圆)", 0, 100, 0, 0, nullptr, nullptr},
    // task 3: square off the two corners of the screen edge the window hugs.
    {L"snap", L"贴边方角", 0, 1, 0, 1, L"开", L"关", nullptr, 0, 1},
    {L"pad", L"内边距", 0, 40, 0, 0, nullptr, nullptr},
};

// ---- 浮窗页 for a companion (component: kCompFloat; section [traybar]) -------------------
// -1 = inherit from [dock], exactly like radius/pad/gap already did.
static const SRow kRowsFloatTray[] = {
    {L"bgMode", L"背景", -1, 2, 0, 0, nullptr, nullptr, kBgNames, 3},
    {L"glassLayer", L"玻璃层", -1, 1, 0, 1, L"开", L"关"},
    {L"hue", L"色调", 0, 0, 0, 0, nullptr, nullptr},
    {L"solidOpacity", L"纯色不透明度", -1, 255, 0, 0, nullptr, nullptr},
    // Same picture row as the strip's (inherits [dock] image= when empty).
    {L"image", L"背景图片", 0, 0, 0, 0, nullptr, nullptr},
    {L"radius", L"圆角（覆盖）", -1, 64, 0, 0, nullptr, nullptr},
    // task 3: -1 = inherit the strip's [dock] snap (the panel shows the value in force).
    {L"snap", L"贴边方角（覆盖）", -1, 1, 0, 1, L"开", L"关", nullptr, 0, 1},
    {L"pad", L"内边距（覆盖）", -1, 40, 0, 0, nullptr, nullptr},
    {L"gap", L"格子间距（覆盖）", -1, 40, 0, 0, nullptr, nullptr},
};

// ---- 图标条页 (component: kCompBar; things a float window has no use for) ----------------
static const SRow kRowsBar[] = {
    {L"iconSize", L"默认图标尺寸", 16, 128, 0, 0, nullptr, nullptr},
    {L"gap", L"图标间距", 0, 40, 0, 0, nullptr, nullptr},
    {L"minIcon", L"最小图标", 8, 64, 0, 0, nullptr, nullptr},
    {L"maxIcon", L"最大图标", 16, 160, 0, 0, nullptr, nullptr},
    {L"hoverMs", L"图标动画时长 (ms)", 40, 600, 0, 0, nullptr, nullptr},
    {L"scrollStep", L"滚轮翻页步长", 1, 5, 0, 0, nullptr, nullptr},
    // task 2: the double-click dodge is a strip gesture, so its switch lives here. Off only
    // removes the path that hops the strip across the centre line; an icon's double click and
    // the tray button are untouched.
    {L"dodgeOnDoubleClick", L"双击空白处闪避（跳到另一侧）", 0, 1, 0, 1, L"开", L"关", nullptr, 0, 1},
};

// Group page: the frame and its two switches.
static const SRow kRowsGroup[] = {
    {L"enabled", L"显示边框线", 0, 1, 0, 1, L"显示", L"隐藏"},
    {L"lineAlpha", L"线不透明度", 0, 255, 0, 0, nullptr, nullptr},
    {L"lineWidth", L"线宽", 1, 4, 0, 0, nullptr, nullptr},
    {L"margin", L"边框外扩 (px)", 0, 40, 0, 0, nullptr, nullptr},
    {L"radius", L"圆角", 0, 64, 0, 0, nullptr, nullptr},
    {L"blockResize", L"屏蔽缩放", 0, 1, 0, 1, L"屏蔽", L"允许"},
    {L"blockMove", L"屏蔽位移", 0, 1, 0, 1, L"屏蔽", L"允许"},
    // H2b: the fade distances are the group's (measured to the group's own rectangle). They only
    // exist in 隐藏方案=鼠标距离 (see SettingsRowVisible).
    // task 4: 隐藏方案 decides the whole tail of this page: distance fade, 贴边隐藏, or never.
    {L"hideMode", L"隐藏方案", 0, 2, 0, 0, nullptr, nullptr, kHideModeNames, 3},
    {L"fadeStart", L"完全显示距离", 0, 200, 0, 0, nullptr, nullptr},
    {L"fadeEnd", L"完全透明距离", 20, 400, 0, 0, nullptr, nullptr},
    // The band's colour: a group has no tone of its own, so it gets one here (falls back to the
    // strip's tone until it is set).
    {L"hue", L"唤醒区域色调", 0, 0, 0, 0, nullptr, nullptr},
    {L"wakeExt", L"唤出区域宽度 (px)", 0, 10, 0, 0, nullptr, nullptr},
    {L"wakeVisible", L"唤出区域常显", 0, 1, 0, 1, L"可见", L"不可见"},
    // task 4: 0 = click the band, 1 = move into it. The toggle's left pill is "value 1", so the
    // labels have to be (1, 0) in that order - the first version had them swapped (user, 2026-11-22).
    {L"wakeMode", L"唤出方式", 0, 1, 0, 1, L"进入", L"单击"},
};

static std::vector<SPage> g_pages;
static int g_page = 0;
static std::vector<int> g_rowVal;
static int g_dragRow = -1;
static HDC g_setDC = nullptr;
static HBITMAP g_setBmp = nullptr;
static void* g_setBits = nullptr;
static int g_setW = 760, g_setH = 720;

static const int kTabH = 44;        // tab bar height
static const int kRowsTop = 122;    // first row's top edge
static const int kRowH = 58;        // row pitch

static int TintAlpha() { return (int)((g_cfg.tint >> 24) & 0xFF); }

static const SPage* ActivePage() {
    if (g_page < 0 || g_page >= (int)g_pages.size()) return nullptr;
    return &g_pages[g_page];
}

// ---- per-kind value access ----------------------------------------------------------------
static int GroupKeyVal(Group& g, const wchar_t* key) {
    if (!wcscmp(key, L"enabled")) return g.enabled ? 1 : 0;
    if (!wcscmp(key, L"lineAlpha")) return g.lineAlpha;
    if (!wcscmp(key, L"lineWidth")) return g.lineWidth;
    if (!wcscmp(key, L"margin")) return g.margin;
    if (!wcscmp(key, L"radius")) return g.radius;
    if (!wcscmp(key, L"blockResize")) return g.blockResize ? 1 : 0;
    if (!wcscmp(key, L"blockMove")) return g.blockMove ? 1 : 0;
    if (!wcscmp(key, L"fadeStart")) return g.fadeStart;
    if (!wcscmp(key, L"fadeEnd")) return g.fadeEnd;
    // task 4: 贴边隐藏
    if (!wcscmp(key, L"hideMode")) return g.hideMode;
    if (!wcscmp(key, L"hideEdge")) return g.hideMode == 1 ? 1 : 0;
    if (!wcscmp(key, L"wakeExt")) return g.wakeExt;
    if (!wcscmp(key, L"wakeVisible")) return g.wakeVisible ? 1 : 0;
    if (!wcscmp(key, L"wakeMode")) return g.wakeModeHover ? 1 : 0;
    if (!wcscmp(key, L"hue")) return 0;      // edited as swatches, not as a number
    return 0;
}

static int TrayKeyVal(const wchar_t* key) {
    if (!wcscmp(key, L"radius")) return g_trayBar.radiusOv;
    if (!wcscmp(key, L"pad")) return g_trayBar.padOv;
    if (!wcscmp(key, L"gap")) return g_trayBar.gapOv;
    // H2 float-style rows: -1 = inherit [dock]
    if (!wcscmp(key, L"bgMode")) return GetInt(L"traybar", L"bgMode", -1);
    if (!wcscmp(key, L"glassLayer")) return GetInt(L"traybar", L"glassLayer", -1);
    if (!wcscmp(key, L"color")) return GetInt(L"traybar", L"color", -1);
    if (!wcscmp(key, L"solidOpacity")) return GetInt(L"traybar", L"solidOpacity", -1);
    // task 3: the companion's own snap switch
    if (!wcscmp(key, L"snap")) return GetInt(L"traybar", L"snap", -1);
    return -1;
}

// The cadence keys are one machine-wide config, reachable from *every* glass window's page
// (user, 2026-11-21: "共享的不应该只在某个窗口显示 ... 相当于只有一个配置，但是多处可改配置").
// They always read and write [dock], whichever window's page is open.
static bool IsSharedGlassKey(const wchar_t* key) {
    return !wcscmp(key, L"refreshHz") || !wcscmp(key, L"captureHz") ||
           !wcscmp(key, L"captureBudgetMs") || !wcscmp(key, L"dragNoCapture");
}

static int PageVal(int i) {
    const SPage* p = ActivePage();
    if (!p || i < 0 || i >= p->count) return 0;
    const SRow& row = p->rows[i];
    if (row.colorAlpha) return TintAlpha();
    if (p->kind == kPageGroupKind) {
        Group* g = GroupById(p->groupId);
        return g ? GroupKeyVal(*g, row.key) : 0;
    }
    if (p->kind == kPageFloatTray) {
        int v = TrayKeyVal(row.key);
        // A two-pill toggle cannot express "inherit", so show the value actually in force
        // instead of the raw -1 - otherwise an inheriting row reads 关 while the strip's 开 is
        // what the window is doing (task 3; same trap as SRow::defv on the strip's pages).
        if (v < 0 && row.isToggle) return GetInt(L"dock", row.key, row.defv);
        return v;
    }
    if (IsSharedGlassKey(row.key)) return GetInt(L"dock", row.key, row.minv);
    return GetInt(p->section.c_str(), row.key, row.minv < 0 ? -1 : row.defv);
}

static void PageLoad() {
    const SPage* p = ActivePage();
    g_rowVal.assign(p ? p->count : 0, 0);
    for (int i = 0; i < (int)g_rowVal.size(); i++) {
        int v = PageVal(i);
        if (v < p->rows[i].minv) v = p->rows[i].minv;
        if (v > p->rows[i].maxv) v = p->rows[i].maxv;
        g_rowVal[i] = v;
    }
}

// Re-applies everything a strip-page row can affect. Kept in one place because the strip's
// layout, the companions' icon sizes and the group frame all derive from g_cfg.
static void ApplyStripStyle() {
    LoadConfig();
    // task 3: [dock] snap may have just changed; recompute the targets right away (the corners
    // animate back in the next frames, see AnimateCorners).
    UpdateSnap();
    g_glassCacheValid = false;
    g_bakeDirty = true;
    RECT rc{};
    GetClientRect(g_hwnd, &rc);
    Paint(rc.right, rc.bottom);
    Present();
    ComputeButtons();
    PaintAndPresent();
    if (g_trayBar.hwnd) {
        TrayRepaint(g_trayBar);
        CompanionPresent(g_trayBar);
        GroupRecompute(DefaultGroup());
    }
}

static void PageSet(int i, int v) {
    SPage* p = nullptr;
    if (g_page >= 0 && g_page < (int)g_pages.size()) p = &g_pages[g_page];
    if (!p || i < 0 || i >= p->count) return;
    const SRow& row = p->rows[i];
    wchar_t buf[64]{};
    if (row.colorAlpha) {
        DWORD tint = (g_cfg.tint & 0x00FFFFFF) | ((DWORD)v << 24);
        swprintf_s(buf, L"#%08X", tint);
        WritePrivateProfileStringW(p->section.c_str(), L"tint", buf, g_iniPath.c_str());
    } else {
        swprintf_s(buf, L"%d", v);
        // the shared cadence keys always live in [dock], whichever window's page changed them
        const wchar_t* sec = IsSharedGlassKey(row.key) ? L"dock" : p->section.c_str();
        if (p->kind != kPageGroupKind)  // group pages persist through GroupSaveFlag
            WritePrivateProfileStringW(sec, row.key, buf, g_iniPath.c_str());
    }

    // Switching the background to "picture" applies the last picture that was used, so the window
    // never goes blank just because this section has no `image=` yet (user, 2026-11-21).
    if (!wcscmp(row.key, L"bgMode") && v == 1 && p->kind != kPageGroupKind) {
        std::vector<wchar_t> cur(MAX_PATH * 2, 0);
        GetPrivateProfileStringW(p->section.c_str(), L"image", L"", cur.data(), (DWORD)cur.size(),
                                 g_iniPath.c_str());
        if (!cur[0]) {
            const std::wstring last = GalleryNewest();
            if (!last.empty()) WriteImagePath(p->section, last);
        }
    }

    switch (p->kind) {
        case kPageGlass: {
            LoadConfig();
            g_glassCacheValid = false;
            if (!wcscmp(row.key, L"blurRadius") || !wcscmp(row.key, L"material"))
                g_bakeDirty = true;
            if (!wcscmp(row.key, L"refreshHz") || !wcscmp(row.key, L"captureHz")) {
                // write the *clamped* capture rate back (it can never exceed the refresh rate)
                if (g_rowVal[i] != g_cfg.captureHz) {
                    for (int r = 0; r < p->count; r++) {
                        if (!wcscmp(p->rows[r].key, L"captureHz")) {
                            g_rowVal[r] = g_cfg.captureHz;
                            wchar_t b2[32]{};
                            swprintf_s(b2, L"%d", g_cfg.captureHz);
                            WritePrivateProfileStringW(L"dock", L"captureHz", b2,
                                                       g_iniPath.c_str());
                        }
                    }
                }
                ArmRepaintTimer(g_hwnd);
            }
            RECT rc{};
            GetClientRect(g_hwnd, &rc);
            Paint(rc.right, rc.bottom);
            Present();
            // Per-window glass parameters: the picture composition bakes the blur in, and a
            // companion keeps its own bake, so both invalidate and repaint here.
            if (!wcscmp(p->section.c_str(), L"traybar")) {
                g_imgTray.sig = 0;
                g_trayBar.glass.dirty = true;
                g_trayBar.glassSig = 0;
                if (g_trayBar.hwnd) {
                    TrayRepaint(g_trayBar);
                    CompanionPresent(g_trayBar);
                }
            } else {
                g_imgStrip.sig = 0;
            }
            break;
        }
        case kPageFloatDock:
        case kPageBar:
            ApplyStripStyle();
            break;
        case kPageFloatTray: {
            int v2 = v;
            if (!wcscmp(row.key, L"radius")) g_trayBar.radiusOv = v2;
            else if (!wcscmp(row.key, L"pad")) g_trayBar.padOv = v2;
            else if (!wcscmp(row.key, L"gap")) g_trayBar.gapOv = v2;
            // task 3: the snap override; the animation starts on the next tick (120 ms)
            else if (!wcscmp(row.key, L"snap")) g_trayBar.snapOv = v2;
            if (g_trayBar.hwnd) {
                TrayRepaint(g_trayBar);
                CompanionPresent(g_trayBar);
                if (Group* g = GroupById(g_trayBar.groupId)) GroupRecompute(*g);
            }
            break;
        }
        case kPageGroupKind: {
            Group* g = GroupById(p->groupId);
            if (!g) break;
            if (!wcscmp(row.key, L"enabled")) {
                g->enabled = v != 0;
                GroupSaveFlag(*g, L"enabled", g->enabled);
                GroupRepaint(*g);
            } else if (!wcscmp(row.key, L"lineAlpha")) {
                g->lineAlpha = v;
                swprintf_s(buf, L"%d", v);
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                WritePrivateProfileStringW(sec, L"lineAlpha", buf, g_iniPath.c_str());
                GroupRepaint(*g);
            } else if (!wcscmp(row.key, L"lineWidth")) {
                g->lineWidth = v;
                swprintf_s(buf, L"%d", v);
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                WritePrivateProfileStringW(sec, L"lineWidth", buf, g_iniPath.c_str());
                GroupRepaint(*g);
            } else if (!wcscmp(row.key, L"margin")) {
                g->margin = v;
                swprintf_s(buf, L"%d", v);
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                WritePrivateProfileStringW(sec, L"margin", buf, g_iniPath.c_str());
                GroupRecompute(*g);
            } else if (!wcscmp(row.key, L"radius")) {
                g->radius = v;
                swprintf_s(buf, L"%d", v);
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                WritePrivateProfileStringW(sec, L"radius", buf, g_iniPath.c_str());
                GroupRepaint(*g);
            } else if (!wcscmp(row.key, L"blockResize")) {
                g->blockResize = v != 0;
                GroupSaveFlag(*g, L"blockResize", g->blockResize);
            } else if (!wcscmp(row.key, L"blockMove")) {
                g->blockMove = v != 0;
                GroupSaveFlag(*g, L"blockMove", g->blockMove);
            } else if (!wcscmp(row.key, L"fadeStart") || !wcscmp(row.key, L"fadeEnd")) {
                // H2b: the fade distances are the group's; they only feed the per-tick alpha
                // computation, so no repaint is needed here.
                const bool isStart = !wcscmp(row.key, L"fadeStart");
                if (isStart) g->fadeStart = v; else g->fadeEnd = v;
                if (g->fadeEnd <= g->fadeStart) g->fadeEnd = g->fadeStart + 1;
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                swprintf_s(buf, L"%d", isStart ? g->fadeStart : g->fadeEnd);
                WritePrivateProfileStringW(sec, row.key, buf, g_iniPath.c_str());
            } else if (!wcscmp(row.key, L"hideMode")) {
                // 隐藏方案: 0 距离淡出 / 1 贴边隐藏 / 2 从不. Leaving 贴边隐藏 slides the group back
                // in; entering it glues it to the nearest edge right away.
                g->hideMode = v;
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                swprintf_s(buf, L"%d", v);
                WritePrivateProfileStringW(sec, L"hideMode", buf, g_iniPath.c_str());
                HideEdgeSet(*g, v == 1);
                GroupRecompute(*g);
                GroupRepaint(*g);
            } else if (!wcscmp(row.key, L"wakeExt")) {
                g->wakeExt = v;
                wchar_t sec[32];
                GroupSectionName(g->id, sec, 32);
                swprintf_s(buf, L"%d", v);
                WritePrivateProfileStringW(sec, L"wakeExt", buf, g_iniPath.c_str());
                // "调完 x" flashes the band twice, in both visibility modes
                g->hideFlashStart = GetTickCount();
                g->hideFlashUntil = g->hideFlashStart + kHideFlashMs;
            } else if (!wcscmp(row.key, L"wakeVisible")) {
                g->wakeVisible = v != 0;
                GroupSaveFlag(*g, L"wakeVisible", g->wakeVisible);
            } else if (!wcscmp(row.key, L"wakeMode")) {
                g->wakeModeHover = v != 0;
                GroupSaveFlag(*g, L"wakeMode", g->wakeModeHover);
                HideWakeSetMode(*g);
            }
            break;
        }
        default:
            break;
    }
    PageLoad();
}

// GDI text into a 32bpp DIB leaves alpha at 0; render white text on black and
// rebuild the alpha from luminance, then composite with premultiplied maths.
static void DrawTextAlpha(int x, int y, int w, int h, const std::wstring& text, int px,
                          DWORD rgb) {
    if (!g_paintBits || w <= 0 || h <= 0) return;
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
            a = a * 5 / 2;                        // thin antialiased edges were vanishing
            if (a > 255) a = 255;
            if (a <= 6) continue;
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

// Tab geometry: equal slices across the panel, one per page.
static RECT TabRect(int i, int count) {
    int x0 = 26, x1 = g_setW - 26;
    int w = count > 0 ? (x1 - x0) / count : 0;
    return RECT{x0 + i * w, 64, x0 + (i + 1) * w - 6, 64 + kTabH};
}

// The panel is as tall as its current page: a 3-row page in a 9-row frame looks broken.
static void SettingsFreeDib() {
    if (g_setBmp) {
        if (g_setDC) SelectObject(g_setDC, GetStockObject(NULL_BRUSH));
        DeleteObject(g_setBmp);
        g_setBmp = nullptr;
    }
    if (g_setDC) {
        DeleteDC(g_setDC);
        g_setDC = nullptr;
    }
    g_setBits = nullptr;
}

static void SettingsResizeForPage() {
    const SPage* p = ActivePage();
    int rows = 0;
    if (p) {
        for (int i = 0; i < p->count; i++)
            if (SettingsRowVisible(p, i)) rows++;
    }
    if (rows < 1) rows = 1;
    g_setH = kRowsTop + rows * kRowH + 56;
    SettingsFreeDib();
    if (g_setWnd)
        SetWindowPos(g_setWnd, nullptr, 0, 0, g_setW, g_setH,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

// ---- picture gallery (H3 image backgrounds) --------------------------------------------
// The gallery is a plain folder next to dock.ini. We never list or manage it in code: Explorer is
// the manager (rename/delete/move = the user's own file manager, no UI from us). Only two
// operations touch it - "+" copies a chosen picture in, and the clock picks one already there.
static std::wstring GalleryDir() {
    std::wstring dir = g_iniPath;
    size_t slash = dir.find_last_of(L"\\/");
    if (slash != std::wstring::npos) dir.resize(slash + 1);
    else dir.clear();
    dir += L"backgrounds";
    CreateDirectoryW(dir.c_str(), nullptr);
    return dir;
}

static bool IsImageFile(const std::wstring& path) {
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos) return false;
    std::wstring ext = path.substr(dot);
    for (auto& c : ext) c = (wchar_t)towlower(c);
    return ext == L".png" || ext == L".jpg" || ext == L".jpeg" || ext == L".bmp" ||
           ext == L".webp";
}

// Newest picture in the gallery, or "" when there is none.
static std::wstring GalleryNewest() {
    const std::wstring dir = GalleryDir();
    std::wstring best;
    ULARGE_INTEGER bestAt{};
    bestAt.QuadPart = 0;
    WIN32_FIND_DATAW fd{};
    const wchar_t* pats[] = {L"\\*.png", L"\\*.jpg", L"\\*.jpeg", L"\\*.bmp", L"\\*.webp"};
    for (const wchar_t* pat : pats) {
        HANDLE h = FindFirstFileW((dir + pat).c_str(), &fd);
        if (h == INVALID_HANDLE_VALUE) continue;
        do {
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            ULARGE_INTEGER at{};
            at.LowPart = fd.ftLastWriteTime.dwLowDateTime;
            at.HighPart = fd.ftLastWriteTime.dwHighDateTime;
            if (at.QuadPart > bestAt.QuadPart) {
                bestAt = at;
                best = dir + L"\\" + fd.cFileName;
            }
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    return best;
}

// Copy a picture into the gallery (unless it is already there) and return the gallery path.
static std::wstring CopyIntoGallery(const std::wstring& src) {
    const std::wstring dir = GalleryDir();
    const std::wstring lowerSrc = Lower(src), lowerDir = Lower(dir);
    if (lowerSrc.rfind(lowerDir, 0) == 0) return src;       // already inside: nothing to do
    size_t slash = src.find_last_of(L"\\/");
    std::wstring name = slash == std::wstring::npos ? src : src.substr(slash + 1);
    std::wstring dst = dir + L"\\" + name;
    for (int n = 2; n < 100; n++) {
        if (GetFileAttributesW(dst.c_str()) == INVALID_FILE_ATTRIBUTES) break;
        size_t dot = name.find_last_of(L'.');
        wchar_t suffix[16]{};
        swprintf_s(suffix, L"-%d", n);
        dst = dir + L"\\" + (dot == std::wstring::npos ? name + suffix
                                                       : name.substr(0, dot) + suffix + name.substr(dot));
    }
    if (!CopyFileW(src.c_str(), dst.c_str(), TRUE)) {
        DLog(L"gallery: copy %s -> %s failed (%lu)", src.c_str(), dst.c_str(), GetLastError());
        return src;                                          // still usable in place
    }
    DLog(L"gallery: added %s", dst.c_str());
    return dst;
}

static bool PickImageFile(HWND owner, const std::wstring& startDir, std::wstring* out) {
    IFileOpenDialog* dlg = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IFileOpenDialog, (void**)&dlg)))
        return false;
    COMDLG_FILTERSPEC types[] = {{L"图片", L"*.png;*.jpg;*.jpeg;*.bmp;*.webp"}};
    dlg->SetFileTypes(1, types);
    dlg->SetTitle(startDir.empty() ? L"选择背景图片" : L"从图库选择背景图片");
    if (!startDir.empty()) {
        IShellItem* folder = nullptr;
        if (SUCCEEDED(SHCreateItemFromParsingName(startDir.c_str(), nullptr, IID_IShellItem,
                                                  (void**)&folder))) {
            dlg->SetFolder(folder);
            folder->Release();
        }
    }
    bool ok = false;
    if (SUCCEEDED(dlg->Show(owner))) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(dlg->GetResult(&item))) {
            PWSTR path = nullptr;
            if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
                *out = path;
                CoTaskMemFree(path);
                ok = true;
            }
            item->Release();
        }
    }
    dlg->Release();
    return ok;
}

static void WriteImagePath(const std::wstring& section, const std::wstring& path) {
    WritePrivateProfileStringW(section.c_str(), L"image", path.c_str(), g_iniPath.c_str());
    DLog(L"image: %s image=%s", section.c_str(), path.c_str());
}

// "Choose a picture from the gallery" (clock). An empty gallery opens Explorer at the folder so
// the user can see/manage it - there is nothing to pick yet.
static void SettingsPickFromGallery() {
    const SPage* p = ActivePage();
    if (!p || g_pickBusy) return;
    const std::wstring dir = GalleryDir();
    if (GalleryNewest().empty()) {
        g_pickBusy = true;
        ShellExecuteW(nullptr, L"open", dir.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
        g_pickBusy = false;
        DLog(L"gallery: empty - opened %s", dir.c_str());
        return;
    }
    std::wstring picked;
    g_pickBusy = true;
    const bool got = PickImageFile(g_setWnd, dir, &picked);
    g_pickBusy = false;
    if (!got) return;
    WriteImagePath(p->section, picked);
    LoadConfig();
    SettingsPaint();
}

// An ini edit (Reload) must reach the float window too: its picture composition is cached by
// (picture, size, glass params) and its glass bake is a separate target, so nothing would repaint
// it until it happened to appear again (found 2026-11-21 while testing per-window parameters).
static void RefreshCompanionAfterReload() {
    g_glassCacheValid = false;
    g_imgStrip.sig = 0;      // force a re-compose with the new parameters
    g_imgTray.sig = 0;
    g_trayBar.glass.dirty = true;
    // task 3: the snap override is read from the ini like the other style keys, and a hand edit
    // followed by a reload (dev/t_dock_reload.ps1) should apply without a restart. The geometry
    // itself is NOT re-read here - a reload must never yank the window somewhere else.
    g_trayBar.snapOv = GetInt(g_trayBar.iniSection, L"snap", -1);
    CompanionSnapUpdate(g_trayBar);
    if (!g_trayBar.hwnd) return;
    TrayRepaint(g_trayBar);
    CompanionPresent(g_trayBar);
}

// Task 4: a group has no tone of its own, so it carries one for its 唤出区域. `which` is
// 0 = strip, 1 = companion, 2 = the group whose page is open (g_hueGroup); an unset group falls
// back to the strip's tone so the band never looks out of place.
static int g_hueGroup = 1;

static DWORD HueFor(int which) {
    if (which == 2) {
        Group* g = GroupById(g_hueGroup);
        return (g && g->hasHue) ? g->hue : g_hue[0];
    }
    return g_hue[which & 1];
}

// Apply one window's 色调 and persist it (`[dock] hue` / `[traybar] hue` / `[group.N] hue`).
static void SetHueFor(int which, DWORD rgb) {
    rgb &= 0x00FFFFFFu;
    if (which == 2) {
        Group* g = GroupById(g_hueGroup);
        if (!g) return;
        g->hue = rgb;
        g->hasHue = true;
        wchar_t sec[32];
        GroupSectionName(g->id, sec, 32);
        wchar_t b[16]{};
        swprintf_s(b, L"#%06X", rgb);
        WritePrivateProfileStringW(sec, L"hue", b, g_iniPath.c_str());
        DLog(L"hue: %s = #%06X (group wake band)", sec, rgb);
        // flash it so the new colour is actually visible - the band is not painted while the
        // group is awake, so without this "调颜色" looks like it does nothing (user, 2026-11-23)
        g->hideFlashStart = GetTickCount();
        g->hideFlashUntil = g->hideFlashStart + kHideFlashMs;
        return;      // the band re-reads it on the next tick, see HideWakePresent
    }
    g_hue[which & 1] = rgb;
    wchar_t b[16]{};
    swprintf_s(b, L"#%06X", rgb);
    WritePrivateProfileStringW(which == 0 ? L"dock" : L"traybar", L"hue", b, g_iniPath.c_str());
    // Both the glass tint and the solid colour come from this, so refresh that window now.
    if (which == 0) {
        ApplyStripStyle();                       // reloads the config and repaints the strip
    } else if (g_trayBar.hwnd) {
        g_trayBar.glass.dirty = true;            // the tint is baked -> needs one new bake
        TrayRepaint(g_trayBar);
        CompanionPresent(g_trayBar);
    }
    DLog(L"hue: %s = #%06X", which == 0 ? L"dock" : L"traybar", rgb);
}

// The free colour picker (the palette chip). Modal, so it runs from the queued message.
static void PickHue(int which) {
    if (g_pickBusy) return;
    static COLORREF custom[16]{};
    CHOOSECOLORW cc{};
    cc.lStructSize = sizeof(cc);
    cc.hwndOwner = g_setWnd;
    cc.lpCustColors = custom;
    const DWORD h = HueFor(which);
    cc.rgbResult = RGB((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF);
    cc.Flags = CC_FULLOPEN | CC_RGBINIT;
    g_pickBusy = true;
    const BOOL ok = ChooseColorW(&cc);
    g_pickBusy = false;
    if (!ok) return;
    SetHueFor(which, ((DWORD)GetRValue(cc.rgbResult) << 16) |
                         ((DWORD)GetGValue(cc.rgbResult) << 8) | (DWORD)GetBValue(cc.rgbResult));
    SettingsPaint();
}

// "Add a picture" (+): pick from anywhere, copy it into the gallery, make it the background.
static void SettingsPickNewImage() {    const SPage* p = ActivePage();
    if (!p || g_pickBusy) return;
    std::wstring picked;
    g_pickBusy = true;
    const bool got = PickImageFile(g_setWnd, std::wstring(), &picked);
    g_pickBusy = false;
    if (!got) return;
    WriteImagePath(p->section, CopyIntoGallery(picked));
    LoadConfig();
    SettingsPaint();
}

// A picture row is only meaningful while the background *is* a picture.
static bool SettingsRowVisible(const SPage* p, int i) {
    if (!p || i < 0 || i >= p->count) return false;
    const wchar_t* key = p->rows[i].key;
    // 隐藏方案 decides which of the two sub-groups of rows exist (user, 2026-11-23):
    //   鼠标距离 -> only the two fade distances
    //   贴边隐藏 -> only the wake-band rows (its colour included)
    //   从不     -> nothing else
    if (p->kind == kPageGroupKind) {
        Group* g = GroupById(p->groupId);
        const int mode = g ? g->hideMode : 0;
        if (!wcscmp(key, L"fadeStart") || !wcscmp(key, L"fadeEnd")) return mode == 0;
        if (!wcscmp(key, L"wakeExt") || !wcscmp(key, L"wakeVisible") ||
            !wcscmp(key, L"wakeMode") || !wcscmp(key, L"hue"))
            return mode == 1;
    }
    if (wcscmp(key, L"image")) return true;
    int bg = 0;
    if (p->kind == kPageFloatTray) bg = TrayKeyVal(L"bgMode");
    else bg = GetInt(p->section.c_str(), L"bgMode", 0);
    return bg == 1;
}

// Rows that contradict the current background are shown greyed and cannot be switched
// (user, 2026-11-21: "选中纯色时玻璃层强制改到关并且不能切换" + the same class of dead setting).
static bool SettingsRowDisabled(const SPage* p, int i) {
    if (!p || i < 0 || i >= p->count) return false;
    const wchar_t* key = p->rows[i].key;
    if (p->kind == kPageGlass) {
        // Shared cadence rows: adjustable wherever *this* window actually bakes a screen backdrop;
        // locked (but still visible) for a picture background, which needs no captures at all.
        // Blur and opacity stay live everywhere - on a picture the blur hits the sharp layer and
        // the opacity is the whole background layer.
        if (IsSharedGlassKey(key)) {
            int bg = 0;
            if (!wcscmp(p->section.c_str(), L"traybar")) {
                bg = GetInt(L"traybar", L"bgMode", -1);      // -1 = inherit the strip's
                if (bg < 0 || bg > 2) bg = g_cfg.bgMode;
            } else {
                bg = GetInt(p->section.c_str(), L"bgMode", 0);
            }
            return bg != 0;
        }
        return false;
    }
    int bg = 0;
    if (p->kind == kPageFloatTray) bg = TrayKeyVal(L"bgMode");
    else bg = GetInt(p->section.c_str(), L"bgMode", 0);
    if (!wcscmp(key, L"glassLayer")) return bg == 2;        // solid has no glass material
    if (!wcscmp(key, L"solidOpacity")) return bg != 2;
    if (!wcscmp(key, L"image")) return bg != 1;
    return false;
}

static void SettingsPaint() {
    if (!g_setWnd) return;
    // The visible row set can change while the panel is open (the picture row only exists while
    // the background *is* a picture), so re-fit the window before drawing - otherwise the last
    // row gets clipped.
    {
        const SPage* pv = ActivePage();
        int want = 0;
        if (pv)
            for (int i = 0; i < pv->count; i++)
                if (SettingsRowVisible(pv, i)) want++;
        if (want < 1) want = 1;
        if (g_setH != kRowsTop + want * kRowH + 56) SettingsResizeForPage();
        // task 4: while a group's page is open its wake band is painted faintly, so the width and
        // colour rows have a visible effect at all (see HideEdgeTick).
        g_previewGroupId = (pv && pv->kind == kPageGroupKind) ? pv->groupId : 0;
    }
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
    g_paintBits = g_setBits; g_paintW = g_setW; g_paintH = g_setH;

    // panel body: same rounded, translucent treatment as the dock
    int panelR = 18;
    FillRound(g_setDC, RECT{0, 0, g_setW, g_setH}, panelR, 0xE61C1C1C);
    FillRound(g_setDC, RECT{1, 1, g_setW - 1, g_setH - 1}, panelR, 0x1AFFFFFF);

    DrawTextAlpha(26, 22, 340, 40, L"dock 设置", 30, 0xFFFFFF);
    DrawTextAlpha(g_setW - 62, 18, 44, 44, L"×", 32, 0xFFFFFFFF);

    // tabs
    int count = (int)g_pages.size();
    for (int i = 0; i < count; i++) {
        RECT tr = TabRect(i, count);
        bool active = (i == g_page);
        FillRound(g_setDC, tr, 10, active ? 0xFF4C9AFF : 0x24FFFFFF);
        DrawTextAlpha(tr.left + 14, tr.top, tr.right - tr.left - 20, tr.bottom - tr.top,
                      g_pages[i].title, 20, active ? 0xFFFFFFFF : 0xC8FFFFFF);
    }

    const SPage* p = ActivePage();
    if (!p) {
        g_paintBits = g_bits; g_paintW = g_dibW; g_paintH = g_dibH;
        return;
    }
    int y = kRowsTop;
    for (int i = 0; i < p->count; i++) {
        const SRow& row = p->rows[i];
        if (!SettingsRowVisible(p, i)) continue;      // e.g. the picture row outside image mode
        const bool dis = SettingsRowDisabled(p, i);
        DrawTextAlpha(30, y, 330, 46, row.label, 24, dis ? 0x5AFFFFFF : 0xF4FFFFFF);
        if (!wcscmp(row.key, L"image")) {
            // The picture row: current file name, then two square buttons - clock = pick from the
            // gallery, + = add a new picture (and copy it in).
            std::wstring cur = ImagePathFor(p->section == L"traybar" ? L"traybar" : L"dock");
            std::wstring name = cur;
            size_t slash = cur.find_last_of(L"\\/");
            if (slash != std::wstring::npos) name = cur.substr(slash + 1);
            if (name.empty()) name = L"（未设置）";
            if (name.size() > 26) name = name.substr(0, 24) + L"…";
            DrawTextAlpha(g_setW - 470, y, 300, 46, name, 19, 0xC8FFFFFF);
            const int bs = 34;
            RECT clock{g_setW - 156, y + 8, g_setW - 156 + bs, y + 8 + bs};
            RECT plus{clock.right + 12, y + 8, clock.right + 12 + bs, y + 8 + bs};
            for (const RECT& b : {clock, plus}) {
                FillRound(g_setDC, b, 9, 0x30FFFFFF);
            }
            // clock glyph: circle + two hands
            int ccx = (clock.left + clock.right) / 2, ccy = (clock.top + clock.bottom) / 2;
            for (int a = 0; a < 360; a += 6) {
                double r = 10.0;
                SetPixelPremul(ccx + (int)(r * cos(a * 3.14159265 / 180)),
                               ccy + (int)(r * sin(a * 3.14159265 / 180)), 0xE0FFFFFF);
            }
            DrawLine(ccx, ccy, ccx, ccy - 6, 2, 0xFFFFFFFF);
            DrawLine(ccx, ccy, ccx + 5, ccy + 2, 2, 0xFFFFFFFF);
            // plus glyph
            int pcx = (plus.left + plus.right) / 2, pcy = (plus.top + plus.bottom) / 2;
            DrawLine(pcx - 8, pcy, pcx + 8, pcy, 2, 0xFFFFFFFF);
            DrawLine(pcx, pcy - 8, pcx, pcy + 8, 2, 0xFFFFFFFF);
            y += kRowH;
            continue;
        }
        if (!wcscmp(row.key, L"hue")) {
            // 8 preset chips + a palette chip (opens the Windows colour picker).
            // 0 = the strip, 1 = the companion, 2 = the group whose page this is (task 4).
            const int which = (p->kind == kPageFloatTray) ? 1 : (p->kind == kPageGroupKind ? 2 : 0);
            const DWORD cur = HueFor(which) & 0x00FFFFFFu;
            const int cs = 26, gap = 9;
            int hx = 370;
            for (int k = 0; k < kHueCount; k++) {
                RECT chip{hx, y + 16, hx + cs, y + 16 + cs};
                const bool on = (cur == kHuePresets[k]);
                RECT ring{chip.left - (on ? 3 : 2), chip.top - (on ? 3 : 2),
                          chip.right + (on ? 3 : 2), chip.bottom + (on ? 3 : 2)};
                FillRound(g_setDC, ring, on ? 11 : 10, on ? 0xFFFFFFFF : 0x30FFFFFF);
                FillRound(g_setDC, chip, 8, 0xFF000000u | kHuePresets[k]);
                hx += cs + gap;
            }
            RECT pc{hx, y + 16, hx + cs, y + 16 + cs};
            FillRound(g_setDC, pc, 8, 0x30FFFFFF);
            const int mx = (pc.left + pc.right) / 2, my = (pc.top + pc.bottom) / 2;
            FillRound(g_setDC, RECT{pc.left + 3, pc.top + 3, mx, my}, 4, 0xFFE85D75);
            FillRound(g_setDC, RECT{mx, pc.top + 3, pc.right - 3, my}, 4, 0xFFF2C14E);
            FillRound(g_setDC, RECT{pc.left + 3, my, mx, pc.bottom - 3}, 4, 0xFF5DB3E8);
            FillRound(g_setDC, RECT{mx, my, pc.right - 3, pc.bottom - 3}, 4, 0xFF6FCF97);
            y += kRowH;
            continue;
        }
        const bool isChoiceRow = (row.choices && row.choiceCount > 0);
        if (!row.isToggle && !isChoiceRow) {
            wchar_t val[32]{};
            if (g_rowVal[i] < 0) wcscpy_s(val, L"继承");
            else swprintf_s(val, L"%d", g_rowVal[i]);
            DrawTextAlpha(g_setW - 150, y, 120, 46, val, 24, dis ? 0x5AFFFFFF : 0xFFFFFFFF);
        }

        int tx = 370, tw = g_setW - 370 - 170;
        int ty = y + 20;
        if (row.choices && row.choiceCount > 0) {
            // N-way choice (H2): one pill per value, left to right.
            const int n = row.choiceCount;
            const int seg = tw / n;
            for (int k = 0; k < n; k++) {
                bool on = (g_rowVal[i] == k);
                RECT pr{tx + k * seg, ty - 14, tx + (k + 1) * seg - 6, ty + 16};
                FillRound(g_setDC, pr, 8, dis ? 0x14FFFFFF : (on ? 0xFF4C9AFF : 0x30FFFFFF));
                DrawTextAlpha(tx + k * seg + 10, ty - 22, seg - 16, 44, row.choices[k], 19,
                              dis ? 0x50FFFFFF : (on ? 0xFFFFFFFF : 0xC0FFFFFF));
            }
        } else if (row.isToggle) {
            int half = tw / 2;
            // A disabled toggle always reads "关": that is the only state the window can be in.
            const int shown = dis ? 0 : g_rowVal[i];
            for (int k = 0; k < 2; k++) {
                bool on = (shown == (k == 0 ? 1 : 0));
                RECT pr{tx + k * half, ty - 14, tx + (k + 1) * half - 6, ty + 16};
                FillRound(g_setDC, pr, 8, dis ? 0x14FFFFFF : (on ? 0xFF4C9AFF : 0x30FFFFFF));
            }
            bool leftOn = (shown == 1);
            const wchar_t* lt = row.onText ? row.onText : L"开";
            const wchar_t* rt = row.offText ? row.offText : L"关";
            DrawTextAlpha(tx + 18, ty - 22, half - 30, 44, lt, 20,
                          dis ? 0x50FFFFFF : (leftOn ? 0xFFFFFFFF : 0xC0FFFFFF));
            DrawTextAlpha(tx + half + 18, ty - 22, half - 30, 44, rt, 20,
                          dis ? 0x90FFFFFF : (leftOn ? 0xC0FFFFFF : 0xFFFFFFFF));
        } else {
            FillRound(g_setDC, RECT{tx, ty, tx + tw, ty + 6}, 3, 0x40FFFFFF);
            double frac = (row.maxv > row.minv)
                              ? (double)(g_rowVal[i] - row.minv) / (row.maxv - row.minv)
                              : 0.0;
            if (frac < 0) frac = 0;
            if (frac > 1) frac = 1;
            int px = tx + (int)(frac * tw);
            FillRound(g_setDC, RECT{tx, ty, px, ty + 6}, 3, dis ? 0x30FFFFFF : 0xFF4C9AFF);
            FillRound(g_setDC, RECT{px - 8, ty - 5, px + 8, ty + 11}, 8,
                      dis ? 0x40FFFFFF : 0xFFFFFFFF);
        }
        y += kRowH;
    }

    g_paintBits = g_bits; g_paintW = g_dibW; g_paintH = g_dibH;
    BLENDFUNCTION bf{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    SIZE size{g_setW, g_setH};
    POINT srcPt{0, 0};
    UpdateLayeredWindow(g_setWnd, nullptr, nullptr, &size, g_setDC, &srcPt, 0, &bf, ULW_ALPHA);
}

static int RowAt(int y) {
    const SPage* p = ActivePage();
    if (!p) return -1;
    int yy = kRowsTop;
    for (int i = 0; i < p->count; i++) {
        if (!SettingsRowVisible(p, i)) continue;      // hidden rows take no space either
        if (y >= yy && y < yy + kRowH) return i;
        yy += kRowH;
    }
    return -1;
}

static void RowFromX(int i, int x) {
    const SPage* p = ActivePage();
    if (!p || i < 0 || i >= p->count) return;
    const SRow& row = p->rows[i];
    if (SettingsRowDisabled(p, i)) return;        // greyed rows are not clickable on purpose
    int tx = 370, tw = g_setW - 370 - 170;
    if (!wcscmp(row.key, L"image")) {
        // The two buttons of the picture row: clock = gallery, + = add a new picture.
        int y = kRowsTop;
        for (int k = 0; k < i; k++)
            if (SettingsRowVisible(p, k)) y += kRowH;
        const int bs = 34;
        const int clockL = g_setW - 156, plusL = clockL + bs + 12;
        int action = 0;
        if (x >= clockL && x < clockL + bs) action = 1;
        else if (x >= plusL && x < plusL + bs) action = 2;
        // Queued, not called: see kSetMsgPickImage.
        if (action && !g_pickBusy && !g_setPickAction) {
            g_setPickAction = action;
            PostMessageW(g_setWnd, kSetMsgPickImage, 0, 0);
        }
        return;
    }
    if (!wcscmp(row.key, L"hue")) {
        int y = kRowsTop;
        for (int k = 0; k < i; k++)
            if (SettingsRowVisible(p, k)) y += kRowH;
        const int which = (p->kind == kPageFloatTray) ? 1 : (p->kind == kPageGroupKind ? 2 : 0);
        const int cs = 26, gap = 9;
        int hx = 370;
        for (int k = 0; k < kHueCount; k++) {
            if (x >= hx && x < hx + cs) {
                SetHueFor(which, kHuePresets[k]);     // no dialog: safe to run from here
                SettingsPaint();
                return;
            }
            hx += cs + gap;
        }
        if (x >= hx && x < hx + cs && !g_pickBusy && !g_setPickAction) {
            // the colour picker is modal -> queue it, same rule as the picture buttons
            g_setPickAction = 20 + which;
            PostMessageW(g_setWnd, kSetMsgPickImage, 0, 0);
        }
        return;
    }
    if (row.choices && row.choiceCount > 0) {
        const int n = row.choiceCount;
        const int seg = tw / n;
        int v = seg > 0 ? (x - tx) / seg : 0;
        if (v < 0) v = 0;
        if (v > n - 1) v = n - 1;
        if (v != g_rowVal[i]) {
            g_rowVal[i] = v;
            PageSet(i, v);
            SettingsPaint();
        }
        return;
    }
    if (row.isToggle) {
        int v = (x >= tx + tw / 2) ? 0 : 1;
        if (v != g_rowVal[i]) {
            g_rowVal[i] = v;
            PageSet(i, v);
            SettingsPaint();
        }
        return;
    }
    double frac = (double)(x - tx) / tw;
    if (frac < 0) frac = 0;
    if (frac > 1) frac = 1;
    int v = row.minv + (int)(frac * (row.maxv - row.minv) + 0.5);
    if (v != g_rowVal[i]) {
        g_rowVal[i] = v;
        PageSet(i, v);
        SettingsPaint();
    }
}

static LRESULT CALLBACK SettingsWndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case kSetMsgPickImage: {
            // The picture button's click is handled *here*, after the mouse message has returned,
            // so the modal dialog can never be re-entered by the click that opened it.
            const int action = g_setPickAction;
            g_setPickAction = 0;
            if (!g_pickBusy) {
                if (action == 1) SettingsPickFromGallery();
                else if (action == 2) SettingsPickNewImage();
                else if (action == 20 || action == 21 || action == 22) PickHue(action - 20);
            }
            return 0;
        }
        case WM_LBUTTONDOWN: {
            int mx = GET_X_LPARAM(lp), my = GET_Y_LPARAM(lp);
            if (mx >= g_setW - 66 && mx <= g_setW - 16 && my >= 12 && my <= 62) {  // the × glyph
                DestroyWindow(h);
                return 0;
            }
            // tabs first: clicking one switches the page and re-reads its values
            int count = (int)g_pages.size();
            for (int i = 0; i < count; i++) {
                RECT tr = TabRect(i, count);
                if (mx >= tr.left && mx < tr.right && my >= tr.top && my < tr.bottom) {
                    if (i != g_page) {
                        g_page = i;
                        PageLoad();
                        SettingsResizeForPage();
                        SettingsPaint();
                    }
                    return 0;
                }
            }
            int i = RowAt(my);
            if (i >= 0) {
                g_dragRow = i;
                SetCapture(h);
                RowFromX(i, mx);
            } else if (my > g_setH - 46) {
                DestroyWindow(h);
            }
            return 0;
        }
        case WM_MOUSEMOVE:
            if (g_dragRow >= 0) {
                // Only sliders follow the pointer. A toggle / choice / the picture row must not
                // repeat its action while the button is held (that is what looped the file dialog).
                const SPage* pg = ActivePage();
                if (pg && g_dragRow < pg->count) {
                    const SRow& rr = pg->rows[g_dragRow];
                    if (!rr.isToggle && !rr.choices && wcscmp(rr.key, L"image"))
                        RowFromX(g_dragRow, GET_X_LPARAM(lp));
                }
            }
            return 0;
        case WM_MOUSEWHEEL: {
            POINT p{};
            GetCursorPos(&p);
            ScreenToClient(h, &p);
            int i = RowAt(p.y);
            const SPage* pg = ActivePage();
            if (pg && i >= 0 && !pg->rows[i].isToggle) {
                int delta = GET_WHEEL_DELTA_WPARAM(wp) > 0 ? 1 : -1;
                int v = g_rowVal[i] + delta;
                if (v < pg->rows[i].minv) v = pg->rows[i].minv;
                if (v > pg->rows[i].maxv) v = pg->rows[i].maxv;
                if (v != g_rowVal[i]) {
                    g_rowVal[i] = v;
                    PageSet(i, v);
                    SettingsPaint();
                }
            }
            return 0;
        }
        case WM_LBUTTONUP:
            if (g_dragRow >= 0) {
                g_dragRow = -1;
                ReleaseCapture();
            }
            return 0;
        case WM_KEYDOWN:
            if (wp == VK_ESCAPE) DestroyWindow(h);
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

// H2: a companion's background / glass-layer choice. -1 in [traybar] = inherit from [dock],
// exactly like radius/pad/gap already do; the strip is always "its own".
static int CompanionBgMode(const Companion& c) {
    (void)c;
    int v = GetInt(L"traybar", L"bgMode", -1);
    if (v < 0 || v > 2) v = g_cfg.bgMode;
    return v;
}

static bool CompanionUsesGlass(const Companion& c) {
    int layer = GetInt(L"traybar", L"glassLayer", -1);
    if (layer != 0 && layer != 1) layer = g_cfg.glassLayer;
    return CompanionBgMode(c) == 0 && layer == 1;      // H3 gives it a real backdrop
}

// "Does this window *have* a glass layer?" - a different question from CompanionUsesGlass() above,
// which asks "does it bake a screen backdrop". A picture background has no backdrop to bake, but
// it does take the glass layer's tint, so its 玻璃 page exists (bug report 2026-11-21: 图片 + 玻璃层开
// 的窗口右键里没有玻璃页).
static bool CompanionHasGlassLayer(const Companion& c) {
    int layer = GetInt(L"traybar", L"glassLayer", -1);
    if (layer != 0 && layer != 1) layer = g_cfg.glassLayer;
    return layer == 1 && CompanionBgMode(c) != 2;      // solid has no glass material at all
}

// Does *any* window still bake a screen backdrop? If not, the glass page's blur / capture rows do
// nothing (a picture is tinted, a solid has no glass) and are greyed out.
static bool AnyScreenBackdrop() {
    if (g_cfg.material == 1) return true;
    if (g_trayBar.hwnd && CompanionUsesGlass(g_trayBar)) return true;
    return false;
}

// H3: the float window's backdrop refresh. Same rules as the strip (captureHz, a floor of 2x
// the measured cost, never mid-drag), plus the three things the plan asks for:
//  * a fully faded-out window costs nothing (alpha 0 -> no capture at all, §3.3.3);
//  * it draws the frame budget from the same pot as the strip (§3.3.2, see BakeGlass);
//  * a window smaller than the strip pays proportionally less - its padded rect is ~1/10 of
//    the strip's area, so the two together stay near the cost of one.
static void CompanionGlassTick(DWORD now) {
    Companion& c = g_trayBar;
    if (!c.hwnd || c.alpha <= 0) return;
    if (!IsWindowVisible(c.hwnd)) return;
    if (!CompanionUsesGlass(c)) {
        c.glass.dirty = false;      // nothing reads it: do not capture for it either
        return;
    }
    // A settings change (reload, colour, blur ...) must not wait for the next natural capture:
    // the bake has the lift/tint/opacity burned in, so it is wrong until re-made. The signature
    // is cheap to compare and needs no notification plumbing from the panel.
    const DWORD sig = g_hue[1] ^ ((DWORD)g_glass[1].tintStrength << 8) ^
                      ((DWORD)g_glass[1].glassOpacity << 16) ^ ((DWORD)g_glass[1].blurRadius << 20);
    if (sig != c.glassSig) {
        c.glassSig = sig;
        c.glass.dirty = true;
    }
    // "no glass" setting (opacity and tint both 0): the composite would only be a frozen copy
    if (g_glass[1].glassOpacity == 0 && g_glass[1].tintStrength == 0) return;
    // A window that moved only needs the *crop* to follow: the bake is anchored to the screen,
    // so re-painting from the new offset keeps the backdrop still while the window slides over
    // it. Only leaving the padded bake needs a new capture. This is what makes following the
    // strip through a drag cheap (a re-crop, ~0.5 ms) instead of a grab per frame (~15 ms).
    const bool justMoved = c.glassMovedAt != 0;
    if (justMoved && c.glass.valid && c.bits) {
        const int w = c.rc.right - c.rc.left, h = c.rc.bottom - c.rc.top;
        const int ox = c.rc.left - c.glass.origin.x, oy = c.rc.top - c.glass.origin.y;
        if (ox < 0 || oy < 0 || ox + w > c.glass.w || oy + h > c.glass.h) {
            c.glass.dirty = true;          // out of the padded bake: one capture is required
        } else {
            TrayRepaint(c);
            CompanionPresent(c);
        }
    }
    c.glassMovedAt = 0;
    if (g_cfg.captureHz <= 0) return;
    UINT capMs = (UINT)(1000 / g_cfg.captureHz);
    if (capMs < 1) capMs = 1;
    DWORD floorMs = c.glass.lastMs * 2;
    if (floorMs > capMs) capMs = floorMs;
    if (!c.glass.dirty && now - c.glass.at < capMs) return;
    // Never grab mid-drag: a capture blocks the frame, and the picture it would replace is the
    // same desktop anyway. The bake is marked dirty, so the frame after the drop is fresh.
    if (c.dragging || c.resizing) {
        c.glass.dirty = true;
        return;
    }
    // Blur needs pixels around the window to look right. While the window is *moving* the bake
    // gets a margin, so the next hundred pixels of travel are already inside it and cost a
    // re-crop instead of a capture; at rest the tight margin is enough (~45 % cheaper per
    // capture, exactly as on the strip).
    // 128 px, not the strip's 256: this window is 245x81, so a 128 px margin already makes the
    // bake 2x2.5 times bigger than the window itself, and it re-bakes every captureHz anyway.
    // The decision is sticky for a few seconds - flipping between two margins made every bake
    // resize (and thus re-create) the DIB.
    const bool movingSoon = justMoved || g_dragging || g_resizeEdge || DefaultGroupBusy() ||
                            GroupScaling() || (c.glassWideUntil && (LONG)(c.glassWideUntil - now) > 0);
    const int M = movingSoon ? kCompanionMargin : (g_glass[1].blurRadius > 0 ? 64 : 0);
    if (movingSoon) c.glassWideUntil = now + 3000;
    // H3c: "拖动时不更新背景" - during somebody's drag this window keeps the picture it has.
    if (movingSoon && g_cfg.dragNoCapture) {
        c.glass.dirty = false;
        return;
    }
    const BakeResult r = BakeGlass(c.glass, c.rc, M, L"companion", g_hue[1], g_glass[1], movingSoon);
    if (r == kBakeNoBudget) return;              // another window took this frame's budget
    if (r == kBakeFailed) {
        // Nothing usable (or the exclusion flag is missing on this system): wait a normal
        // capture period before trying again, otherwise every frame retries a failed grab.
        c.glass.at = now;
        c.glass.dirty = false;
        return;
    }
    c.glassCount++;
    // the bake is new -> the pixels in the window are stale
    if (c.bits) {
        TrayRepaint(c);
        CompanionPresent(c);
    }
}

// The tab set of an object is the set of components it owns (PLAN_COMPONENTS.md §2.2):
//   the strip          → 浮窗 + 图标条 + 玻璃(if the glass layer is on) + 组 1
//   a glass companion  → 浮窗 + 玻璃 + 组 N
//   a plain companion  → 浮窗 + 组 N
//   a group (menu)     → 组 N only (a group is not a window: no background, no glass)
// `hintObj` is what the menu asked for, `hintId` the group id when it is a group.
static void SettingsBuildPages(int hintObj, int hintId, int* hintPage) {
    g_pages.clear();
    *hintPage = -1;
    int wantKind = kPageFloatDock;
    int wantGroup = 0;

    auto addGroupPage = [](int id) {
        wchar_t title[32];
        swprintf_s(title, L"组 %d", id);
        // task 4: the 色调 row on a group page edits that group's wake-band colour
        g_hueGroup = id;
        g_pages.push_back(SPage{title, L"", kRowsGroup,
                                (int)(sizeof(kRowsGroup) / sizeof(kRowsGroup[0])),
                                kPageGroupKind, id});
    };

    if (hintObj == kObjGroup) {
        wantKind = kPageGroupKind;
        wantGroup = hintId;
        addGroupPage(hintId);
    } else if (hintObj == kObjCompanion) {
        // A companion owns "float" always, "glass" only when its own background is the glass
        // layer, and the 组 page of the group it belongs to (groupId 0 = in no group).
        wantKind = kPageFloatTray;
        g_pages.push_back(SPage{L"浮窗", L"traybar", kRowsFloatTray,
                                (int)(sizeof(kRowsFloatTray) / sizeof(kRowsFloatTray[0])),
                                kPageFloatTray, 0});
        const bool glass = CompanionHasGlassLayer(g_trayBar);
        if (glass)
            g_pages.push_back(SPage{L"玻璃", L"traybar", kRowsGlassTray,
                                    (int)(sizeof(kRowsGlassTray) / sizeof(kRowsGlassTray[0])),
                                    kPageGlass, 0});
        if (g_trayBar.groupId > 0) {
            wantGroup = g_trayBar.groupId;
            addGroupPage(g_trayBar.groupId);
        }
    } else {
        // The strip: a float window that also happens to be an icon bar and uses the glass.
        wantKind = kPageFloatDock;
        wantGroup = 1;
        g_pages.push_back(SPage{L"浮窗", L"dock", kRowsFloatDock,
                                (int)(sizeof(kRowsFloatDock) / sizeof(kRowsFloatDock[0])),
                                kPageFloatDock, 0});
        g_pages.push_back(SPage{L"图标条", L"dock", kRowsBar,
                                (int)(sizeof(kRowsBar) / sizeof(kRowsBar[0])), kPageBar, 0});
        if (g_cfg.glassLayer && g_cfg.bgMode != 2)      // solid has no glass material
            g_pages.push_back(SPage{L"玻璃", L"dock", kRowsGlass,
                                    (int)(sizeof(kRowsGlass) / sizeof(kRowsGlass[0])),
                                    kPageGlass, 0});
        addGroupPage(1);
    }

    g_page = 0;
    for (int i = 0; i < (int)g_pages.size(); i++) {
        if (g_pages[i].kind != wantKind) continue;
        if (wantKind == kPageGroupKind && g_pages[i].groupId != wantGroup) continue;
        *hintPage = i;
        break;
    }
    // One line per open: the tab set is the whole point of H2, so make it visible in the log.
    {
        std::wstring list;
        for (int i = 0; i < (int)g_pages.size(); i++) {
            if (i) list += L" | ";
            list += g_pages[i].title;
        }
        DLog(L"settings: obj=%d group=%d -> %d page(s): %s", hintObj, wantGroup,
             (int)g_pages.size(), list.c_str());
    }
}

static void ShowSettings(int hintKind, int hintId) {
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
    int hint = -1;
    SettingsBuildPages(hintKind, hintId, &hint);
    if (hint >= 0) g_page = hint;
    PageLoad();
    SettingsResizeForPage();                 // height follows the page that was picked
    RECT dockRect{};
    GetWindowRect(g_hwnd, &dockRect);
    int px = dockRect.left + (dockRect.right - dockRect.left) / 2 - g_setW / 2;
    int py = dockRect.top - g_setH - 10;
    HMONITOR mon = MonitorFromWindow(g_hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{sizeof(mi)};
    if (GetMonitorInfoW(mon, &mi)) {
        if (py < mi.rcWork.top) py = dockRect.bottom + 10;
        if (px + g_setW > mi.rcWork.right) px = mi.rcWork.right - g_setW;
        if (px < mi.rcWork.left) px = mi.rcWork.left;
        if (py + g_setH > mi.rcWork.bottom) py = mi.rcWork.bottom - g_setH;
    }
    g_setWnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
                               L"DockSettingsWindow", L"dock 设置", WS_POPUP, px, py, g_setW,
                               g_setH, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!g_setWnd) return;
    g_setBits = nullptr;
    ShowWindow(g_setWnd, SW_SHOW);      // UpdateLayeredWindow needs a visible window
    SettingsPaint();
    SetForegroundWindow(g_setWnd);
}

// Right click on a strip icon: show a menu that looks like the taskbar's own -
// "<title>" (open/bring forward), the app's own tasks (new window, profiles, recent
// workspaces...), and "关闭窗口". Pinning is deliberately absent: Windows has no public
// API for it and the old undocumented "taskbarpin" verb does nothing on Windows 11
// (measured 2026-11-12 on this machine).
static void ShowAppMenuForSlot(int slot) {
    if (slot < 0 || slot >= (int)g_slots.size()) return;
    int item = g_slots[slot].item;
    if (item < 0 || item >= (int)g_items.size()) return;
    const Item it = g_items[item];
    std::wstring exe = it.exePath;
    if (exe.empty() && it.hwnd && IsWindow(it.hwnd)) exe = WindowExe(it.hwnd);

    // Menu label: the pin's own name if this exe is pinned ("File Explorer", "Visual
    // Studio Code"), otherwise the shell's display name, otherwise the exe name. No
    // "打开" prefix - the native menu just shows the app name, and the name must not
    // change depending on whether a window happens to be open.
    const PinInfo* pin = PinForExe(exe);
    std::wstring name;
    if (pin && !pin->name.empty()) name = pin->name;
    if (name.empty() && !exe.empty()) {
        SHFILEINFOW sfi{};
        if (SHGetFileInfoW(exe.c_str(), 0, &sfi, sizeof(sfi), SHGFI_DISPLAYNAME) &&
            sfi.szDisplayName[0])
            name = sfi.szDisplayName;
    }
    if (name.empty()) name = exe.empty() ? L"?" : PathFindFileNameW(exe.c_str());

    std::vector<JumpTask> tasks = JumpTasksForExe(exe);
    HMENU menu = CreatePopupMenu();
    int id = 1;
    const int idOpen = id++;
    AppendMenuW(menu, MF_STRING, idOpen, name.c_str());
    std::vector<int> taskIds;
    if (!tasks.empty()) {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        for (size_t i = 0; i < tasks.size() && i < 12; i++) {
            const std::wstring& label = tasks[i].title;
            int tid = id++;
            AppendMenuW(menu, MF_STRING, tid, label.c_str());
            taskIds.push_back(tid);
        }
    }
    int idClose = 0;
    if (it.hwnd && IsWindow(it.hwnd)) {
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        idClose = id++;
        AppendMenuW(menu, MF_STRING, idClose, L"关闭窗口");
    }
    POINT sp{};
    GetCursorPos(&sp);
    g_popupOpen = true;
    int cmd = (int)TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, sp.x, sp.y, 0, g_hwnd,
                                  nullptr);
    g_popupOpen = false;
    DestroyMenu(menu);
    DLog(L"menu: slot %d item %d exe=%s tasks=%d -> cmd=%d", slot, item, exe.c_str(),
         (int)tasks.size(), cmd);
    if (cmd <= 0) return;
    if (cmd == idOpen) {
        // "Run the app" exactly like the taskbar's own name entry does: start the pinned
        // shortcut and let the App decide. Single-instance apps (QQ) then bring their
        // existing window forward, multi-instance ones (Edge, Explorer) open a new one -
        // which is what the native menu does. Unpinned windows are just activated.
        if (pin && !pin->lnk.empty()) LaunchShortcut(pin->lnk, slot);
        else if (it.hwnd && IsWindow(it.hwnd)) ActivateWindow(it.hwnd);
        else if (!it.exePath.empty()) LaunchPath(it.exePath, L"strip menu");
        else if (!it.lnkPath.empty()) LaunchShortcut(it.lnkPath, slot);
        return;
    }
    if (idClose && cmd == idClose) {
        if (it.hwnd && IsWindow(it.hwnd)) PostMessageW(it.hwnd, WM_CLOSE, 0, 0);
        return;
    }
    for (size_t i = 0; i < taskIds.size(); i++) {
        if (taskIds[i] == cmd) {
            RunJumpTask(tasks[i]);
            return;
        }
    }
}

// ---------------------------------------------------------------- dodge
// Double-clicking the strip's *empty* area (padding, the gaps between icons - not an
// icon, not "^") sends it to the point mirrored across the monitor work area's centre
// line: a wide strip goes up/down, a tall one left/right. Only the window is moved -
// UpdateAlpha() keeps running untouched, so the fade-by-cursor-distance during the
// flight is exactly the normal one.
//
// The class has no CS_DBLCLKS, so WM_LBUTTONDBLCLK never arrives; the second click is
// recognised here instead: same blank area, within GetDoubleClickTime(), moved < 4px.
static DWORD g_lastBlankClickAt = 0;
static POINT g_lastBlankClickPos{};

struct FlipState {
    bool active = false;
    DWORD t0 = 0;
    int dur = 250;
    int frames = 0;
    int fromX = 0, fromY = 0;
    int toX = 0, toY = 0;
};
static FlipState g_flip;

static void FlipTarget(int* px, int* py) {
    RECT wr{};
    GetWindowRect(g_hwnd, &wr);
    int w = wr.right - wr.left, h = wr.bottom - wr.top;
    RECT wa{};
    MONITORINFO mi{sizeof(mi)};
    HMONITOR mon = MonitorFromWindow(g_hwnd, MONITOR_DEFAULTTONEAREST);
    if (mon && GetMonitorInfoW(mon, &mi)) {
        wa = mi.rcWork;
    } else {
        wa = RECT{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
    }
    int x = wr.left, y = wr.top;
    // Only the axis that actually moves gets clamped: a strip that already hangs over
    // an edge (this machine's is wider than the screen) must not be dragged sideways by
    // an up/down dodge - "x stays the same" is part of the definition.
    if (w > h) {
        y = wa.top + wa.bottom - wr.top - h;      // wide strip: mirror top/bottom
        if (y + h > wa.bottom) y = wa.bottom - h;
        if (y < wa.top) y = wa.top;
    } else {
        x = wa.left + wa.right - wr.left - w;     // tall strip: mirror left/right
        if (x + w > wa.right) x = wa.right - w;
        if (x < wa.left) x = wa.left;
    }
    *px = x;
    *py = y;
}

static void FlipEnd(const wchar_t* why, bool atTarget) {
    if (!g_flip.active) return;
    g_flip.active = false;
    KillTimer(g_hwnd, 4);
    if (atTarget) {
        g_cfg.x = g_flip.toX;
        g_cfg.y = g_flip.toY;
        SetWindowPos(g_hwnd, HWND_TOPMOST, g_cfg.x, g_cfg.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
    }
    // a fresh capture belongs to the new position; doing it every frame would cost a
    // PrintWindow per frame, so the flight draws with the old bake and we re-bake once,
    // after landing
    g_bakeDirty = true;
    SavePosition();
    PaintAndPresent();
    DLog(L"flip: %s (%d,%d) -> (%d,%d) after %lu ms in %d frame(s)", why, g_flip.fromX,
         g_flip.fromY, g_cfg.x, g_cfg.y, (unsigned long)(GetTickCount() - g_flip.t0),
         g_flip.frames);
}

static void FlipTick() {
    if (!g_flip.active) return;
    DWORD elapsed = GetTickCount() - g_flip.t0;
    double t = (double)elapsed / (double)g_flip.dur;
    if (t >= 1.0) {
        FlipEnd(L"landed", true);
        return;
    }
    double e = t * t * (3.0 - 2.0 * t);      // smoothstep: soft start, soft landing
    g_flip.frames++;
    int x = g_flip.fromX + (int)((g_flip.toX - g_flip.fromX) * e + 0.5);
    int y = g_flip.fromY + (int)((g_flip.toY - g_flip.fromY) * e + 0.5);
    if (x == g_cfg.x && y == g_cfg.y) return;    // two timers feed this; one is enough
    g_cfg.x = x;
    g_cfg.y = y;
    // no repaint per frame: a layered window's surface travels with the window, so
    // SetWindowPos alone is the whole frame. Re-painting would cost more than the tick
    // and the bake belongs to the old spot anyway (re-baked once in FlipEnd).
    SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
    // The dodge animation is the same class of move as a drag: the attached windows have to
    // step with the strip, or they visibly arrive late (see CompanionFollowTo).
    CompanionFollowTo(x, y);
}

static void StartFlip() {
    if (!g_cfg.dodgeOnDoubleClick) return;   // task 2: [dock] dodgeOnDoubleClick=0
    if (g_flip.active) return;
    RECT wr{};
    GetWindowRect(g_hwnd, &wr);
    g_flip.fromX = wr.left;
    g_flip.fromY = wr.top;
    FlipTarget(&g_flip.toX, &g_flip.toY);
    if (g_flip.toX == g_flip.fromX && g_flip.toY == g_flip.fromY) {
        DLog(L"flip: already on the far side of the centre line - nothing to do");
        return;
    }
    g_flip.t0 = GetTickCount();
    g_flip.dur = 250;
    g_flip.frames = 0;
    g_flip.active = true;
    SetTimer(g_hwnd, 4, 8, nullptr);     // ~15ms in practice: enough steps for 250ms
    DLog(L"flip: double click on empty strip -> (%d,%d) to (%d,%d) over %d ms", g_flip.fromX,
         g_flip.fromY, g_flip.toX, g_flip.toY, g_flip.dur);
}

static bool IsBlankDoubleClick() {
    DWORD now = GetTickCount();
    POINT sp{};
    GetCursorPos(&sp);
    bool dbl = g_lastBlankClickAt && (now - g_lastBlankClickAt) <= GetDoubleClickTime() &&
               abs(sp.x - g_lastBlankClickPos.x) <= 4 &&
               abs(sp.y - g_lastBlankClickPos.y) <= 4;
    if (dbl) {
        g_lastBlankClickAt = 0;
        return true;
    }
    g_lastBlankClickAt = now;
    g_lastBlankClickPos = sp;
    return false;
}

// One step of the icon zoom. Returns bit0 = something moved, bit1 = still animating.
// The zoom keeps a fixed duration (hoverMs); how many steps it gets is decided by the
// caller's rate (the panel tick, or the fast timer while the zoom is running).
static int StepHoverAnimation(DWORD now) {
    if (!g_hwnd) return 0;
    if ((int)g_slotHover.size() != (int)g_slots.size())
        g_slotHover.assign(g_slots.size(), SlotAnim{});
    UINT dur = (UINT)(g_cfg.hoverMs < 40 ? 40 : g_cfg.hoverMs);
    int r = 0;
    for (size_t i = 0; i < g_slotHover.size(); i++) {
        SlotAnim& a = g_slotHover[i];
        float target = ((int)i == g_hover) ? 1.0f : 0.0f;
        if (target != a.target) {
            a.from = a.v;
            a.target = target;
            a.t0 = now;
        }
        float p = a.t0 ? (float)(now - a.t0) / (float)dur : 1.0f;
        if (p > 1) p = 1;
        if (p < 1) r |= 2;
        float e = p * p * (3.0f - 2.0f * p);     // smoothstep
        float nv = a.from + (a.target - a.from) * e;
        if (nv != a.v) {
            a.v = nv;
            r |= 1;
        }
    }
    return r;
}


// ---------------------------------------------------------------- frame clock
// WM_TIMER is quantised to the system tick (15.6ms on this machine), so 30Hz came out as
// 21Hz and anything above ~64Hz was impossible: the loop, not the renderer, was the
// ceiling. A high-resolution waitable timer in its own thread posts WM_APP+1 at the
// requested period; the 30ms WM_TIMER stays armed as a fallback (and is demoted to a 1s
// heartbeat once the thread runs).

static DWORD WINAPI FrameClockThread(LPVOID) {
    HANDLE timer = CreateWaitableTimerExW(nullptr, nullptr,
                                          CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    if (!timer) {
        DLog(L"frame clock: no high-resolution timer (err=%lu)", (unsigned long)GetLastError());
        return 0;
    }
    DLog(L"frame clock: high-resolution timer ready");
    while (!g_timerExit) {
        LARGE_INTEGER due{};
        double p = g_tickPeriod100ns;
        if (p < 1000.0) p = 1000.0;              // never faster than 10 kHz
        due.QuadPart = -(LONGLONG)p;
        if (!SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE)) break;
        HANDLE hs[2] = {timer, g_timerWake};
        DWORD r = WaitForMultipleObjects(2, hs, FALSE, INFINITE);
        if (r != WAIT_OBJECT_0) break;           // woken to stop
        // never let the queue fill up with ticks: one pending is enough
        if (InterlockedExchange(&g_tickPosted, 1) == 0) {
            if (!g_hwnd || !PostMessageW(g_hwnd, WM_APP + 1, 0, 0))
                InterlockedExchange(&g_tickPosted, 0);
        }
    }
    CancelWaitableTimer(timer);
    CloseHandle(timer);
    return 0;
}

static void StartFrameClock() {
    g_timerExit = 0;
    g_timerWake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    g_timerThread = CreateThread(nullptr, 0, FrameClockThread, nullptr, 0, nullptr);
    if (g_timerThread) {
        DLog(L"frame clock: thread started, %.1f ms period (%.0f Hz)", g_tickPeriod100ns / 10000.0,
             10000000.0 / g_tickPeriod100ns);
        if (g_hwnd) SetTimer(g_hwnd, 1, 1000, nullptr);   // demote the fallback
    }
}

static void StopFrameClock() {
    if (!g_timerThread) return;
    InterlockedExchange(&g_timerExit, 1);
    if (g_timerWake) SetEvent(g_timerWake);
    WaitForSingleObject(g_timerThread, 500);
    CloseHandle(g_timerThread);
    g_timerThread = nullptr;
    if (g_timerWake) { CloseHandle(g_timerWake); g_timerWake = nullptr; }
}

// Everything that has to happen once per frame. Driven by the high-resolution timer
// thread (WM_APP+1); the old 30ms WM_TIMER stays as a fallback if that thread could not
// start.
// One easing step for the reorder animation. Returns true while anything still moves, so the
// caller can keep the frame loop awake.
static bool AnimateReorder() {
    if (!g_reordering) return false;
    static DWORD last = 0;
    DWORD now = GetTickCount();
    float dt = last ? (float)(now - last) : 16.0f;
    last = now;
    if (dt > 120.0f) dt = 120.0f;
    float k = 1.0f - expf(-dt / 45.0f);      // same feel as the hover zoom
    bool moving = false;
    for (size_t i = 0; i < g_items.size(); i++) {
        Item& it = g_items[i];
        if (it.animX < -1e8f) continue;
        float d = (float)it.targetX - it.animX;
        if (d > -0.6f && d < 0.6f) { it.animX = (float)it.targetX; continue; }
        it.animX += d * k;
        moving = true;
    }
    return moving;
}

static void RenderTick() {
        DWORD now = GetTickCount();
        bool dirty = false;
        // H3 §3.3: the capture budget is per frame. Whoever bakes first in this tick pays for
        // it; a second bake only runs if the tick is still under [dock] captureBudgetMs.
        g_bakeBudgetUsedMs = 0;
        // H3c: start/stop the frozen work-area picture exactly with the drag. Must run before
        // any bake in this tick (the frozen grab has to exist before a moving window reads it).
        GlassDragTick();
        // A drag only records where the strip should go (see the WM_MOUSEMOVE branch);
        // the move itself is applied by UpdateLayeredWindow below, together with the new
        // pixels, so the two can never be seen a frame apart.
        if (g_dragMovePending && g_hwnd) dirty = true;
        // Everything below only matters when the cursor or the window actually moved.
        // At 120Hz+ the unconditional GetWindowRect/GetMonitorInfo/WindowFromPoint calls
        // were eating the whole frame budget - that was the "old slow" code.
        POINT cp{};
        bool haveCursor = GetCursorPos(&cp) != 0;
        static POINT lastCursor{-100000, -100000};
        bool cursorMoved = haveCursor && (cp.x != lastCursor.x || cp.y != lastCursor.y);
        if (haveCursor) lastCursor = cp;

        RECT curR{};
        if (g_hwnd) GetWindowRect(g_hwnd, &curR);
        static RECT lastTickRect{};
        bool movedNow = g_hwnd && (curR.left != lastTickRect.left || curR.top != lastTickRect.top ||
                                   curR.right != lastTickRect.right ||
                                   curR.bottom != lastTickRect.bottom);
        if (g_hwnd) lastTickRect = curR;

        static int lastUiState = -1;
        int uiState = (g_setWnd ? 4 : 0) | (g_gridVisible ? 2 : 0) | (g_menuOpen ? 1 : 0);
        bool uiChanged = (uiState != lastUiState);
        lastUiState = uiState;

        if (cursorMoved || movedNow || uiChanged) {
            UpdateAlpha();
            // A stuck WS_EX_TRANSPARENT makes the strip unclickable while it still looks
            // fine (it is only set when the strip fades out). Check the real style instead
            // of trusting the cached flag.
            if (g_alpha > 0 && g_hwnd &&
                (GetWindowLongW(g_hwnd, GWL_EXSTYLE) & WS_EX_TRANSPARENT)) {
                SetWindowLongW(g_hwnd, GWL_EXSTYLE,
                               GetWindowLongW(g_hwnd, GWL_EXSTYLE) & ~WS_EX_TRANSPARENT);
                g_clickThrough = false;
                DLog(L"alpha: cleared a stuck WS_EX_TRANSPARENT (alpha=%d)", g_alpha);
            }
            // edge docking follows the window position
            UpdateSnap();
        } else if (uiChanged) {
            UpdateSnap();
        }
        if (AnimateReorder()) dirty = true;
        // The dragged icon follows the cursor, and a mouse move touches no window at all, so
        // nothing else would mark the frame dirty: without this the icon froze at the last
        // painted spot and jumped to the cursor only when a swap happened to repaint.
        if (g_reordering) dirty = true;
        // Edge scroll while reordering: moving an icon past the container edge (left) or past
        // the grid button (right) pulls the hidden icons in from that side, so an icon can be
        // dropped somewhere that is not currently on the strip.
        if (g_reordering) {
            static DWORD lastEdge = 0;
            static bool wasOver = false;
            int sz = (int)(g_iconPx * kReorderZoom + 0.5f);
            POINT cp{};
            GetCursorPos(&cp);
            ScreenToClient(g_hwnd, &cp);
            int left = cp.x - sz / 2;
            RECT crc{};
            GetClientRect(g_hwnd, &crc);
            int clipR = crc.right;
            int clipL = 0;
            for (size_t i = 0; i < g_slots.size(); i++) {
                if (g_slots[i].item == kSlotWin) clipL = g_slots[i].rc.right;
                else if (g_slots[i].item == kSlotChevron) { clipR = g_slots[i].rc.left; break; }
            }
            const int thr = sz / 3;
            int overL = clipL - left;              // how much hangs under the Windows button
            int overR = (left + sz) - clipR;       // how much hangs under the grid button
            int per = g_pageItems;
            int n = (int)g_items.size();
            bool canL = overL > thr && g_scroll > 0;
            bool canR = overR > thr && g_scroll + per < n;
            bool over = canL || canR;
            if (over && (!wasOver || now - lastEdge >= 220)) {
                lastEdge = now;
                if (canL) {
                    g_scroll--;
                    if (g_scroll < 0) g_scroll = 0;
                    MoveItem(g_reorderItem, g_scroll);
                    g_reorderItem = g_scroll;
                } else {
                    g_scroll++;
                    int last = g_scroll + per - 1;
                    if (last > n - 1) last = n - 1;
                    MoveItem(g_reorderItem, last);
                    g_reorderItem = last;
                }
                SyncOrder();
                ComputeButtons();
                DLog(L"reorder: edge scroll %s -> scroll=%d item=%d (overL=%d overR=%d)",
                     canL ? L"left" : L"right", g_scroll, g_reorderItem, overL, overR);
                dirty = true;
            }
            wasOver = over;
        }
        FlipTick();          // backup for timer 4: positions come from the clock
        if (AnimateCorners() && !g_flip.active) {
            g_glassCacheValid = false;      // the rounded outline moved
            dirty = true;
        }

        // housekeeping: cheap, but there is no point in running it at 180Hz
        static DWORD lastWatch = 0;
        if (now - lastWatch >= 16) {
            lastWatch = now;
            if (g_alpha > 0 && !g_reordering) {
                if (cursorMoved || movedNow) UpdateHoverFromCursor();
            } else if (g_gridVisible && !g_menuOpen) {
                GridHide(L"strip faded");
            }
            TrayMenuTick();
            LaunchWatchTick();
            FlushPendingUp(now);
            TrayAutoDoubleTick(now);
            // The shell sometimes defers our "hide the native taskbar" while one of its own
            // popups is opening (Start, Win+X). When that deferral is dropped the bar simply
            // stays up until the user clicks elsewhere - the rare "it did not go away" case.
            // So keep asking for a couple of seconds (never while our tray flyout is what
            // keeps it on screen).
            if (g_barHideRetryUntil && (LONG)(now - g_barHideRetryUntil) < 0 &&
                !OverflowFlyoutOnScreen()) {
                static DWORD lastAsk = 0;
                if (!lastAsk || now - lastAsk >= 350) {
                    lastAsk = now;
                    if (NativeTaskbarOnScreen()) {
                        int found = 0;
                        EnumWindows(HideTaskbarProc, (LPARAM)&found);
                        if (!found) {
                            for (int i = 0; i < g_barSeenCount; i++) {
                                if (IsWindow(g_barSeen[i]))
                                    PostMessageW(g_barSeen[i], WM_TIMER, 2, 0);
                            }
                        }
                        DLog(L"win button: taskbar still on screen - asked again");
                    }
                }
            }
            // and refuses to hide it, so ask the mod (inside explorer) to cloak the taskbar
            // for us. Released once the flyout is gone (parked counts as gone), with a grace
            // period so the cloak survives the steps before the flyout appears.
            //
            // While the flyout is up the bar must also not be *expanded*: the shell keeps
            // asking for that, and an expanded bar is what surfaced later as "the taskbar pops
            // out by itself". So the deny is refreshed for the whole lifetime of the flyout and
            // dropped shortly after it goes.
            {
                const DWORD now2 = GetTickCount();
                static bool wasOnScreen = false;
                static DWORD lastDeny = 0;
                if (OverflowFlyoutOnScreen()) {
                    g_cloakGraceUntil = 0;
                    wasOnScreen = true;
                    TaskbarCloakSet(true);
                    if (!lastDeny || now2 - lastDeny >= 400) {
                        lastDeny = now2;
                        TaskbarDenyExpansion(1500);
                    }
                } else if (!g_cloakGraceUntil || (LONG)(now2 - g_cloakGraceUntil) >= 0) {
                    if (wasOnScreen) {
                        wasOnScreen = false;
                        // A tray that keeps the keyboard focus makes the shell expand its
                        // taskbar again a few seconds later (the "it pops up by itself" the
                        // user saw). Hand the focus back and ask the shell to hide the bar -
                        // but keep the cloak on for a moment, otherwise the bar becomes
                        // visible for the length of that hide animation.
                        if (g_fgBeforeTray && IsWindow(g_fgBeforeTray)) {
                            AllowSetForegroundWindow(ASFW_ANY);
                            SetForegroundWindow(g_fgBeforeTray);
                        }
                        HideNativeTaskbar();
                        g_cloakGraceUntil = now2 + 500;
                        TaskbarCloakSet(true);
                        g_fgBeforeTray = nullptr;
                        lastDeny = 0;
                        // Keep the "stay down" request a little longer than the close itself:
                        // the shell asks to re-expand right after its flyout goes away.
                        g_denyClearAt = now2 + 700;
                        DLog(L"tray: native flyout gone - focus handed back, taskbar hidden again");
                    } else {
                        TaskbarCloakSet(false);
                    }
                }
                // The deny is only ever dropped here, and only after the flyout has been and
                // gone. Clearing it whenever no flyout is on screen was fatal: the "^" path
                // writes it *before* the flyout exists, and the very next tick used to wipe it
                // - so the shell was free to expand the bar 130 ms later, which is the
                // "taskbar rises together with the tray and then never comes back down" the
                // user reported.
                if (g_denyClearAt && (LONG)(now2 - g_denyClearAt) >= 0) {
                    g_denyClearAt = 0;
                    TaskbarDenyClear(L"tray flyout gone");
                }
            }
            CompanionTick(now);      // attached windows: follow, fade, tray state
            // The group fade animates over ~120 ms, but the strip's alpha used to be sampled only
            // when the cursor moved - with one shared (animated) value it would freeze at the last
            // sample and never follow the fade (found 2026-11-22 while unifying the fade).
            if (g_alpha != DefaultGroupFadeAlpha()) UpdateAlpha();
            QuickSettingsTick(now);  // put the quick settings panel next to the tray bar
            PressWatchTick();
            FocusWatchTick();
            ZWatchTick(now);         // task 1: keep the topmost band honest (and yield to snips)
            // task 4: 贴边隐藏 for every group - it has to run even for a group that holds no
            // companion (a single-member group is a legal group).
            for (int gi = 0; gi < g_groupCount; gi++) HideEdgeTick(g_groups[gi], now);
            if (g_trayRetryAt && (LONG)(now - g_trayRetryAt) >= 0) {
                g_trayRetryAt = 0;
                // Never rebuild the panel while it is open: the tray list is
                // sorted, so a rebuild moves the icons under the user's cursor
                // and the click then lands on a neighbour (or on nothing). The
                // refreshed list is picked up the next time the panel opens.
                g_lastTrayCount = 0;
                if (g_rescanPending) {
                    g_rescanPending = false;
                    TrayBridgeOpen();
                    int n = g_trayShm ? (int)g_trayShm->count : -1;
                    DLog(L"tray: rescan done - the bridge now holds %d icon(s); "
                         L"they show the next time the panel opens", n);
                } else {
                    DLog(L"tray: refresh requested - the new icons show on the next "
                         L"open");
                }
            }
        }

        // icon grow/shrink: fixed duration (hoverMs). While it runs, timer 5
        // drives it at ~8ms so the zoom gets many steps instead of one per panel
        // tick - the duration never changes, only the smoothness.
        {
            int r = StepHoverAnimation(now);
            if ((r & 1) && g_alpha > 0) dirty = true;
            if ((r & 2) && g_alpha > 0) SetTimer(g_hwnd, 5, 8, nullptr);
        }

        // backdrop: the snapshot is re-taken at captureHz; in between, the strip
        // re-crops that snapshot whenever it moved (cheap - this is what
        // refreshHz buys while dragging). Captures are skipped *while* dragging
        // on purpose: a PrintWindow mid-drag is a guaranteed hitch, and the
        // snapshot it would replace is the same window anyway.
        static DWORD lastBake = 0;
        static RECT lastRect{};
        // no glass at all (opacity 0 + tint 0): there is nothing to capture or blend, and
        // leaving g_bakeDirty set would repaint every single frame for nothing
        const bool noGlassTick = (g_glass[0].glassOpacity == 0 && g_glass[0].tintStrength == 0);
        if (g_cfg.material == 1 && g_alpha > 0 && !g_flip.active && !noGlassTick) {
            RECT curR{};
            GetWindowRect(g_hwnd, &curR);
            RECT cr{};
            GetClientRect(g_hwnd, &cr);
            const int M = g_stripGlass.marginUsed;
            // The bake covers the strip plus M on every side, so a move that stays
            // inside that window needs no new bake at all - just a repaint that
            // reads the same blurred picture at the new offset. The backdrop then
            // stays anchored to the desktop instead of sliding with the strip.
            int ox = curR.left - g_stripGlass.origin.x, oy = curR.top - g_stripGlass.origin.y;
            // Containment, not equality: as long as the window (any size) sits inside the
            // snapshot with its top-left at (ox, oy), the existing picture can be re-cropped
            // and nothing needs grabbing. An equality test re-grabbed on every resize frame.
            bool covered = g_stripGlass.bits && g_stripGlass.w >= cr.right &&
                           g_stripGlass.h >= cr.bottom && ox >= 0 && oy >= 0 &&
                           ox + cr.right <= g_stripGlass.w && oy + cr.bottom <= g_stripGlass.h;
            bool captureDue = false;
            // Dragging is a no-capture zone (see below): a real mouse twitches a few
            // pixels when it is clicked, so "hold the strip without moving" counts as a
            // drag, and grabbing there would drop the whole glass refresh rate to the drag
            // cadence. The glass therefore keeps its last snapshot until the button is
            // released; that is a documented trade-off, not an oversight.
            bool busy = g_dragging || g_resizeEdge || DefaultGroupBusy() || GroupScaling();
            // Instrumentation for the 2026-11-16 "背景抖动" report: if the strip leaves its
            // snapshot while dragging, the glass is drawn from a stale picture. The margin fix
            // is what keeps this at 0; the counter is how that stays verifiable.
            if (busy && !covered) g_lostSnapshot++;
            if (g_cfg.captureHz > 0) {
                UINT capMs = (UINT)(1000 / g_cfg.captureHz);
                if (capMs < 1) capMs = 1;
                // A capture costs g_lastBakeMs. Asking for 65/s used to starve the
                // whole frame loop, so keep at least 2x the measured cost as a gap
                // whatever the setting says.
                DWORD floorMs = g_stripGlass.lastMs * 2;
                if (floorMs > capMs) capMs = floorMs;
                // Never grab mid-drag. A capture is ~15 ms and blocks the frame, and it
                // also changes what the glass shows in the middle of a drag (visible as a
                // jump). This is the behaviour the handover describes; the "refresh while
                // dragging" experiment in 4.8.3 turned out to be a mistake: with a real
                // mouse a click twitches a few pixels, the strip counts as being dragged,
                // and the whole glass refresh rate drops to the drag cadence - the user saw
                // exactly that as "the frame rate halves while I hold the strip".
                if (now - lastBake >= capMs) {
                    lastBake = now;
                    captureDue = true;
                }
            }
            // Never grab mid-drag: a capture is ~15 ms and blocks the frame, and it also
            // changes what the glass shows in the middle of a drag (a visible jump). Note
            // the order - this has to come *after* the block above, or it gets overwritten.
            if (busy) captureDue = false;
            if (captureDue) g_underCache.at = 0;   // force a new snapshot
            bool needBake = !covered || captureDue || g_bakeDirty;
            if (needBake) g_bakeDirty = true;
            bool moved = curR.left != lastRect.left || curR.top != lastRect.top ||
                         curR.right != lastRect.right || curR.bottom != lastRect.bottom;
            if (moved || needBake) dirty = true;
            lastRect = curR;
        }

        // one repaint per tick at most, and none at all while the dodge animation
        // owns the window (it moves the layered surface without repainting)
        if (dirty && !g_flip.active) {
            if (g_dragMovePending) {
                g_dragMovePending = false;
                g_renderPos.x = g_cfg.x;
                g_renderPos.y = g_cfg.y;
            }
            PaintAndPresent();
            g_renderPos.x = INT_MIN;
            g_renderPos.y = INT_MIN;
        }

        // H3: every *other* glass window bakes here, after the strip has had its turn in this
        // tick (the strip is the interactive one, so it gets first claim on the budget).
        CompanionGlassTick(now);

        // live evidence for tuning: how many ticks / repaints actually happened
        {
            static DWORD logAt = 0;
            static int ticks = 0, paints = 0;
            ticks++;
            if (dirty) paints++;
            if (logAt == 0) logAt = now;
            if (now - logAt >= 10000) {
                DWORD span = now - logAt;
                logAt = now;
                DLog(L"cadence: %d ticks / %d repaints / %d captures / %d companion moves in"
                     L" %lu ms",
                     ticks, paints, g_captureCount, g_companionFollowMoves,
                     (unsigned long)span);
                // H3: the second glass window is accounted for on its own line, so "glass got
                // more expensive" can be told apart from "the strip got more expensive".
                if (g_trayBar.glassCount)
                    DLog(L"cadence: companion glass: %d bakes, last %lu ms, bake %dx%d",
                         g_trayBar.glassCount, (unsigned long)g_trayBar.glass.lastMs,
                         g_trayBar.glass.w, g_trayBar.glass.h);
                // H3c: the drag-time frozen picture and how much of the glass it served.
                if (g_frozenCount || g_frozenHits)
                    DLog(L"cadence: frozen work-area picture: %d taken (last %lu ms), %d bake(s) "
                         L"read from it",
                         g_frozenCount, (unsigned long)g_frozenTakenMs, g_frozenHits);
                if (g_lostSnapshot)
                    DLog(L"cadence: %d frames painted from a backdrop that no longer covered "
                         L"the strip (%s)",
                         g_lostSnapshot,
                         g_cfg.dragNoCapture
                             ? L"expected: dragNoCapture=1 keeps the old picture by design"
                             : L"the frozen work-area picture should have covered this; check "
                               L"that the strip stayed inside the monitor");
                // per-frame cost, measured with QPC
                if (g_statPaints > 0) {
                    DLog(L"frame: n=%d paint=%.2fms (glass %.2f + icons %.2f) present=%.2fms"
                         L" bake=%.2fms (n=%d) sync=%.2fms (n=%d)",
                         g_statPaints, (g_statGlass + g_statIcons) / g_statPaints,
                         g_statGlass / g_statPaints, g_statIcons / g_statPaints,
                         g_statPresents ? g_statPresent / g_statPresents : 0.0,
                         g_statBakes ? g_statBake / g_statBakes : 0.0, g_statBakes,
                         g_statSyncs ? g_statSync / g_statSyncs : 0.0, g_statSyncs);
                }
                g_statGlass = g_statIcons = g_statPresent = g_statBake = 0;
                g_statSync = 0;
                g_statSyncs = 0;
                g_statPaints = g_statPresents = g_statBakes = 0;
                g_captureCount = 0;
                g_trayBar.glassCount = 0;
                g_frozenCount = 0;
                g_frozenHits = 0;
                g_companionFollowMoves = 0;
                g_lostSnapshot = 0;
                ticks = 0;
                paints = 0;
            }
        }

        // keep the button list in sync with the window list
        static DWORD lastCheck = 0;
        static size_t lastSig = 0;
        if (now - lastCheck > 1200) {
            lastCheck = now;
            size_t sig = 1469598103934665603ull;
            int count = 0;
            EnumWindows(
                [](HWND h, LPARAM lp) -> BOOL {
                    if (IsCandidate(h)) {
                        auto* acc = reinterpret_cast<std::pair<size_t*, int*>*>(lp);
                        *acc->first = (*acc->first ^ (size_t)h) * 1099511628211ull;
                        (*acc->second)++;
                    }
                    return TRUE;
                },
                (LPARAM)&std::pair<size_t*, int*>(&sig, &count));
            size_t full = sig ^ ((size_t)count << 32);
            if (full != lastSig) {
                lastSig = full;
                RefreshItems();
            }
        }
}

static LRESULT CALLBACK WndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CREATE:
            ArmRepaintTimer(h);
            // Low-level mouse hook: the only reliable way to notice "the user pressed
            // somewhere outside our windows" (see PressWatchTick).
            g_mouseHook = SetWindowsHookExW(WH_MOUSE_LL, LowLevelMouseProc,
                                            GetModuleHandleW(nullptr), 0);
            DLog(L"mouse hook = %p (err=%lu)", (void*)g_mouseHook,
                 (unsigned long)(g_mouseHook ? 0 : GetLastError()));
            RememberTaskbars();
            return 0;

        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;   // never steal focus from the target app

        case WM_NCHITTEST:
            return HTCLIENT;

        case WM_SETCURSOR: {
            POINT p{};
            GetCursorPos(&p);
            ScreenToClient(h, &p);
            RECT rc{};
            GetClientRect(h, &rc);
            // `屏蔽缩放`: no resize cursor anywhere on the member (the group ring still works)
            int e = GroupBlocksResize(nullptr) ? 0 : EdgeAt(p, rc);
            if (e) {
                LPCWSTR cur = IDC_ARROW;
                if ((e & 1) && (e & 4)) cur = IDC_SIZENWSE;
                else if ((e & 2) && (e & 4)) cur = IDC_SIZENESW;
                else if ((e & 8) && (e & 1)) cur = IDC_SIZENESW;
                else if ((e & 8) && (e & 2)) cur = IDC_SIZENWSE;
                else if ((e & 1) || (e & 2)) cur = IDC_SIZEWE;
                else cur = IDC_SIZENS;
                SetCursor(LoadCursorW(nullptr, cur));
                return TRUE;
            }
            break;
        }

        case WM_APP + 1:                 // frame from the high-resolution clock
            InterlockedExchange(&g_tickPosted, 0);
            RenderTick();
            return 0;

        case WM_TIMER:
            if (wp == 1) {
                RenderTick();      // fallback tick, see the timer thread

            } else if (wp == 2) {
                KillTimer(h, 2);
                Reload();
            } else if (wp == 3) {
                KillTimer(h, 3);
                DLog(L"thumb timer fired, hover=%d popup=%d", g_hover, (int)g_popupOpen);
                // the preview is a topmost window: showing it while one of our menus is
                // up would paint it over the menu
                if (g_hover >= 0 && !g_popupOpen) ThumbShow(g_hover);
            } else if (wp == 4) {
                FlipTick();          // the dodge animation runs on its own faster timer
            } else if (wp == 6) {
                KillTimer(h, 6);
                HideNativeTaskbar();     // see OpenPowerUserMenu
            } else if (wp == 5) {                static DWORD zoomT0 = 0;
                static int zoomSteps = 0;
                if (!zoomT0) {
                    zoomT0 = GetTickCount();
                    zoomSteps = 0;
                }
                zoomSteps++;
                int r = StepHoverAnimation(GetTickCount());
                if ((r & 1) && g_alpha > 0) PaintAndPresent();
                if (!(r & 2)) {
                    KillTimer(h, 5);      // zoom finished
                    DLog(L"hover zoom: %d frames in %lu ms (duration %d ms)", zoomSteps,
                         (unsigned long)(GetTickCount() - zoomT0), g_cfg.hoverMs);
                    zoomT0 = 0;
                }
            }
            return 0;

        case WM_MOUSEMOVE: {
            int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
            if (g_resizeEdge) {
                POINT p{};
                GetCursorPos(&p);
                RECT r = g_resizeRect;
                int dx = p.x - g_resizeOrigin.x;
                int dy = p.y - g_resizeOrigin.y;
                if (g_resizeEdge & 1) r.left += dx;
                if (g_resizeEdge & 2) r.right += dx;
                if (g_resizeEdge & 4) r.top += dy;
                if (g_resizeEdge & 8) r.bottom += dy;
                int minSide = g_cfg.minIcon + g_cfg.pad * 2;
                if (r.right - r.left < minSide) {
                    if (g_resizeEdge & 1) r.left = r.right - minSide; else r.right = r.left + minSide;
                }
                if (r.bottom - r.top < minSide) {
                    if (g_resizeEdge & 4) r.top = r.bottom - minSide; else r.bottom = r.top + minSide;
                }
                SetWindowPos(h, HWND_TOPMOST, r.left, r.top, r.right - r.left, r.bottom - r.top,
                             SWP_NOACTIVATE);
                g_cfg.x = r.left;
                g_cfg.y = r.top;
                // Resizing arrives per mouse message (not inside the frame tick), so the
                // follow has to be nudged here too - the 16 ms housekeeping gate would leave
                // the attached windows 1-2 frames behind the strip's new origin.
                CompanionFollowTo(r.left, r.top);
                GroupRecompute(DefaultGroup());   // the strip's own size changed: frame resizes
                UpdateSnap();
                return 0;
            }
            if (g_dragging) {
                POINT p;
                GetCursorPos(&p);
                // the button can go up while we are not looking (another window
                // grabs capture, the click launched an app): never keep dragging
                if (!(GetKeyState(VK_LBUTTON) & 0x8000) && !(GetKeyState(VK_RBUTTON) & 0x8000)) {
                    g_dragging = false;
                    g_dragMovePending = false;
                    ReleaseCapture();
                    SetWindowPos(h, HWND_TOPMOST, g_dragRect.left, g_dragRect.top, 0, 0,
                                 SWP_NOSIZE | SWP_NOACTIVATE);
                    SavePosition();
                    return 0;
                }
                g_cfg.x = p.x - g_dragStart.x;
                g_cfg.y = p.y - g_dragStart.y;
                // Moving the window here and repainting on the next tick is what made the
                // backdrop slide: between the two, the old pixels travel with the window.
                // Remember the target and let the frame tick move + paint together.
                // With a solid / no background there are no position-dependent pixels, so the
                // tick is pure latency: move right here (see MoveStripNow).
                if (GlassBackdropIsPositional()) g_dragMovePending = true;
                else MoveStripNow(g_cfg.x, g_cfg.y);
                return 0;
            }
            if (g_pressActive && !g_dragging && !g_reordering) {
                if (!(GetKeyState(VK_LBUTTON) & 0x8000)) {
                    g_pressActive = false;      // stale press: drop it
                } else {
                    POINT cp{};
                    GetCursorPos(&cp);
                    int dx = cp.x - g_pressScreen.x;
                    int dy = cp.y - g_pressScreen.y;
                    if (dx * dx + dy * dy >= 16) {
                        if (g_pressItem >= 0) {
                            // an icon was pressed: drag reorders it instead of moving the strip
                            g_reordering = true;
                            g_reorderItem = g_pressItem;
                            for (auto& it : g_items) it.animX = -1e9f;   // snap on first layout
                            g_hover = -1;                    // no zoom/hover while reordering
                            KillTimer(h, 3);
                            ThumbHide();
                            DLog(L"reorder start item=%d title=%s", g_reorderItem,
                                 g_items[g_reorderItem].title.c_str());
                        } else {
                            g_dragging = true;
                            g_lastBlankClickAt = 0;     // a drag is not half of a double click
                            DLog(L"drag start");
                        }
                    }
                }
            }
            if (g_reordering) {
                // live reorder: whatever slot is under the cursor swaps with the dragged item
                POINT cp{};
                GetCursorPos(&cp);
                POINT q = cp;
                ScreenToClient(h, &q);
                // The dragged icon lives at the row's centre line, so only x matters here;
                // the inset keeps a cursor parked on a cell boundary from flip-flopping.
                q.y = (g_slots.empty() ? q.y : (g_slots[0].rc.top + g_slots[0].rc.bottom) / 2);
                int over = -1;
                for (size_t i = 0; i < g_slots.size(); i++) {
                    const RECT& r = g_slots[i].rc;
                    if (q.x >= r.left + kReorderInset && q.x < r.right - kReorderInset &&
                        q.y >= r.top && q.y < r.bottom) {
                        over = (int)i;
                        break;
                    }
                }
                if (over >= 0 && g_slots[over].item >= 0 && g_slots[over].item != g_reorderItem) {
                    int to = g_slots[over].item;
                    DLog(L"reorder: item %d -> %d", g_reorderItem, to);
                    MoveItem(g_reorderItem, to);
                    g_reorderItem = to;
                    SyncOrder();                 // keep the periodic rebuild in line
                    ComputeButtons();
                    PaintAndPresent();
                }
                return 0;
            }
            int hover = -1;
            POINT pt{x, y};
            for (size_t i = 0; i < g_slots.size(); i++) {
                if (PtInRect(&g_slots[i].rc, pt)) { hover = (int)i; break; }
            }
            if (hover != g_hover) {
                g_hover = hover;
                KillTimer(h, 3);
                ThumbHide();
                if (hover >= 0) SetTimer(h, 3, (UINT)g_cfg.thumbDelay, nullptr);
                RECT rc;
                GetClientRect(h, &rc);
                Paint(rc.right, rc.bottom);
                Present();
                InvalidateRect(h, nullptr, FALSE);
            }
            TRACKMOUSEEVENT tme{sizeof(tme), TME_LEAVE, h, 0};
            TrackMouseEvent(&tme);
            return 0;
        }

        case WM_MOUSELEAVE:
            KillTimer(h, 3);
            ThumbHide();
            if (g_hover != -1) {
                g_hover = -1;
                RECT rc;
                GetClientRect(h, &rc);
                Paint(rc.right, rc.bottom);
                Present();
            }
            return 0;

        case WM_LBUTTONDOWN: {
            KillTimer(h, 3);
            ThumbHide();
            if (g_flip.active) FlipEnd(L"grabbed mid-flight", false);   // stop where it is
            int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
            POINT pt{x, y};
            int hit = -1;
            for (size_t i = 0; i < g_slots.size(); i++)
                if (PtInRect(&g_slots[i].rc, pt)) { hit = (int)i; break; }
            DLog(L"LBUTTONDOWN at %d,%d slot=%d of %d (alpha=%d through=%d)", x, y, hit,
                 (int)g_slots.size(), g_alpha, (int)g_clickThrough);
            {
                RECT crc{};
                GetClientRect(h, &crc);
                // `屏蔽缩放`: pressing an edge of the strip must not start a resize
                int edge = GroupBlocksResize(nullptr) ? 0 : EdgeAt(pt, crc);
                if (edge) {
                    GetWindowRect(h, &g_resizeRect);
                    GetCursorPos(&g_resizeOrigin);
                    g_resizeEdge = edge;
                    SetCapture(h);
                    DLog(L"resize start edge=%d", edge);
                    return 0;
                }
            }
            // remember the press: it becomes a click on release, or a drag once
            // the pointer moves a few pixels (works from an icon too)
            g_pressSlot = hit;
            g_pressItem = -1;
            g_pressHwnd = nullptr;
            g_pressLnk.clear();
            if (hit >= 0 && hit < (int)g_slots.size() && g_slots[hit].item >= 0 &&
                g_slots[hit].item < (int)g_items.size()) {
                g_pressHwnd = g_items[g_slots[hit].item].hwnd;
                g_pressLnk = g_items[g_slots[hit].item].lnkPath;
                g_pressItem = g_slots[hit].item;
            }
            g_pressPos = pt;
            g_pressScreen = POINT{x, y};
            ClientToScreen(h, &g_pressScreen);
            RECT wr;
            GetWindowRect(h, &wr);
            POINT cp;
            GetCursorPos(&cp);
            g_dragStart.x = cp.x - wr.left;
            g_dragStart.y = cp.y - wr.top;
            g_dragRect = wr;
            g_dragging = false;
            g_pressActive = true;
            SetCapture(h);
            return 0;
        }

        case WM_EXITSIZEMOVE:
            g_bakeDirty = true;
            SavePosition();
            SaveSize();
            PaintAndPresent();
            return 0;

        case WM_APP_TRAY_FELL_BACK:
            // the worker could not get the shell's flyout: keep the built-in grid usable
            DLog(L"tray: falling back to the built-in grid");
            if (!g_gridVisible) GridShow();
            return 0;

        case WM_LBUTTONUP:
            if (g_pressActive && !g_dragging && !g_resizeEdge && !g_reordering) {
                g_pressActive = false;
                ReleaseCapture();
                DLog(L"click slot=%d hwnd=%p lnk=%s", g_pressSlot, (void*)g_pressHwnd,
                     g_pressLnk.c_str());
                // empty strip (neither an icon nor "^"): the second quick click dodges.
                // [dock] dodgeOnDoubleClick=0 removes just this branch - the click tracking is
                // not even started, so nothing else can inherit a stale "last blank click".
                if (g_pressSlot < 0 && !g_pressHwnd && g_pressLnk.empty() &&
                    g_cfg.dodgeOnDoubleClick) {
                    if (IsBlankDoubleClick()) {
                        StartFlip();
                        return 0;
                    }
                } else {
                    g_lastBlankClickAt = 0;
                }
                if (g_pressSlot >= 0 && g_pressSlot < (int)g_slots.size() &&
                    g_slots[g_pressSlot].item == kSlotWin) {
                    // the native taskbar closes its overflow when Start opens; do the same
                    if (g_menuOpen) CloseMenuNow(L"win button opened the start menu");
                    if (g_gridVisible) GridHide(L"win button opened the start menu");
                    OpenStartMenu();     // the Windows button opens the shell's Start menu
                } else if (g_pressSlot >= 0 && g_pressSlot < (int)g_slots.size() &&
                           g_slots[g_pressSlot].item == kSlotChevron) {
                    // The chevron toggles the tray: by default that is the shell's own
                    // overflow flyout, which we only move next to the button ([tray] native).
                    if (g_trayNative) {
                        if (g_gridVisible) GridHide(L"native tray flyout opened");
                        NativeTrayToggle();
                    } else {
                        GridShow();      // the built-in grid panel
                    }
                } else if (g_pressHwnd && IsWindow(g_pressHwnd)) {
                    // we are about to give this app the foreground: that is not "focus
                    // went to a third party", so remember it as friendly
                    DWORD opid = 0;
                    GetWindowThreadProcessId(g_pressHwnd, &opid);
                    g_friendPid = opid;
                    g_focusGraceUntil = GetTickCount() + 300;
                    ActivateWindow(g_pressHwnd);
                } else if (!g_pressLnk.empty()) {
                    g_focusGraceUntil = GetTickCount() + 2000;   // the app is starting
                    LaunchShortcut(g_pressLnk, g_pressSlot);
                }
                return 0;
            }
            g_pressActive = false;
            if (g_reordering) {
                g_reordering = false;
                g_reorderItem = -1;
                ReleaseCapture();
                FinishReorder();
                return 0;
            }
            if (g_resizeEdge) {
                g_resizeEdge = 0;
                ReleaseCapture();
                SavePosition();
                SaveSize();
                PaintAndPresent();
                ShrinkToIcons();     // transparent strip only: snap back to the icon box
                return 0;
            }
            if (g_dragging) {
                g_dragging = false;
                if (g_dragMovePending) {
                    g_dragMovePending = false;
                    SetWindowPos(h, HWND_TOPMOST, g_cfg.x, g_cfg.y, 0, 0,
                                 SWP_NOSIZE | SWP_NOACTIVATE);
                }
                ReleaseCapture();
                SavePosition();
                Reload();
            }
            return 0;

        case WM_RBUTTONUP: {
            // The strip's own menu (settings, quit, autostart...). A forwarded tray
            // menu in the way is put away first: only one menu is tracked at a time.
            if (g_menuOpen) CloseMenuNow(L"strip menu opened");
            // the hover preview is a topmost window and would cover the menu
            KillTimer(h, 3);
            ThumbHide();
            int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
            POINT pt{x, y};
            int hit = -1;
            for (size_t i = 0; i < g_slots.size(); i++)
                if (PtInRect(&g_slots[i].rc, pt)) { hit = (int)i; break; }
            int hitItem = (hit >= 0) ? g_slots[hit].item : -1;
            if (hit >= 0 && hitItem == kSlotWin) {
                OpenPowerUserMenu();      // same menu as right-clicking the Start button
                return 0;
            }
            if (hit >= 0 && hitItem >= 0) {
                // on an icon: the app's own menu (open / tasks / close window)
                ShowAppMenuForSlot(hit);
                return 0;
            }
            HMENU menu = CreatePopupMenu();
            if (hitItem >= 0 && g_items[hitItem].hwnd) {
                AppendMenuW(menu, MF_STRING, 1, L"关闭该窗口");
                AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
            }
            AppendMenuW(menu, MF_STRING, 2, L"重载配置");
            AppendMenuW(menu, MF_STRING, 7, L"重新扫描托盘");
            AppendMenuW(menu, MF_STRING, 4, L"打开日志");
            AppendMenuW(menu, MF_STRING, 5, L"设置…");
            AppendMenuW(menu, MF_STRING | (AutoStartEnabled() ? MF_CHECKED : 0), 6,
                        L"开机自启");
            AppendMenuW(menu, MF_STRING, 3, L"退出");
            POINT sp;
            GetCursorPos(&sp);
            g_popupOpen = true;
            int cmd = (int)TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, sp.x, sp.y, 0, h, nullptr);
            g_popupOpen = false;
            DestroyMenu(menu);
            if (cmd == 1 && hitItem >= 0) PostMessageW(g_items[hitItem].hwnd, WM_CLOSE, 0, 0);
            else if (cmd == 2) Reload();
            else if (cmd == 7) {
                // Ask every app to register its tray icon again, then re-read the table:
                // the self-heal for "an icon vanished after a Windhawk mod reload".
                DLog(L"tray: manual rescan requested - broadcasting TaskbarCreated");
                StartTrayWarmup(0);
                g_rescanPending = true;
                g_trayRetryAt = GetTickCount() + 600;
            }
            else if (cmd == 4) ShellExecuteW(nullptr, L"open", g_logPath.c_str(), nullptr, nullptr,
                                            SW_SHOWNORMAL);
            else if (cmd == 5) ShowSettings(kObjStrip, 0);
            else if (cmd == 6) {
                bool on = SetAutoStart(!AutoStartEnabled());
                DLog(L"autostart -> %d (ok=%d)", (int)AutoStartEnabled(), (int)on);
            }
            else if (cmd == 3) PostQuitMessage(0);
            return 0;
        }

        case WM_SIZE:
            PaintAndPresent();
            return 0;

        case WM_MOUSEWHEEL: {
            int delta = GET_WHEEL_DELTA_WPARAM(wp);
            int n = (int)g_items.size();
            int per = g_pageItems;
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
        case WM_SETTINGCHANGE:
            SetTimer(h, 2, 300, nullptr);
            return 0;

        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

// ---------------------------------------------------------------- main
static DWORD IntegrityOfToken(HANDLE tok) {
    BYTE buf[512]{};
    DWORD sz = 0;
    if (!GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof(buf), &sz)) return 0;
    auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buf);
    DWORD count = *GetSidSubAuthorityCount(label->Label.Sid);
    if (!count) return 0;
    return *GetSidSubAuthority(label->Label.Sid, count - 1);
}

static DWORD OwnIntegrity() {
    DWORD v = 0;
    HANDLE tok = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
        v = IntegrityOfToken(tok);
        CloseHandle(tok);
    }
    return v;
}

static DWORD IntegrityOfProcess(DWORD pid) {
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return 0;
    DWORD v = 0;
    HANDLE tok = nullptr;
    if (OpenProcessToken(h, TOKEN_QUERY, &tok)) {
        v = IntegrityOfToken(tok);
        CloseHandle(tok);
    }
    CloseHandle(h);
    return v;
}

// If another instance is running: take over when we are at least as privileged
// (a dock started from a low-integrity host cannot launch programs, so a normal
// double-click has to be able to replace it), otherwise just flash it.
static bool ClaimSingleInstance(HANDLE mtx) {
    if (!mtx || GetLastError() != ERROR_ALREADY_EXISTS) return true;

    HWND other = FindWindowW(L"DockStripWindow", nullptr);
    DWORD otherPid = 0;
    if (other) GetWindowThreadProcessId(other, &otherPid);

    DWORD mine = OwnIntegrity();
    DWORD theirs = otherPid ? IntegrityOfProcess(otherPid) : 0;

    if (otherPid && theirs && theirs <= mine) {
        HANDLE hp = OpenProcess(PROCESS_TERMINATE, FALSE, otherPid);
        if (hp) {
            TerminateProcess(hp, 0);
            CloseHandle(hp);
            for (int i = 0; i < 40 && FindWindowW(L"DockStripWindow", nullptr); i++)
                Sleep(50);
            return true;   // we now own the name
        }
    }
    if (other) {
        SetWindowPos(other, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        FlashWindow(other, TRUE);
    }
    return false;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    HANDLE mtx = CreateMutexW(nullptr, TRUE, L"Local\\DockStripSingleInstance");
    if (!ClaimSingleInstance(mtx)) return 0;

    wchar_t exeDir[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exeDir, MAX_PATH);
    PathRemoveFileSpecW(exeDir);
    g_iniPath = std::wstring(exeDir) + L"\\dock.ini";
    if (!PathFileExistsW(g_iniPath.c_str())) CreateDefaultIni();
    StripIniBom();
    LoadConfig();

    g_logPath = std::wstring(exeDir) + L"\\dock.log";
    // Keep the log across restarts: it is the only evidence after something
    // goes wrong. Rotate instead of truncating.
    {
        WIN32_FILE_ATTRIBUTE_DATA fa{};
        unsigned long long size = 0;
        if (GetFileAttributesExW(g_logPath.c_str(), GetFileExInfoStandard, &fa))
            size = ((unsigned long long)fa.nFileSizeHigh << 32) | fa.nFileSizeLow;
        if (size > (4ull << 20)) {
            std::wstring old = std::wstring(exeDir) + L"\\dock.old.log";
            MoveFileExW(g_logPath.c_str(), old.c_str(), MOVEFILE_REPLACE_EXISTING);
        }
        DLog(L"---- run ----");
    }
    DLog(L"=== dock start, exeDir=%s", exeDir);
    QpcInit();
    DLog(L"=== build %S %S", __DATE__, __TIME__);
    DLog(L"cfg: bgAlpha=%d bg=%06X radius=%d pad=%d gap=%d min=%d max=%d ini=%s",
         (int)g_cfg.bgAlpha, (unsigned)g_cfg.bg, g_cfg.radius, g_cfg.pad, g_cfg.gap,
         g_cfg.minIcon, g_cfg.maxIcon, g_iniPath.c_str());
    LogProcessContext();

    if (DWORD il = OwnIntegrity(); il && il < 0x2000) {
        DLog(L"WARNING: low integrity 0x%lx - relaunching through the shell", il);
        // A low-integrity dock can switch windows but cannot start other programs: the
        // child inherits low IL and dies on its own, which looks exactly like "clicking an
        // icon does nothing". Ask explorer to start us again - the shell runs it at its own
        // (medium) integrity - and let this copy exit.
        wchar_t self[MAX_PATH]{};
        GetModuleFileNameW(nullptr, self, MAX_PATH);
        std::wstring selfArg = L"\"" + std::wstring(self) + L"\"";
        HINSTANCE r = ShellExecuteW(nullptr, L"open", L"explorer.exe", selfArg.c_str(), nullptr,
                                    SW_SHOWNORMAL);
        DLog(L"low integrity: asked the shell to restart us (ShellExecute -> %lld)",
             (long long)(INT_PTR)r);
        if ((INT_PTR)r <= 32) {
            MessageBoxW(nullptr,
                        L"\u8fd9\u4e2a dock \u662f\u5728\u4f4e\u6743\u9650\u73af\u5883\u4e0b\u542f\u52a8\u7684\uff0c"
                        L"\u5b83\u53ef\u4ee5\u5207\u6362\u7a97\u53e3\uff0c\u4f46\u65e0\u6cd5\u542f\u52a8\u65b0\u7a0b\u5e8f\u3002\n\n"
                        L"\u8bf7\u5148\u5728\u4efb\u52a1\u7ba1\u7406\u5668\u7ed3\u675f dock.exe\uff0c"
                        L"\u518d\u6309 Win+E \u5728\u6587\u4ef6\u8d44\u6e90\u7ba1\u7406\u5668\u91cc\u53cc\u51fb dock.exe \u542f\u52a8\u3002",
                        L"dock", MB_ICONWARNING | MB_SETFOREGROUND);
        }
        return 0;
    }

    PWSTR appdata = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &appdata))) {
        g_pinDir = std::wstring(appdata) + L"\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar";
        CoTaskMemFree(appdata);
    }

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    // A silent death is useless: log the faulting code and its offset inside dock.exe before
    // letting Windows Error Reporting do its thing (the dock vanished once with no trace,
    // 2026-11-21 21:34 - this is what makes the next one diagnosable).
    SetUnhandledExceptionFilter([](EXCEPTION_POINTERS* ep) -> LONG {
        if (ep && ep->ExceptionRecord) {
            const EXCEPTION_RECORD* r = ep->ExceptionRecord;
            const char* base = (const char*)GetModuleHandleW(nullptr);
            const char* where = (const char*)r->ExceptionAddress;
            DLog(L"!!! crash: code=%08lX at +0x%llX inside dock.exe (addr=%p)",
                 (unsigned long)r->ExceptionCode,
                 base && where > base ? (unsigned long long)(where - base) : 0ull,
                 (void*)r->ExceptionAddress);
        }
        return EXCEPTION_CONTINUE_SEARCH;
    });
    BuildItems();

    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = inst;
    wc.lpszClassName = L"DockStripWindow";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);

    WNDCLASSEXW wct{sizeof(wct)};
    wct.lpfnWndProc = ThumbProc;
    wct.hInstance = inst;
    wct.lpszClassName = L"DockThumbWindow";
    wct.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&wct);
    g_thumbWnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                                 L"DockThumbWindow", L"", WS_POPUP, 0, 0, 10, 10, nullptr, nullptr,
                                 inst, nullptr);

    int w, h;
    ComputeLayout(&w, &h);
    // the size the user dragged to is part of the layout: without this every restart
    // snapped back to the "one row of default icons" width (hasSize was read and never
    // used, so the dock forgot its size on every launch)
    if (g_cfg.hasSize && g_cfg.w > 0 && g_cfg.h > 0) {
        w = g_cfg.w;
        h = g_cfg.h;
    }
    if (!g_cfg.hasPos) {
        int sw = GetSystemMetrics(SM_CXSCREEN), sh = GetSystemMetrics(SM_CYSCREEN);
        g_cfg.x = (sw - w) / 2;
        g_cfg.y = sh - h - 80;
    }
    g_hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
                             wc.lpszClassName, L"dock", WS_POPUP, g_cfg.x,
                             g_cfg.y, w, h,
                             nullptr, nullptr, inst, nullptr);
    if (!g_hwnd) return 1;

    ComputeButtons();
    Paint(w, h);
    g_alpha = 255;
    ShowWindow(g_hwnd, SW_SHOWNOACTIVATE);
    Present();
    CompanionCreate();       // the tray bar sits next to the strip, hidden until hovered
    StartFrameClock();      // drive the frames from a high-resolution timer
    TrayBridgeEnsureExists();   // own the block so nobody can hand us a bad DACL
    StartTrayWarmup(1500);   // fill the tray bridge table once the shell is up

    if (wcsstr(GetCommandLineW(), L"--settings")) ShowSettings();

    if (!RegisterHotKey(g_hwnd, 100, MOD_CONTROL | MOD_ALT | MOD_SHIFT, 'D')) {
        // ignore: the right click menu can still quit
    }

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (msg.message == WM_HOTKEY && msg.wParam == 100) break;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    StopFrameClock();
    UnregisterHotKey(g_hwnd, 100);
    if (g_memDC) DeleteDC(g_memDC);
    if (g_dib) DeleteObject(g_dib);
    CoUninitialize();
    return 0;
}
