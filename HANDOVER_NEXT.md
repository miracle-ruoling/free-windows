# 交接：下一轮从这里开始

> 写于 2026-11-15 18:20（本轮把"固定 Windows 按钮（开始菜单 / Win+X）"做完并自测通过）。
> 上一轮（图标拖动重排 + 动效 + 边界滚入）的过程在 `HANDOVER_TODO_GLASS_LAG.md` §4.10–§4.17，
> **别重读历史排查**，看本文即可。
> 工作目录已从 `common_workspace` 改名为 `fly_bar`（`C:\Users\20979\RP_Projects\fly_bar\`），
> 文档里的旧路径已全部改过来。

---

## 0. 三分钟版本

- 项目：`dock/`（一个自绘的 Win11 图标条 + 托盘宫格），源码 `dock/dock.cpp` 单文件 ~7100 行。
- 本轮之前的**大坑已经全部收尾**：玻璃背景"位移/抖动"的根因是
  "`UpdateLayeredWindow` 的矩形和像素没落在同一次合成里"，修法是 `presentSync=2`
  （ULW **之前** `DwmFlush()`）。**这一条别动**。
- 现在条的性能：静止 16–20 次抓图/秒（每帧合成 0.37 ms）、拖动 115–119 次重绘/秒、
  每帧 `paint≈1.3 ms`、`present≈0.2 ms`。本轮加的四方块 logo 相当于多画一个图标，量级不变。
- 本轮新增：**第一格固定 Windows 按钮**——左键开始菜单、右键 Win+X；和 `^` 一套槽位规则
  （不滚动、抓不走、不能插到它前面）。见 **§3.2**。
- **这轮最重要的结论**：开始菜单 / Win+X 都是 shell 的 XAML 窗口，**外部进程搬不动位置**
  （`SetWindowPos` 成功但画面一像素不动）。所以"把弹窗迁到条附近"没做成，
  用户 2026-11-15 选的是"先按原生位置弹"。细节与证据见 §3.2 末尾。
- **下一步待办见 §3**：①（已修，仅留记录）被拖图标锯齿；
  ②把任务栏更多东西搬到条上（形式待定，**先和用户对齐**）。

---

## 1. 必读（按顺序，30 分钟够）

| 顺序 | 文件 / 章节 | 为什么 |
|---|---|---|
| 1 | **本文 §0–§4** | 现场、模块地图、改代码前必须知道的 8 件事 |
| 2 | `HANDOVER.md` **§1 语义模型**、**§3 关键实现**、**§5 坑（血泪清单）**、**§9 用户习惯** | 项目的基本盘；§5 里 40 多条坑不要重踩 |
| 3 | `HANDOVER_TODO_GLASS_LAG.md` **§4.10 / §4.13 / §4.15 / §4.16 / §4.17** | 玻璃延迟的最终结论、混色搬进抓图、透明档热区、重排与动效 |
| 4 | `HANDOVER.md` §6 代码地图 | 找函数用 |

> `HANDOVER_TODO_GLASS_LAG.md` 的 §1–§4.9、§4.12、§4.14 是**历史排查过程**（含几次错误假设）。
> 只需要知道结论；不要照着重新验证一遍。

---

## 2. 现场（2026-11-15 18:20）

| | |
|---|---|
| 构建 | `dock.cpp` → `build.ps1`（MSVC 18 / SDK 26100）→ 部署到 `%LOCALAPPDATA%\Programs\Dock\` |
| 重启 | `dev/redeploy.ps1`：关掉 dock → 复制 exe → **通过 explorer.exe 拉起**（必须，低完整性会自愈但会闪一下）。**先杀 dock 再 build**，否则 `build.ps1` 的复制会报"文件被占用"（`cl.exe` 已经产出新 exe，但脚本以错误退出） |
| 条 | 本轮实测 `x=872 y=40 w=665 h=121`（用户会自己摆/改宽度，别当成固定值） |
| ini | `material=1 / glassOpacity=1 / tintStrength=0 / lightMode=1 / tint=#A6101010 / blurRadius=0 / refreshHz=144 / captureHz=20 / presentSync=2 / presentOrder=0 / debugBeacon=0 / radius=77 / pad=10 / maxIcon=72` |
| git | 仓库在 `dock/`，`.gitignore` 已覆盖产物/截图/帧转储 → **`git add -A` 就够** |

