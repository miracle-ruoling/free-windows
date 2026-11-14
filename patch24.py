"""Patch dock.cpp: long-press an icon and drag to reorder it.

Before this, a left-drag anywhere on the strip moved the whole strip. Now the press point
decides:

  * press on an *item* and drag  -> that item is moved through the row (live reorder);
  * press on the blank part      -> the strip moves, as before.

The trade-off (the user's own call): in a fully packed strip there is no blank area, so the
strip can then only be moved by grabbing whatever padding is left.

Order is persisted as `order=` in the ini: a ';'-separated list of item keys (lowercased exe
path, or the title when an item has no exe), applied with a stable sort at the end of
BuildItems(). Stable matters: a pin and the windows of its exe share one key, so they stay
grouped, and items the list does not mention keep their build order after the listed ones.
"""
import io
import os
import shutil
import sys

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dock.cpp')
src = io.open(P, 'r', encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in src else '\n'
orig = src


def sub(old, new, why):
    global src
    o = old.replace('\n', nl)
    n = new.replace('\n', nl)
    if src.count(o) != 1:
        print('FAIL [%s]: found %d matches' % (why, src.count(o)))
        sys.exit(1)
    src = src.replace(o, n)
    print('ok   %s' % why)


# ---------------------------------------------------------------- 1. config key
sub(
    """    std::wstring extraPins;""",
    """    std::wstring extraPins;
    std::wstring order;          // user order of the strip, see ItemKey()""",
    'config field')

sub(
    """    GetPrivateProfileStringW(L"dock", L"extraPins", L"", buf, 1024, g_iniPath.c_str());
    g_cfg.extraPins = buf;""",
    """    GetPrivateProfileStringW(L"dock", L"extraPins", L"", buf, 1024, g_iniPath.c_str());
    g_cfg.extraPins = buf;
    {
        // the item order can be long: one key per strip item
        std::vector<wchar_t> ob(8192, 0);
        GetPrivateProfileStringW(L"dock", L"order", L"", ob.data(), (DWORD)ob.size(),
                                 g_iniPath.c_str());
        g_cfg.order = ob.data();
    }""",
    'config read')

# ---------------------------------------------------------------- 2. key + helpers
sub(
    """static void BuildItems() {""",
    """// Identity of a strip item for the persisted order. One key for a pin and for the windows
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

static void BuildItems() {""",
    'order helpers')

# ---------------------------------------------------------------- 3. apply the order
sub(
    """    g_items.swap(ordered);
    g_cachedIconPx = 0;      // fresh Item objects: the pixel cache must rebuild""",
    """    g_items.swap(ordered);
    g_cachedIconPx = 0;      // fresh Item objects: the pixel cache must rebuild""",
    'anchor check (no-op)')

sub(
    """        if (it.iconPath.empty() && it.hwnd) it.iconPath = it.exePath;
    }
""",
    """        if (it.iconPath.empty() && it.hwnd) it.iconPath = it.exePath;
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
""",
    'apply the persisted order')

# ---------------------------------------------------------------- 4. state globals
sub(
    """static int g_scroll = 0;        // first visible item""",
    """static int g_scroll = 0;        // first visible item
static bool g_reordering = false;   // dragging an icon to a new place in the row
static int g_reorderItem = -1;      // item being dragged
static int g_pressItem = -1;        // item under the button at press time (-1 = blank)""",
    'reorder globals')

# ---------------------------------------------------------------- 5. remember the pressed item
sub(
    """            g_pressSlot = hit;
            g_pressHwnd = nullptr;
            g_pressLnk.clear();""",
    """            g_pressSlot = hit;
            g_pressItem = -1;
            g_pressHwnd = nullptr;
            g_pressLnk.clear();""",
    'reset the pressed item')

sub(
    """            if (hit >= 0 && hit < (int)g_slots.size() && g_slots[hit].item >= 0 &&
                g_slots[hit].item < (int)g_items.size()) {
                g_pressHwnd = g_items[g_slots[hit].item].hwnd;
                g_pressLnk = g_items[g_slots[hit].item].lnkPath;
            }""",
    """            if (hit >= 0 && hit < (int)g_slots.size() && g_slots[hit].item >= 0 &&
                g_slots[hit].item < (int)g_items.size()) {
                g_pressHwnd = g_items[g_slots[hit].item].hwnd;
                g_pressLnk = g_items[g_slots[hit].item].lnkPath;
                g_pressItem = g_slots[hit].item;
            }""",
    'remember the pressed item')

# ---------------------------------------------------------------- 6. press -> reorder or move
sub(
    """                    if (dx * dx + dy * dy >= 16) {
                        g_dragging = true;
                        g_lastBlankClickAt = 0;     // a drag is not half of a double click
                        DLog(L"drag start");
                    }
                }
            }""",
    """                    if (dx * dx + dy * dy >= 16) {
                        if (g_pressItem >= 0) {
                            // an icon was pressed: drag reorders it instead of moving the strip
                            g_reordering = true;
                            g_reorderItem = g_pressItem;
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
                int over = -1;
                for (size_t i = 0; i < g_slots.size(); i++) {
                    if (PtInRect(&g_slots[i].rc, q)) { over = (int)i; break; }
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
            }""",
    'press decides reorder vs move')

# ---------------------------------------------------------------- 7. finish on release
sub(
    """            g_pressActive = false;
            if (g_resizeEdge) {""",
    """            g_pressActive = false;
            if (g_reordering) {
                g_reordering = false;
                g_reorderItem = -1;
                ReleaseCapture();
                FinishReorder();
                return 0;
            }
            if (g_resizeEdge) {""",
    'finish the reorder on release')

# ---------------------------------------------------------------- 8. no hover churn while reordering
sub(
    """static void UpdateHoverFromCursor() {
    int hover = -1;""",
    """static void UpdateHoverFromCursor() {
    if (g_reordering) return;      // the row is being reordered: no zoom, no preview
    int hover = -1;""",
    'freeze hover while reordering')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak24')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
