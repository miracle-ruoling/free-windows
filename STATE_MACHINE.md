# Dock 三态交互状态机（条 / 宫格 / App 右键菜单）

> 记录时间：2026-11-12 01:05。对应 `dock.cpp` 构建 2026-11-12 01:00。
> 2026-11-12 12:08 补：状态 1 多了"双击条空白处 = 快速闪避"（见 §2 最后一行，细节在 `HANDOVER.md` §8.4）。
> 这份文档只讲**可见性与收起规则**（谁在什么时候消失），不讲托盘数据、玻璃、菜单转发细节（那些在 `HANDOVER.md`）。
> 用户 2026-11-11 23:40 给出完整定义，2026-11-12 00:22 修正 3b-iv，之后按此实现并逐条验证。

---

## 0. 术语

| 词 | 含义 |
|---|---|
| **条**（strip / pill） | 对标任务栏的那条窗口（`DockStripWindow`，`g_hwnd`） |
| **宫格**（panel / grid） | 点 `^` 弹出的托盘面板（`DockGridWindow`，`g_gridWnd`） |
| **菜单** | 由 App 自己弹出、我们只负责转发右键得到的托盘菜单（我们没有它的代码） |
| `条∪宫格` | 两个窗口矩形的并集（不是"条 + 宫格都算"，是"落在这个并集里"） |
| **点中图标** | 点在条的某个按钮上，或宫格的某个格子上 |
| **没点中图标** | 落在 `条∪宫格` 内，但在格子/按钮之外（宫格内边距、条上空白、`^` 以外） |

---

## 1. 状态

```
状态 1      状态 2            状态 3
 条         条 + 宫格         条 + 宫格 + 菜单
```

状态之间只有四种转移：

```
       ^ /（宫格打开）
  1 ───────────────────► 2
  ▲                      │
  │（点外面 / 失焦 /      │（右键点中托盘图标）
  │  点 `^` / 点图标）    ▼
  └────────── 3 ◄─────────┘
       （菜单消失且用户点了菜单项 → 面板一起收 → 1）
```

---

## 2. 状态 1：只有条

| 事件 | 结果 |
|---|---|
| 光标移动 | 按**光标到条的矩形距离**调整透明度：`d <= fadeStart` 全不透明，`d >= fadeEnd` 完全透明（并 `WS_EX_TRANSPARENT` 穿透点击） |
| 失焦 | **不影响**条 |
| 左键点条上的图标 | 激活窗口 / 启动固定项 |
| 右键点条 | 弹 **dock 自己的菜单**（关闭该窗口 / 重载配置 / 打开日志 / 设置… / 开机自启 / 退出） |
| 左键点 `^` | 打开宫格 → 状态 2 |
| 左键**双击条的空白处**（内边距 / 图标之间的缝；图标和 `^` 不算） | 条以 250ms 动画移到**沿工作区中心线对称的另一边**（宽>高上下、高>宽左右；只 clamp 移动的那条轴）。**不改变状态**：仍是状态 1，宫格不弹。双击图标 / `^` 不闪避 |

---

## 3. 状态 2：条 + 宫格

| 事件 | 结果 |
|---|---|
| **a** 鼠标移动（去哪都行、失不失焦） | 条 + 宫格**都保持**。条被强制 `alpha=255`（不按距离淡出），宫格不因"光标离开"收起 |
| **b-i** 左键点 `条∪宫格` **外** | 宫格**瞬间消失** → 状态 1；条回到按距离淡出 |
| **b-ii** 左键点内、**没点中图标** | **无事发生**（条 + 宫格保持） |
| **b-iii** 左键点**中图标** | 打开对应窗口；条 + 宫格**保持** |
| **c-i** 右键点 `条∪宫格` **外** | 宫格消失 → 状态 1；条按距离淡出 |
| **c-ii** 右键点内、**没点中图标** | **无事发生**（条 + 宫格保持），且顺带把任何残留菜单关掉 |
| **c-iii** 右键点**中托盘图标** | 关掉旧菜单（若有）→ 请 App 弹新菜单 → 状态 3 |