最近提交（倒序）：`2d9941f` 首格固定 Windows 按钮 → `1b33eab` 文档：§4.18 被拖图标锯齿 →
`ef19e64` 修锯齿 + 交接文档 → `1bee953` 重排不跟手的修复 → `1761d5f` 重排动效+边界滚入 →
`c9c3e03` 重排本身 → `66d849c` 混色搬进抓图 → `c8fcaf1` 拉伸闪烁 → `15badf9` 存档点。

---

## 3. 下一步

### 3.1 被拖图标"变糊/锯齿" —— **本轮已修，只留记录**

现象（用户）：长按拖动时图标保持悬浮放大尺寸，但**明显变糊**，圆形图标（Clash Verge）变成
肉眼可见的少边多边形，边界锯齿，内部线条也锯齿。

根因：`Paint()` 里画被拖图标用的是我手写的**最近邻采样**循环（1.34× 直接取一个源像素），
而正常悬浮放大走 `BlendScaled()`（双线性）。

修法（`patch27.py`）：给 `BlendScaled()` 加一个可选的**水平裁剪**参数 `clipL/clipR`
（被拖图标要按 `[容器左边, 宫格按钮左边)` 裁剪），被拖图标改走它。

验证：`dev/drag_icon_full.png` / `dev/drag_icon_zoom.png`（放大后边缘平滑，无锯齿）。
**如果用户仍说不清楚，先确认他看的是"被拖的那个"而不是邻居。**

### 3.2 Windows 按钮（第一格固定 / 左键开始菜单 / 右键 Win+X）—— ✅ 本轮完成

**语义（用户 2026-11-15 拍板）**
- 位置：条的**第一格**，和 `^` 完全同一套槽位规则——**不参与滚动、不能被长按抓走重排、别的图标
  不能插到它前面**；它的**右边界**和 `^` 的**左边界**一样，是图标区的硬边界（拖动重排时超出就裁掉）。
- 左键 = 开始菜单；右键 = Win+X（电源用户菜单）。**两个弹窗都是 shell 自己的窗口**，我们只发命令，
  不自绘窗口（用户明确要求）。
- 图标：Win11 的四方块 logo 系统资源里没有（是 XAML 画的），所以自己画（见下）。

**实现落点（`dock.cpp`）**
- 槽位哨兵：`kSlotChevron = -1`、`kSlotWin = -3`。**注意**：以前所有 `item < 0` 都当成"宫格按钮"，
  现在必须按哨兵判（`GridPlacement()`、拖动裁剪、边界滚动这三处都改过，漏一处宫格会锚到首格）。
- `ComputeButtons()`：`show = cap - 1 - (needExpand ? 1 : 0)`（Win 占一格、`^` 占一格），
  `g_pageItems = show`（滚轮翻页/边界滚动的步长，原来写的是 `g_capacity - 1`）；
  首格尺寸也吃 hover 放大（`g_slotHover[0]`），所以它和普通图标一样会长大、邻居让位。
- `Paint()`：`kSlotWin` → `PaintWinButton()`（四个圆角方块，白 `0xF0FFFFFF`，和雪佛龙同色；
  跨度 92%、间隙 9%、圆角 `sq/7`——按 Fluent logo 的比例，圆角再大就会糊成一块）。
  **首格不画 hover 白底**（白底 + 白方块会糊成一坨，1.34× 放大就是反馈），其它槽位照旧；
  拖动重排的裁剪范围改成 `[win.right, chevron.left)`。
- 点击：`WM_LBUTTONUP` 命中首格 → 先 `GridHide`（和原生"点开始收起托盘面板"一致）再 `OpenStartMenu()`；
  `WM_RBUTTONUP` 命中首格 → `OpenPowerUserMenu()`（不进 dock 自己的菜单）。
