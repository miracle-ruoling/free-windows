"""Patch dock.cpp (step 1): animate the reorder.

What the user asked for:
  * the long-pressed icon stays at 1.34x and follows the cursor on the long axis only;
  * the other icons stay at 1x and *slide* out of the way, leaving its slot empty;
  * when the pressed icon's centre reaches another icon's cell, that icon takes the empty slot
    and its own cell becomes the new hole (the data side already worked like this - MoveItem
    splices the dragged item to the target index, which is the same thing).

Mechanics here:
  * Item gets `animX` (displayed x, client coords) and `targetX` (from the layout). Every frame
    animX eases towards targetX with the same curve as the hover zoom, so a splice - which moves
    several targets by one cell at once - animates instead of teleporting. Because animX lives in
    the Item, it travels with the item through splice() and through vector reallocation.
  * While reordering the dragged item gets no slot at all: ComputeButtons still reserves its
    width (the hole) but draws nothing there, so the row keeps its size and does not re-centre.
  * Hit testing stays on the *target* slot rects (static per layout), not on the animated
    positions: no feedback loop is possible, which is why the "moving icons do not count"
    rule is not needed. A small inset (6 px) is the hysteresis that stops flip-flopping when
    the cursor sits exactly on a cell boundary.
  * The dragged icon is drawn last, at the cursor, clipped to [0, chevron.left) - the container
    edge on the left, the grid button on the right.
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


# ---------------------------------------------------------------- 1. per-item animation state
sub(
    """    bool hasWindow = false;
};""",
    """    bool hasWindow = false;
    // reorder animation: displayed x (client) easing towards the slot's x
    float animX = -1e9f;
    int targetX = 0;
};

static const int kReorderInset = 6;      // px of hysteresis at a cell boundary
static const float kReorderZoom = 1.34f; // the dragged icon stays at the hover size""",
    'item animation fields')

# ---------------------------------------------------------------- 2. layout: hole + targetX
sub(
    """    for (int i = 0; i < visible; i++) {
        int item = g_scroll + i;
        if (item >= n) break;
        Slot s;
        s.item = item;
        s.size = sizes[i];
        int cross = pad + (shortSide - pad * 2 - s.size) / 2;
        if (vertical) s.rc = {cross, pos, cross + s.size, pos + s.size};
        else s.rc = {pos, cross, pos + s.size, cross + s.size};
        g_slots.push_back(s);
        pos += s.size + gap;
    }""",
    """    for (int i = 0; i < visible; i++) {
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
    }""",
    'layout reserves the hole and records targets')

# ---------------------------------------------------------------- 3. ease once per frame
sub(
    """static void RenderTick() {""",
    """// One easing step for the reorder animation. Returns true while anything still moves, so the
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

static void RenderTick() {""",
    'reorder easing')

sub(
    """        FlipTick();          // backup for timer 4: positions come from the clock""",
    """        if (AnimateReorder()) dirty = true;
        FlipTick();          // backup for timer 4: positions come from the clock""",
    'drive the animation')

# ---------------------------------------------------------------- 4. draw at the animated x
sub(
    """        Item& it = g_items[s.item];
        int sz = s.size > 0 ? s.size : g_iconPx;
        int icx = (s.rc.left + s.rc.right) / 2 - sz / 2;
        int icy = (s.rc.top + s.rc.bottom) / 2 - sz / 2;""",
    """        Item& it = g_items[s.item];
        int sz = s.size > 0 ? s.size : g_iconPx;
        int cellLeft = s.rc.left;
        if (g_reordering && it.animX > -1e8f) cellLeft = (int)lroundf(it.animX);
        int icx = cellLeft + (s.rc.right - s.rc.left) / 2 - sz / 2;
        int icy = (s.rc.top + s.rc.bottom) / 2 - sz / 2;""",
    'draw at the animated position')

# ---------------------------------------------------------------- 5. the dragged icon on top
sub(
    """    if (g_cfg.debugBeacon) {""",
    """    if (g_reordering && g_reorderItem >= 0 && g_reorderItem < (int)g_items.size()) {
        // The pressed icon: 1.34x, follows the cursor along the strip only, drawn above the
        // others. Clipped to [0, chevron.left): the container edge on the left and the grid
        // button on the right, which is the boundary the user defined.
        Item& it = g_items[g_reorderItem];
        int sz = (int)(g_iconPx * kReorderZoom + 0.5f);
        POINT cp{};
        GetCursorPos(&cp);
        ScreenToClient(g_hwnd, &cp);
        int left = cp.x - sz / 2;
        int top = (h - sz) / 2;
        int clipL = 0, clipR = w;
        for (size_t i = 0; i < g_slots.size(); i++)
            if (g_slots[i].item < 0) { clipR = g_slots[i].rc.left; break; }   // the grid button
        // a soft lift so it reads as "picked up"
        FillRound(g_memDC, RECT{left, top, left + sz, top + sz}, RadiusFor(sz, sz) / 2 + 2,
                  ((DWORD)g_cfg.hoverAlpha << 24) | 0x00FFFFFF);
        if (!it.px.empty() && it.cachedPx > 0) {
            const uint32_t* sp = it.px.data();
            const int sdim = it.cachedPx;
            for (int y = 0; y < sz; y++) {
                int dy = top + y;
                if (dy < 0 || dy >= h) continue;
                int sy = (int)((y + 0.5f) * sdim / sz);
                if (sy >= sdim) sy = sdim - 1;
                for (int x = 0; x < sz; x++) {
                    int dx = left + x;
                    if (dx < clipL || dx >= clipR) continue;
                    int sx = (int)((x + 0.5f) * sdim / sz);
                    if (sx >= sdim) sx = sdim - 1;
                    uint32_t c = sp[(size_t)sy * sdim + sx];
                    if (c >> 24) SetPixelPremul(dx, dy, c);
                }
            }
        }
    }
    if (g_cfg.debugBeacon) {""",
    'draw the dragged icon on top')

# ---------------------------------------------------------------- 6. start/stop the animation
sub(
    """                            g_reordering = true;
                            g_reorderItem = g_pressItem;""",
    """                            g_reordering = true;
                            g_reorderItem = g_pressItem;
                            for (auto& it : g_items) it.animX = -1e9f;   // snap on first layout""",
    'reset the animation when the reorder starts')

# ---------------------------------------------------------------- 7. hysteresis in the hit test
sub(
    """                int over = -1;
                for (size_t i = 0; i < g_slots.size(); i++) {
                    if (PtInRect(&g_slots[i].rc, q)) { over = (int)i; break; }
                }""",
    """                // The dragged icon lives at the row's centre line, so only x matters here;
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
                }""",
    'hysteresis on the target cells')

# ---------------------------------------------------------------- 8. do not rebuild mid-drag
sub(
    """            if (g_alpha > 0) {
                if (cursorMoved || movedNow) UpdateHoverFromCursor();""",
    """            if (g_alpha > 0 && !g_reordering) {
                if (cursorMoved || movedNow) UpdateHoverFromCursor();""",
    'no hover updates while reordering')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak25')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