补充：
- **宫格位置**（2026-11-12 12:46，`GridPlacement()`）：贴着 `^` 弹，不锚条的中点——横向条在条**下方**、右边缘对齐 `^`；竖向条在条**右边**、下边缘对齐 `^`；短边方向哪边放得下就哪边，两边都不行选空间大的那边。**整块必须在工作区内（硬要求）**，不与条重叠只是尽力而为。细节见 `HANDOVER.md` §3.2。
- 本条规则里 `^` 保留"开关"语义：宫格开着时点 `^` = 收起宫格（用户 2026-11-12 00:22 确认）。
- 宫格开着时双击条的空白处：条照样闪避，**宫格留在原地**（面板是独立窗口，不跟着跳）。当前行为，用户没提要求，别去"对齐"。
- "打开对应窗口" = **向 App 转发 `WM_LBUTTONDOWN/UP`**（`ForwardTrayClick()`，2026-11-12 起）。App 决定点一下是什么效果（QQ 开那个账号的聊天窗、WorkBuddy 抬主窗）；拿不到回调消息的条目才退回 `TrayActivate()`。

---

## 4. 状态 3：条 + 宫格 + App 菜单

| 事件 | 结果 |
|---|---|
| **a** 鼠标移动（去哪都行、失不失焦） | 三者**都保持** |
| **b-i** 左键点三者**外** | 菜单 + 宫格消失；条按距离淡出 |
| **b-ii** 左键点 `条∪宫格` 内、**没点中图标** | **菜单消失**；条 + 宫格保持 |
| **b-iii** 左键点**中图标** | 打开窗口；菜单消失；条 + 宫格保持 |
| **b-iv** 左键点**菜单项** | App 执行该命令并自己收菜单；**宫格也跟着消失**，条按距离淡出 → 状态 1（用户 2026-11-12 00:22 修正） |
| **c-i** 右键点三者**外** | 菜单 + 宫格消失；条按距离淡出 |
| **c-ii** 右键点 `条∪宫格` 内、没中图标 | 条 + 宫格保持；**菜单消失** |
| **c-iii** 右键点**中图标**（含同一个图标） | 关旧菜单 → 开新菜单（同一图标 = 刷新位置，走同一条路径） |
| **c-iv** 右键点**菜单本身** | 什么都不做；菜单怎么表现由 App 决定 |

**菜单自己消失的两种情况**（必须分开，否则行为会错）：

| 情况 | 判定 | 结果 |
|---|---|---|
| 用户点了菜单项 | 我们看到"按下落在菜单窗口上"（`g_menuItemPressAt`，2s 内） | 收宫格 + 菜单 → 状态 1（3b-iv） |
| App 自己收的（鼠标移开、超时、App 退出） | 没看到那种按下 | 面板保持，只清菜单状态（3a） |

> 用户 2026-11-12 00:00 说明：原生托盘里有的图标右键后鼠标移开菜单也不消失（QQ）、有的会消失（WorkBuddy），这是 App 自己实现不同。**不要**去对齐，我们只保证"我们不主动收"。

---

## 5. 失焦（唯一会"非点击"收起的条件）

失焦只在**宫格或菜单存在时**生效（状态 2/3）；状态 1（只有条）不看失焦。

> 前台窗口属于下列任一，就不算失焦：
> 1. dock 自己的窗口（条 / 宫格 / 缩略图 / 设置面板，含它们的子窗口）
> 2. dock 进程自己的窗口（例如 dock 自己的右键菜单 popup）
> 3. 正在跟踪的那个菜单所属的进程（`g_menuPid`）
> 4. **我们刚替用户操作的 App**（`g_friendPid`：`ActivateWindow()` 的目标、点条上图标激活的 App、菜单消失时的 App）
> 5. **打开宫格那一刻的前台窗口**——按 **pid** 比较（`g_fgPidAtGridOpen`），不是按 HWND。Electron 弹菜单会把焦点挪到自己另一个窗口，只比 HWND 会误判
> 6. 刚发生上述操作后 300ms 内（`g_focusGraceUntil`；启动 App 时 2s）
>
> 否则 → `focus left us` → 关菜单 + 收宫格。
> `GetForegroundWindow()` 返回 NULL 时**直接放过**（本机常见），否则会疯狂收起。

---

## 6. 实现映射（`dock.cpp`）