- 排版日志（**新**，脚本靠它定位，别再按公式推）：`layout: cap=8 show=6 cells=8 scroll=0 items=11
  win=23,24-95,96 chevron=569,24-641,96 icon=72`，只在几何变化时打一条。

**两个命令的细节与实测**
- 左键用 **Ctrl+Esc** 而不是 Win：同一个开始菜单，但不会惊动 `taskbar-hidden-until-win` 这个 mod
  （它只看 Win 键）。实测 3 次：任务栏窗口全程停在 `y=1078`（屏幕外），开始菜单正常弹出。
- 右键必须真的按 Win（`keybd_event`：Win down → X down/up → Win up）。实测 3 次：菜单都出来
  （`Xaml_WindowedPopupClass 222x761 @531,325`），任务栏**也没跟着滑出来**。
  仍然留了保险：`WM_TIMER 6` 在 650ms 后向任务栏的 `kTrayTimerHide`（`WM_TIMER` id=2）补一条 post，
  在就收、不在就什么都不做。

**结论：位置搬不动/搬得动，取决于**找对窗口**（2026-11-15 18:5x 修正过一版，别再重复踩）**

- ❗**先纠正上一版记录的错误**：当时我挪的是 `SearchHost.exe` 的 `1000x938` 窗口，那个是**搜索浮窗**，
  挪它当然"画面纹丝不动"。真正的开始菜单在 **`StartMenuExperienceHost.exe`** 的一个
  **`Windows.UI.Core.CoreWindow`，`1920x1020`（= 整个工作区，标题"开始"）**里，面板是画在这块
  XAML 画布上的一个 frame（默认画在 `419,82`，尺寸 `800x938`）。
  - 判据：`WindowFromPoint(600,300)` → 根窗口 = 那个 SMEH 窗口；把它 `SetWindowPos` 移动 `+120,+90`，
    面板左/右边从 `419/1221` 精确变成 `539/1341`（`dev/t_smeh_root_move.ps1`）。
  - 关掉再开会**保留**这个偏移（shell 不会重置）→ 所以"外部挪窗口"这条路必须自己负责复原。
- **Win+X 菜单**：`Xaml_WindowedPopupClass`（explorer 的 XAML 弹窗，`222x761`）。`SetWindowPos` 连矩形都不变
  （`SWP_NOSENDCHANGING` 也一样），会被弹窗放置逻辑改回去。
- 这两类窗口都**不在 `EnumWindows` 的结果里**（`WindowFromPoint` / `GetWindowRect` / `PostMessage` 正常）。
  任务栏窗口"展开状态"时也枚举不到（收起 `y=1078` 时能枚举到）→ dock 启动时 `RememberTaskbars()` 记 handle。
- **能搬到什么程度（几何事实）**：面板 `640x750` DIP，工作区 `1536x864` DIP → 纵向总余量只有
  **114 DIP**。所以"贴着条放"在纵向**放不下**（条在顶部时，面板下方/上方都塞不进 750），
  只能"横向跟随首格 + 纵向夹紧到工作区"。横向余量很大（面板宽 640，工作区 1536）。
- 参考实现：Windhawk 官方 mod **`shell-flyout-positions`**（m417z，GPLv3，v1.3 / 2026-06）已经做了
  一模一样的事——**不是 hook `SetWindowPos`**，而是
  ① hook `DwmSetWindowAttribute(DWMWA_CLOAK, FALSE)`（浮窗"要显示"的那一刻）拿窗口；
  ② 在**承载 XAML 的进程里**改布局属性：Win10 老开始菜单改 `StartDocked.StartSizingFrame` 的
     `Canvas.Left/Top`，Win11 新开始菜单改 `FrameRoot` 的 `HorizontalAlignment` + `Margin`
     （`horizontalAlignment=startButtonLeft/Center/Right` 就是用 UIA 取任务栏开始按钮的 rect 再 clamp 到工作区）。
  → 也就是说"以某个按钮为参考点"的形态已经是现成的，**只要把参考点从"任务栏开始按钮"换成"我们条的首格"**。
  源码已下到 `dev/shell-flyout-positions.wh.cpp`（2195 行，`StartMenuUI` 段是重点）。
