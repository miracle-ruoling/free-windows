import io, sys

p = r"C:\Users\20979\RP_Projects\fly_bar\dock\dock.cpp"
s = io.open(p, encoding="utf-8").read()

def rep(old, new, count=1):
    global s
    if old not in s:
        print("MISSING:", old[:80].replace("\n", "\\n"))
        sys.exit(1)
    s = s.replace(old, new, count)

# --- thumbnails: take a slot index, not an item index ---
rep("""    Item& it = g_items[index];""",
"""    if (index >= (int)g_slots.size()) return;
    const Slot slot = g_slots[index];
    int itemIndex = slot.item;
    if (itemIndex < 0) { ThumbHide(); return; }
    Item& it = g_items[itemIndex];""")

rep("""    if (index >= (int)g_buttonRects.size()) return;

    RECT btn = g_buttonRects[index];""",
"""    RECT btn = slot.rc;""")

rep("""    DLog(L"thumb: register index=%d hwnd=%p", index, (void*)it.hwnd);""",
"""    DLog(L"thumb: register slot=%d item=%d hwnd=%p", index, itemIndex, (void*)it.hwnd);""")

rep("""    DLog(L"thumb: skip index=%d hwnd=%p", index, (void*)it.hwnd);""",
"""    DLog(L"thumb: skip slot=%d item=%d hwnd=%p", index, itemIndex, (void*)it.hwnd);""")

# --- hover hit test ---
rep("""            int hover = -1;
            POINT pt{x, y};
            for (size_t i = 0; i < g_buttonRects.size(); i++) {
                if (PtInRect(&g_buttonRects[i], pt)) { hover = (int)i; break; }
            }""",
"""            int hover = -1;
            POINT pt{x, y};
            for (size_t i = 0; i < g_slots.size(); i++) {
                if (PtInRect(&g_slots[i].rc, pt)) { hover = (int)i; break; }
            }""")

# --- left click: slot -> item, -1 means expand ---
rep("""            for (size_t i = 0; i < g_buttonRects.size(); i++)
                if (PtInRect(&g_buttonRects[i], pt)) { hit = (int)i; break; }
            DLog(L"LBUTTONDOWN at %d,%d hit=%d of %d (alpha=%d through=%d)", x, y, hit,
                 (int)g_items.size(), g_alpha, (int)g_clickThrough);
            if (hit >= 0) {
                ClickItem(hit);
            } else {""",
"""            for (size_t i = 0; i < g_slots.size(); i++)
                if (PtInRect(&g_slots[i].rc, pt)) { hit = (int)i; break; }
            DLog(L"LBUTTONDOWN at %d,%d slot=%d of %d (alpha=%d through=%d)", x, y, hit,
                 (int)g_slots.size(), g_alpha, (int)g_clickThrough);
            if (hit >= 0 && g_slots[hit].item < 0) {
                ToggleExpand();
            } else if (hit >= 0) {
                ClickItem(g_slots[hit].item);
            } else {""")

# --- right click: same mapping ---
rep("""            for (size_t i = 0; i < g_buttonRects.size(); i++)
                if (PtInRect(&g_buttonRects[i], pt)) { hit = (int)i; break; }
            HMENU menu = CreatePopupMenu();
            if (hit >= 0 && g_items[hit].hwnd) {""",
"""            for (size_t i = 0; i < g_slots.size(); i++)
                if (PtInRect(&g_slots[i].rc, pt)) { hit = (int)i; break; }
            int hitItem = (hit >= 0) ? g_slots[hit].item : -1;
            HMENU menu = CreatePopupMenu();
            if (hitItem >= 0 && g_items[hitItem].hwnd) {""")

rep("""            if (cmd == 1 && hit >= 0) PostMessageW(g_items[hit].hwnd, WM_CLOSE, 0, 0);""",
"""            if (cmd == 1 && hitItem >= 0) PostMessageW(g_items[hitItem].hwnd, WM_CLOSE, 0, 0);""")

# --- drop the unused vector ---
rep("static std::vector<RECT> g_buttonRects;\n", "")

io.open(p, "w", encoding="utf-8").write(s)
print("patched slots usage")