| 职责 | 函数 |
|---|---|
| 判定"用户按下了鼠标、按在哪" | `PressWatchTick()` + 低级鼠标钩子 `LowLevelMouseProc`（`WH_MOUSE_LL`）；`WindowFromPoint` 分类 |
| 判定失焦 | `FocusWatchTick()` |
| 这是不是我们的窗口 / 正在跟踪的菜单 | `IsOwnWindow()` / `IsMenuWindow()` |
| 关菜单（带原因日志） | `CloseMenuNow(const wchar_t* why)` |
| 收宫格（带原因日志） | `GridHide(const wchar_t* why)` —— **先隐藏再关菜单**，否则会把宫格重新提回 topmost 造成闪烁 |
| 把面板提回顶层 | `MenuRestorePanel()` |
| 菜单超出工作区 → 平移菜单窗口本身 | `FitMenuToWorkArea()` |
| 菜单压不到面板上面 → 把菜单提进 topmost | `RaiseMenuAbovePanel()`（提不动才降级面板） |
| 条强制不淡出 | `UpdateAlpha()`：`g_setWnd \|\| g_gridVisible \|\| g_menuOpen` → alpha 255 |
| 双击条空白处 → 闪避 | `IsBlankDoubleClick()`（`WM_LBUTTONUP` 里判时间/位移）+ `StartFlip()` / `FlipTick()` / `FlipEnd()`（`FlipTarget()` 算镜像点） |
| 删除掉的旧机制 | `GridTick()`（光标离开 500ms 收起）、`MenuWatchTick()`（轮询版点击检测）、右键时 `SetCursorPos`、右键时降级面板 |

### 日志关键词（排查时先搜这些）

| 日志 | 含义 |
|---|---|
| `press: left/right on our window ...` | 按在我们自己的窗口上，交给窗口过程 |
| `press: left on the app menu ...` | 按在 App 菜单上（3b-iv 的判据） |
| `left/right click outside the panel+menu at x,y over <hwnd> cls=<cls>` | 判为"点外面" |
| `grid: hide (from <原因>)` | 宫格被隐藏，`原因` = click outside / focus lost / toggle / menu item picked / panel hidden … |
| `grid: hide` **没有** 却看不到宫格 | z-order 问题：宫格被别的窗口盖住了（见 `covered` 日志），不是被隐藏 |
| `grid visible but covered at its centre by ...` | 诊断：宫格中心点被谁盖住 |
| `grid: focus at open = <hwnd> pid=<pid> '标题'` | 开宫格那一刻的前台 |
| `tray: lifting menu ... ok=1` | 菜单已提进 topmost（正常） |
| `tray: could not lift the menu - demoting the panel instead` | 提权 App，提不动，回退降级 |
| `tray: app menu is gone after a click on it - closing the panel` | 用户点了菜单项 → 面板也收（3b-iv） |
| `tray: app menu is gone - panel stays` | App 自己收的菜单 → 面板保持（3a） |
| `focus left us: foreground is <hwnd> pid=<pid> '标题'` | 失焦收起，日志直接给出"谁抢走了前台" |

---

## 7. 验证记录（都是当场日志/截图）

| 规则 | 证据 |
|---|---|
| 2a | 光标移到 (1800,1000) 1.2s 后 `gridVisible=True` |
| 2b-i / 3b-i | `left click outside ... grid: hide (from click outside)` |
| 3c-i 时延 | 三次实测 `panel invisible after 122/122/123 ms`（含注入点击自身 70ms） |
| 失焦 | Alt+Tab 后 `focus left us ... -> closing panel` |
| 2b-iii | 点 DeepSeek 格子 → `activate: alt tap ok`，1.2s 后仍 `gridVisible=True` |
| 2c-ii | `tray: right click on empty panel space - panel stays` |
| 3b-iv | 合成托盘图标：`press: left on the app menu` → `app menu is gone after a click on it` → `grid: hide (from menu item picked)`，mark 文件记到 `item1 clicked` |
| 3a | 菜单开着光标移远 1.2s，三者都在 |
| 3c-iii | cell2 右键 → cell3 右键，两次都 `watching menu window`，面板一直可见 |
| 前台 App 右键其图标 | DeepSeek 在前台时右键其格子：宫格保持 + `lifting menu ... ok=1`，截图里菜单画在宫格之上 |

---

## 8. 复测方法（脚本都在 `dock/dev/`）

```powershell
# 通用库（dot-source）
. .\statelib.ps1

# 点外面 → 面板多久收（打印 hidden after N ms）
powershell -File t_clickprobe.ps1 -WithMenu

# 右键某个 exe 的格子并点菜单项（安全验证 3b-iv 用合成托盘图标，别点真 App）
powershell -File t_fgcase.ps1 -Exe deepseek        # 右键它的格子
powershell -File t_fgcase.ps1 -Exe deepseek -Foreground   # 先把它抬到前台再右键（复现"前台 App"场景）
powershell -File t_itempick.ps1 -Exe powershell    # 需要先起 traytest.ps1

# 合成托盘图标（安全地验"点菜单项"，点了会写 traymark.txt）
powershell -File traytest.ps1
```

注意：这些脚本靠**注入鼠标**驱动，和真人操作不完全等价（见 `HANDOVER.md` §9 与正文说明）。