- 仍未做：Win+X 菜单的放置逻辑在 explorer 的 XAML 弹窗引擎里，**没有参考实现**，纯逆向。
  用户 2026-11-15 决定：**先按原生位置弹**，位置的事另做（见 §3.4 的计划）。

**验证（脚本 + 截图都在 `dock/dev/`）**
- 左键：`winclick_left_after.png`（开始菜单开着、任务栏没露头）；日志 `win button: left click -> start menu (ctrl+esc)`。
- 右键：`winclick_right_after.png`（原生 Win+X 菜单：已安装的应用/电源选项/终端/设置/关机…）；
  日志 `win button: right click -> win+x menu` + `win button: hid the native taskbar again (...)`。
- 首格不掉位：滚轮 3 格后 `layout: ... scroll=3 ... win=23,24-95,96`（和 scroll=0 时同一条矩形），
  截图 `scroll_view.png`（图标已经翻过去、四方块还在最左）。
- 宫格仍锚在 `^`：`t_wingrid.ps1` → `grid 1227,169 286x296`、`inside work area=True`、`overlaps strip=False`。
- 宫格开着时点首格：日志 `grid: hide (from win button opened the start menu)` → 再开开始菜单。

**未由人手复核**
- 手感：首格 hover 放大时邻居让位是否自然；四方块的大小/间隙像不像 Win（要改就动
  `PaintWinButton()` 里那三个比例；放大 4× 的对照图 `win_btn_hover_zoom.png`）。
- 在首格上**按住拖动 = 拖整条**（和 `^`/空白处一样），不是"拖不动"。想改成只响应点击，说一声。
- logo 恒白（和雪佛龙一致）。若以后换成浅色壁纸看不清，可以按 `lightMode` 换成深色，或加个 ini 开关。

**测试时注意**：用户一边打字/动鼠标时，注入的 Win+X 会被他自己按下的键**直接关掉**（实测 6 次里 1 次这样，
日志有 `right click -> win+x menu` 但截图里没有菜单）。这不是 bug；脚本连跑两次、或等他手离开再测就好。

### 3.3 把任务栏更多东西搬到条上（形式待定，**下一轮先和用户对齐**）

用户原话："将任务栏更多东西移植到我们的条上，形式暂时未定"。
**这里不要自己拍板**（用户习惯：有歧义先问）。可候选的方向，供和他讨论时列出来：

1. **一个 App 一个按钮**：现在是"一个窗口一个按钮"（`BuildItems()` 里按 hwnd 展开）。
   任务栏默认是合并的。改法：按 exe 合并 + 悬停时列出该 App 的窗口（宫格或弹出列）。
2. **窗口数量角标 / 活动指示**：任务栏的"多点"标记（`hasWindow` 现在只用来画图钉点）。
3. **进度条**：`ITaskbarList3::SetProgressValue` 的进度画在按钮底部（下载、复制时很有感）。
4. **闪烁提醒**：窗口 `FlashWindow` 时按钮高亮/跳动。
5. **显示桌面 / 任务视图 / 搜索**：条两端的系统按钮。
6. **跳转列表**：右键 App 时的"最近/常用"（现在右键是 App 自己的窗口菜单）。
7. **托盘**：已经有宫格了，不要再抄一份到条上（见 `HANDOVER.md` §3.2 的取舍）。
8. **分组悬停预览**：合并成组后，悬停出该 App 的窗口列表缩略图（现有 `ThumbShow` 可复用）。

注意几件事：①条上只有 ~13 个格子（`cap = (W-2*pad+gap)/cell`），任何"更多东西"都要考虑它挤谁；
②任何新按钮都要进 `ComputeButtons()` 的槽位体系，否则 `g_slots`/点击/缩略图全不对；
③透明档（`glassOpacity=0 && tintStrength=0`）里**空白像素收不到鼠标事件**（见 §4.3），
新加的东西必须是"不透明像素"才点得到。

### 3.4 浮窗锚点：把 shell 弹窗放到条上的按钮旁边（**A 方案进行中，dock 侧已完成**）

用户 2026-11-15 决定：走 A（fork mod），而且**不要只为首格写死**——以后可能加"音量/网络"按钮
（Win+A 快速设置）之类，机制必须能复用。

