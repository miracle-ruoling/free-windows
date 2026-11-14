"""Patch dock.cpp (step 2): drag an icon to the edge and the off-strip icons scroll in.

The user's rule:
  * left boundary  = the container edge (client x = 0);
  * right boundary = the left edge of the grid button (the chevron is not part of the row);
  * while dragging, the icon may hang over a boundary and is simply clipped there;
  * once more than a third of it is outside, read that as "put it outside what is visible":
    scroll one icon in from that side (nothing happens if there is nothing hidden there), and
    give the dragged icon the first / last visible slot.

Rate-limited to one step per 220 ms while the cursor stays out there, so a long move can walk
several positions but does not run away the moment the cursor touches the edge.
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


sub(
    """        if (AnimateReorder()) dirty = true;""",
    """        if (AnimateReorder()) dirty = true;
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
            for (size_t i = 0; i < g_slots.size(); i++)
                if (g_slots[i].item < 0) { clipR = g_slots[i].rc.left; break; }   // grid button
            const int thr = sz / 3;
            int overL = -left;                     // how much hangs off the container edge
            int overR = (left + sz) - clipR;       // how much hangs under the grid button
            int per = g_capacity > 1 ? g_capacity - 1 : 1;
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
        }""",
    'edge scroll while reordering')

if src == orig:
    print('nothing changed')
    sys.exit(1)
shutil.copy2(P, P + '.bak26')
io.open(P, 'w', encoding='utf-8', newline='').write(src)
print('written %s' % P)