**dock 侧（已完成、已实测）**
- `Local\DockAnchor_v1`（`DockAnchorShm`，`magic='DANK'` = `0x4B4E4144`，size 720B）：
  dock 用**空 DACL** 自己创建并一直持有 handle（写法与 `TrayBridgeEnsureExists()` 相同），
  结构 = `{magic, version=1, count, updatedMs, entries[16]}`，
  每条 = `{kind, flags, left/top/right/bottom（屏幕物理像素）, gapPx, pad[4]}`。
- kind：`1 = 开始菜单`、`2 = 快速设置（音量/网络，Win+A）`、`3 = 通知中心`（后两个是预留位）。
- `PublishAnchors()` 在 `ComputeButtons()` 末尾和 `OpenStartMenu()` 之前各调一次，
  只写有变化的项；**dock 退出 → 共享块随之消失 → mod 侧自动退回原生位置**（不存在脏数据）。
- 实测：`dev/anchordump.ps1` 从另一个进程读到了 `magic=0x4B4E4144 version=1 count=1
  kind=1 rect=731,-1-798,66 gap=8`，`sizeof(Table)=720` 与 mod 侧一致。

**mod 侧（已写好，**还没编译**）**：`windhawk/dock-flyout-anchor.wh.cpp`
（fork 自 m417z 的 `shell-flyout-positions` v1.3，GPLv3，署名保留；原文件留在
`dev/shell-flyout-positions.wh.cpp` 供对照）
- 新增 `dock` 对齐值：`startMenu.horizontalAlignment/verticalAlignment`、
  `actionCenter.horizontalAlignment`、`notificationCenter.horizontalAlignment`；
  新增 `dockAnchor.gap`（96-dpi 单位）。**开始菜单的默认值就是 `dock/dock`**。
- `DockAnchor::Get()`：每次按名字 `OpenFileMapping` → 读 → `UnmapViewOfFile`
  （不缓存：dock 重启/退出时立刻读不到，比缓存干净）。
- `DockAnchor::Place()`（与 dock 的 `GridPlacement()` 同源）：横向对左边缘 → 右边溢出就右对齐 →
  夹进工作区；纵向先试"按钮下方"→ 试"上方"→ 都放不下选空间大的一边 → 再夹紧。
- 落点实现：新开始菜单（`StartMenu.StartBlendedFlexFrame` / 兜底路径）改 `FrameRoot` 的
  `HorizontalAlignment=Left` + `RenderTransform.X`（横向绝对偏移）、
  `VerticalAlignment=Top` + `Margin.Top`（纵向绝对偏移），都是相对 `rcMonitor` 左上角的 DIP；
  老开始菜单（Canvas）改 `Canvas.Left/Top`；**快速设置/通知中心走 `CoreWindowUI`**：
  在进程内 hook `SetWindowPos` 改写 X/Y（`AdjustCoreWindowPos`，kind=`QuickSettings`）。
- 兜底：XAML 内容类名不是已知的那个也照样走 redesigned 路径（只找 `FrameRoot` 这个名字），
  避免 25H2 改了类名就整段失效。
- 自检日志：`%TEMP%\dock-flyout-anchor.log`（`DockTrace()`，256KB 上限；Wh_Log 只能在
  Windhawk UI 里看，写个镜像文件方便离线排查；稳定后可以删）。

**以后加一个"音量/网络"按钮要做什么（不用改 mod 代码）**
1. dock 里给它一个固定槽位（照 `kSlotWin` 的写法），点击时发 `Win+A`；
2. 在该槽位每次都 `AnchorPublish(kAnchorQuickSettings, &screenRect, 8)`；
3. Windhawk 里把 `Dock Flyout Anchor` 的 `Action Center → Horizontal alignment` 设成
   `Next to the dock button`（设完 mod 会重载，并挂上 QuickActions 的 `SetWindowPos` 钩子）。
放大到别的弹窗同理：dock 加一个 kind，mod 里加一个 `DockAnchor::Kind` 和在那个弹窗的定位路径里用 `Place()`。

**编译流程（本机没有 CLI，只能走 UI）**
1. 已经复制到 `C:\ProgramData\Windhawk\ModsSource\local@dock-flyout-anchor.wh.cpp`；
2. Windhawk UI → **Create new mod** → 名字 `Dock Flyout Anchor`（id 自动是 `dock-flyout-anchor`）；
   若编辑器里是空模板，先切到别的 mod 再切回来，让它从磁盘重载我们的源码；
3. **Compile** → **Enable**（`@include` 保持 upstream 的 4 个进程）。
4. 验证：`dev/t_anchor_check.ps1` 点首格开开始菜单并抓前后两帧 → `dev/shotdiff.py anchor_a.png anchor_b.png`
   给面板包围盒，再和 `dev/anchordump.ps1` 打印的按钮矩形对照。

**风险**：25H2 的 XAML 结构未知（类名/元素名可能又变，已加兜底但仍可能找不到 `FrameRoot`）；
每次迭代都要用户在 UI 里点一次 Compile —— 但**Windhawk 编译后会自动重新注入**（实测编译后 19 秒
mod-status 里 4 个进程的记录全刷新了），所以不用重启 explorer/SMEH；Windows 更新后可能要跟着修。

**实测（2026-11-15 20:2x，mod 0.2.0 + dock 现行版）**
- 开始菜单：`anchor kind=1 button=732,0-798,66 gap=8 -> flyout 1111x938 px at 732,74`
  （面板实际宽 1111px = 889 DIP，含右侧手机互联卡）；条被拖到 882 时右边放不下 →
  自动右对齐到 `809`。内容类名 `StartMenu.StartBlendedFlexFrame`，走 redesigned 路径。
- Win+X：`anchor kind=4 rect=723,6-795,78` → 弹窗落在 `723,86`（= 按钮左边 723、下方 78+8），
  与期望值完全一致。
- 一个已知的运行特征：explorer 会反复把 Win+X 弹窗摆回自己的位置（实测 500ms 内 8 次），
  我们的钩子每次都改写回锚点。视觉上稳定，但这意味着"我们一直在和 shell 抢"，以后如果它开始动画/抖动，
  优先看这里。

### 3.5 透明档下拉成竖条会被"压回横条"（2026-11-15 20:2x 修）

**现象**：完全透明档（`glassOpacity=0 && tintStrength=0`）把条拖成竖的，松手就弹回横的。

**根因**：松手时 `ShrinkToIcons()` 把窗口收成"图标盒"，而它读的是 **ini 里的 `dock.vertical`**
（只有 `LoadConfig()` 写、拖动过程中从不更新）→ 永远按横条算 `tw=span+2pad, th=icon+2pad`。
以前没暴露：那时 `glassOpacity=1` → `FullyTransparent()` 为假 → `ShrinkToIcons()` 直接返回，
竖窗就留着；换成全透档后这条路径才开始跑。

**修法**：方向改用**刚拖出来的形状**（`oldH > oldW`），并把 `g_cfg.vertical` 同步成同一值；
`shrink:` 日志加了 `vertical=` 字段。

**证据**：`dev/t_shrink_vertical.ps1`（把窗口直接设成 200x600，再投递"拉伸开始/结束"）→
`shrink: 200x600 -> 92x560 ... vertical=1`，`layout:` 里 chevron 在 `64,498`（竖排）；
修前同样输入得到 638x92 的横条。该脚本绕过真实鼠标（透明档空白像素会穿透、注入拖动不可靠），
验证的是"松手那一刻的收敛逻辑"，手感仍需用户确认。

---

## 4. 改代码前必须知道的 9 件事

1. **`presentSync=2`（`Present()` 里 ULW **之前** `DwmFlush()`）不是优化，是正确性修复。**
   合成器"下一帧才应用新矩形、但 layered 位图立刻生效"→ 每次移动后的 5–7 ms 是
   "新内容 + 旧几何"，表现为背景向后偏/抖动（幅度 = 速度 ÷ 重绘率）。
   改成 1（放在后面）或 0（去掉）都会复发。详见 `TODO_GLASS_LAG.md` §4.10。
2. **每帧的重活只在抓图和图标**：`CaptureBackdrop()` 一次 ~8–9 ms（屏幕回读有 ~7 ms 固定开销，
   面积再小也省不了）；`Paint()` 每帧只有 0.37 ms（混色已经烤进烘焙图，圆角/边缘光走缓存的
   `g_covMask`/`g_rimMask`）。**任何"每帧加一点计算"的改动都要先看这个预算。**
3. **抓图边距是动态的**（`g_bakeMarginUsed`）：静止 = 0（只抓条自己），拖动/拉伸 = 256
   （靠重新裁剪而不是重抓）。`covered` 是**包含**判定（不是相等），否则拉伸时会每帧重抓 → 闪。
4. **透明档的命中测试**：layered 窗口按 **alpha** 判定命中，`Paint()` 在 `noGlass` 下只画图标，
   其余像素 alpha=0 → **空白区域收不到鼠标**。所以：拉伸结束后 `ShrinkToIcons()` 把窗口收成
   "图标+pad"，热区按 pad 内缩（角=两端图标四角、上下带=中间图标上下两方）。
   同理：透明档里移动条只能抓**雪佛龙**、**Windows 按钮**或留出可见余量。
5. **`WDA_EXCLUDEFROMCAPTURE` 是全局副作用**：抓图那 ~8 ms 里别的程序（截图/录屏/共享）看不到条。
   实测用户截图**偶发缺条**。写测量脚本时必须当心：`dev/motion_probe.py` 会等参考帧里真的有条。
6. **重排状态机**（`g_reordering`/`g_reorderItem`/`g_pressItem`）三个坑：
   ①`g_pressActive` 的两处判定都要带 `!g_reordering`（否则重复开始/松手变点击）；
   ②重排期间**每帧强制 `dirty`**（鼠标移动不碰任何窗口，否则被拖图标卡住再跳）；
   ③重排期间 `UpdateHoverFromCursor()` 直接返回（否则 1.34× 悬浮会在光标下抖）。
7. **图标的绘制必须走 `BlendPremul`/`BlendScaled`**（GDI 写 32bpp DIB 会把 alpha 写 0）；
   新写的"手绘"都要用 `SetPixelPremul` 或 `BlendScaled`（后者是双线性，放大别用最近邻）。
8. **ini 的 BOM 必须保留**（`StripIniBom()`）；`WritePrivateProfileStringW` 用来写 `x/y/w/h/order/extraPins`。
9. **槽位里的 `item` 有两个负值了**：`kSlotChevron(-1)` 和 `kSlotWin(-3)`。任何"`item < 0` 就是宫格按钮"
   的老写法都会把首格当成 `^`（宫格锚点、拖动裁剪、边界滚动），要按哨兵判。
   另外 `g_capacity` 现在是**格子数**（含首格和 `^`），翻页量用 `g_pageItems`。

---

## 5. 工具（`dock/dev/`）

| 脚本 | 用途 |
|---|---|
| `redeploy.ps1` | 关 dock → 复制 exe → 通过 explorer 拉起。改完代码必跑（**先杀 dock 再 build**） |
| `abtest.py <label> k=v …` | 改 ini → 重启 → 拖动扫一遍 → 直接出结论（A/B 实验用） |
| `motion_probe.py <dir> [span] [speed] [cx0 cx1] [fast]` | 双线程：一边拖一边抓帧；带 cx0/cx1 时只抓窄带（143 Hz，避免截图撕裂） |
| `content_anchor.py <dir> cx0 cx1 [search]` | 量"玻璃内容 vs 世界"的位移（需要静态纹理的窄带；条几乎全是图标，测试时要把条拉宽） |
| `hand_capture.py <sec> <frames> <dir>` + `hand_scan2.py` | **用户自己拖**、录帧；相邻帧两两对比判断"内容锚定 / 粘窗口" |
| `draglong.ps1 -Seconds N` | 真实按住拖动 N 秒，把 10 秒统计窗口填满 |
| `acrylic_test.cpp` + `buildtoy2.ps1` | DWM 磨砂可行性验证（还没用上，见 `HANDOVER.md` §3.6 末尾） |
| **`t_winbtn.ps1 -Button left\|right`** | 【本轮】从 `layout:` 日志读首格矩形 → 真鼠标点一下 → 打印任务栏/弹窗状态 + 截图 |
| **`t_wingrid.ps1 [-KeepOpen]`** | 【本轮】按 `layout:` 的 `chevron=` 点开宫格并报告落点（旧的 `t_gridplace.ps1` 按老公式算位置，已不准） |
| **`loggrep.ps1 -Pattern <正则> -Last N`** | 【本轮】日志正经 grep。`logtail.ps1` 只给最后 25 行、而且**不认 `-Lines`**，别用它判断"有无某条日志" |
| `t_win_probe5/6.ps1` + `shotdiff.py` | 【本轮】"开始菜单窗口搬不动"的探针：probe5 移动面板窗口并前后截图，`shotdiff.py a.png b.png` 出 `changed=N` 与包围盒（实测 `changed=0 of 2073600`） |
| `t_winx.ps1 [-Move]` | 【本轮】Win+X 菜单的探针：新出现的窗口类/矩形，以及 `SetWindowPos` 后矩形是否真的变（这台机器：不变） |
| `t_winx_anchor.ps1` | 【本轮】右键首格 → 打印 Win+X 弹窗实际 rect、`kind=4` 锚点、期望落点（现在应完全一致） |
| `anchordump.ps1` | 【本轮】把 `Local\DockAnchor_v1` 的内容打出来（magic/version/count/每条 kind+rect+gap+armed） |
| `t_shrink_vertical.ps1` | 【本轮】透明档竖条验证：设成 200x600 → 投递"拉伸开始/结束" → 看 `shrink:` 选的方向 |
| `t_anchor_check.ps1` + `shotdiff.py` | 【本轮】点首格开开始菜单、抓前后两帧、用 diff 包围盒量面板位置 |
| `t_start_host_reset.ps1` | 【本轮】把开始菜单宿主窗口挪回 `0,0`（shell 不会自己复位，实验残留会一直留着） |
| `t_cloak_state.ps1` / `t_while_start.ps1` / `t_who_draws_start.ps1` | 【本轮】"谁画的面板 / 哪个窗口被 cloak"的原始探针（`WindowFromPoint` 是关键，`EnumWindows` 看不到） |
| `t_winscroll.ps1 -Notches N` | 【本轮】给条发滚轮，验证首格不动（配合 `loggrep.ps1 -Pattern "layout:"` 看 `scroll=` 与 `win=` 矩形） |
| `t_bar_handle.ps1` | 【本轮】"任务栏展开后枚举不到、但记住的 handle 仍有效"的探针（`GetWindowRect` 报 `y=1020` = 展开、`y=1078` = 收起） |
| `t_ctrlesc_hide.ps1` | 【本轮】Ctrl+Esc 开开始菜单期间任务栏是否露头（结论：不露头），以及"菜单开着时 post 隐藏没用" |

**测量心法**：静态截图看不见"只在运动中"的现象；要把"位置/内容"从**同一张合成帧**里读出来
（`debugBeacon` 临时画一个 10×10 品红块当作条体标记），或者相邻帧两两对比。
拿一分钟前的参考帧做互相关在滚动背景上会给出假峰（踩过）。

---

## 6. 用户怎么配合（`HANDOVER.md` §9 的补充）

- **有歧义先问，别猜**；把不确定的点列成选择题给他，他答得很快。
- **要结论也要证据**：日志行、截图、实测数字。他反感"看起来好了"。
- **能自己验证的绝不推给他**（编译/启动/截图/读日志/跑脚本都自己做）；
  只有**手感**类（动画节奏、跟手程度）历来只能他确认。
- 他会**同时用电脑**：注入鼠标会和手抢（`SetCursorPos` 会被他的物理鼠标覆盖），
  测试脚本要么先确认他空闲，要么在日志里甄别。
- 他喜欢**没有外围白线**的完全透明档，别为了"可见性"把白边加回来。
- 收尾时把状态写进文档（本文 + `TODO_GLASS_LAG.md`），他会在上下文快满时切会话。
