# 交接：下一轮从这里开始

> 写于 2026-11-15 23:40，2026-11-16 00:2x 更新（本轮做完：Win+X 锚定、**附属窗口 + 托盘三合一（R1）**、
> 快速设置面板锚定与测量；**修掉"拖条时小窗掉帧"**；**R2 组框**）。
> 上一轮（图标拖动重排 + 动效 + 边界滚入）的过程在 `HANDOVER_TODO_GLASS_LAG.md` §4.10–§4.17，
> **别重读历史排查**，看本文即可。
> 工作目录已从 `common_workspace` 改名为 `fly_bar`（`C:\Users\20979\RP_Projects\fly_bar\`），
> 文档里的旧路径已全部改过来。

> **新对话第一件事（3 分钟）**：读本文 §0 → §2 → **§3.7（小窗跟随修复 + 测量脚本）** →
> **§3.8（R2 组框）** → **§3.9（R3 组缩放）** → §4（改代码前必须知道的 11 件事）→ `PLAN_COMPANION.md`。
> 然后从 `PLAN_COMPANION.md` 的 R4（图标精细度 / 设置 UI）开始。

---

## 0. 三分钟版本

- 项目：`dock/`（一个自绘的 Win11 图标条 + 托盘宫格），源码 `dock/dock.cpp` 单文件 ~8500 行。
- 玻璃背景"位移/抖动"的根因是 `UpdateLayeredWindow` 的矩形和像素没落在同一次合成里，
  修法是 `presentSync=2`（ULW **之前** `DwmFlush()`）。**这一条别动**。
- **已经能用的**（本轮及之前）：
  - 第一格固定 **Windows 按钮**：左键开始菜单、右键 Win+X，和 `^` 同一套槽位规则（§3.2）；
  - **开始菜单 / Win+X / 快速设置** 三个 shell 弹窗都能**跟着条上的按钮**摆位置（§3.2、§3.4、§3.7）；
  - **附属窗口框架 + 托盘三合一**（网络/音量/电量）：独立小窗、真实状态、悬停 tooltip、
    点击弹快速设置、可拖动/拉伸、跟随条位移、鼠标上条淡入（§3.7、`PLAN_COMPANION.md`）。
- **本轮修掉/做完**（2026-11-16 00:0x–01:0x）：
  1. **拖条时托盘小窗像 30fps** 的遗留 bug。根因是"跟随"跑在 16 ms 的清理节流门里
     （实测小窗 40.7 次/秒 vs 条 111.4 次/秒），修法是把跟随搬进 `Present()`（每帧、和条的位移同一次合成）。
     修完 105.7 vs 105.7、偏移漂移 0 px。见 §3.7 末尾的"修复记录"。
  2. **R2 组框**：条 + 所有跟随窗口的外接矩形（+margin）画一圈 1px 圆角框，内部完全穿透，
     框内空白算"在组里"（鼠标从条走去小窗不会让小窗消失），拖小窗时框实时重算。见 §3.8。
  3. **R3 组缩放**：框的 margin 环就是把手（看不见但能抓），拖边/拖角把**每个成员的窗口矩形**按比例改
     —— 条的外框直接变，图标格数会跳（用户已同意）；对边固定；缩到成员最小值就停。见 §3.9。
  4. **快速拉框边时小窗闪没**（用户报的 bug）：可见性白名单漏了"组缩放进行中"，框边落后光标 → 误判"离开组"。
     修完同条件隐藏比例 71.7% → 0%。见 §3.9 末尾。
  5. **R4**：音量滚轮（音格上每格 ±2%）、`[traybar] radius/pad/gap` 每窗口样式覆盖、小窗右键菜单
     （跟随/重置尺寸/显示组框/Dock 设置）。用户砍掉了 wifi 格数与电量档位（三态与 tooltip 已够）。见 §3.10。
- **下一步待办**：没有排定的轮次了 —— R1–R4 全部完成。候补（要用户点头才做）：
  设置面板里给新键加行（`[group]`/`[traybar]` 目前只能改 ini + 重启）、框边悬停高亮、组内更多附属窗口。

---

## 1. 必读（按顺序，30 分钟够）

| 顺序 | 文件 / 章节 | 为什么 |
|---|---|---|
| 1 | **本文 §0–§4** | 现场、模块地图、改代码前必须知道的 9 件事 |
| 2 | **本文 §3.2 / §3.4 / §3.7** | 三个 shell 弹窗的锚定链路 + 附属窗口/托盘三合一 + **遗留 bug 的排查线索** |
| 3 | **`PLAN_COMPANION.md`**（全文，短） | 附属窗口/组的语义、ini 结构、R1 现状、R2–R4 计划、用户拍板的 8 条 |
| 4 | `HANDOVER.md` **§1 语义模型**、**§3 关键实现**、**§5 坑（血泪清单）**、**§9 用户习惯** | 项目的基本盘；§5 里 50 多条坑不要重踩 |
| 5 | `HANDOVER_TODO_GLASS_LAG.md` **§4.10 / §4.13 / §4.15 / §4.16 / §4.17** | 玻璃延迟的最终结论、混色搬进抓图、透明档热区、重排与动效 |
| 6 | `HANDOVER.md` §6 代码地图 | 找函数用 |

> `HANDOVER_TODO_GLASS_LAG.md` 的 §1–§4.9、§4.12、§4.14 是**历史排查过程**（含几次错误假设）。
> 只需要知道结论；不要照着重新验证一遍。

---

## 2. 现场（2026-11-16 00:1x）

| | |
|---|---|
| 构建 | `dock.cpp` → `build.ps1`（MSVC 18 / SDK 26100）→ 部署到 `%LOCALAPPDATA%\Programs\Dock\` |
| 重启 | `dev/redeploy.ps1`。**先杀 dock 再 build**，否则 `build.ps1` 的复制报"文件被占用"（脚本以错误退出，看起来像编译失败） |
| 条 | 实测 `x=842 y=184 w=716 h=92`（用户会自己摆，别当固定值；`layout:` 行给的是 client 坐标） |
| 托盘小窗 | 实测 `x=1369 y=270 202x60`、`follow=1`；ini 里是 **`[traybar]`** 一节（`enabled/x/y/w/h/hasPos/follow`） |
| ini `[dock]` | `material=1 / lightMode=1 / glassOpacity=0 / tintStrength=0 / blurRadius=0 / refreshHz=144 / captureHz=20 / presentSync=2 / radius=77 / pad=10 / maxIcon=72 / allowResize=1`（**全透明档** → `FullyTransparent()` 为真，`ShrinkToIcons()` 会生效） |
| ini `[group]` | `enabled=1 / margin=8 / lineAlpha=64 / lineWidth=1 / radius=12`（R2 组框 + R3 缩放把手；**margin 同时是抓取环宽度**，调成 0 = 关掉组缩放；**改完要重启 dock**） |
| ini `[traybar]` | 位置/尺寸 + `enabled/follow/hasPos`；**R4 新增样式覆盖** `radius / pad / gap`（不写或 -1 = 继承 `[dock]`；**改完要重启 dock**） |
| Windhawk mod | `fly_bar/windhawk/dock-flyout-anchor.wh.cpp`（**0.2.0**，2026-11-15 23:01 编译）；`ModsSource` 里是同一份；`@include` = explorer / ShellExperienceHost / ShellHost / StartMenuExperienceHost |
| git | 仓库在 `dock/`，`.gitignore` 覆盖产物/截图/帧转储 → **`git add -A` 就够** |

最近提交（倒序）：`（R4）音量滚轮 + 样式覆盖 + 右键菜单` → `089131d` 修快速拉框边闪没 →
`bdd8233` R3 组缩放 → `f96388f` R2 组框 → `9d9be89` 修拖条时小窗掉帧 + follow 探针 → `8d4dced` 交接文档 →
`53c27cb` 快速设置测量+挪窗口 → `2e175a4` 托盘状态轮询降频 →
`b9f6195` 去每帧日志 + mod actionCenter=dock → `ba9848e` R1 附属窗口+托盘三合一 →
`469ca7b` 计划文档 → `fb00bd1` 竖条修复 → `4f29f0a` 锚点 v2 + Win+X → `2d9941f` 首格 Win 按钮。

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

### 3.7 附属窗口 + 托盘三合一 + 快速设置锚定（R1，2026-11-15 22:0x–23:3x）

**语义**（用户原话整理，另有 `PLAN_COMPANION.md` 全文）：附属窗口是"挂在条旁边的独立小窗"，
有 `继承(follow=1)/独立(0)`；继承的跟随条位移、样式继承条、**只在鼠标上条时淡入**、
鼠标离开"条∪跟随窗口"就淡出；条自身仍按距离淡出。第一个附属窗口 = **托盘三合一**
（网络/音量/电量，整块当一个按钮，点击弹 Win+A 快速设置）。组框/组缩放是 R2/R3，还没做。

**实现落点（都在 `dock.cpp` 的 `// ---- companions` 段与 `// ---- quick settings placement` 段）**

| 项 | 关键点 |
|---|---|
| 窗口 | `DockTrayBarWindow`，`WS_EX_LAYERED｜TOPMOST｜TOOLWINDOW｜NOACTIVATE`；ini 节 **`[traybar]`** |
| 尺寸/方向 | `CompanionIconPx()` = 短边 - 2*pad，夹在 minIcon..maxIcon；`TrayCells()`：高>宽就竖排，否则横排 |
| 绘制 | **复用**条的原语：把 `g_paintBits/g_paintW/g_paintH` 临时指向自己的 DIB（和 `GridPaint()`/`SettingsPaint()` 同一招），画完换回 |
| 字形 | `Segoe Fluent Icons`；`RenderGlyphMask()` 把字形渲染成**蒙版 → 量墨迹包围盒 → 双线性缩放**到格子的 78%（不然 GDI 行高会把字形撑爆/裁掉），按 (code,px) 缓存 |
| 状态 | 网络：`WlanOpenHandle/EnumInterfaces/QueryInterface`（SSID + 信号）+ `InternetGetConnectedState` 判有线；音量：`IAudioEndpointVolume`；电量：`GetSystemPowerStatus` |
| 字形码位 | wifi `E874`、以太网 `E839`、未连接 `E871`；音量 `E992`–`E995` + 静音 `E74F`；电量 `E850`–`E859`（10 档）、充电 `E85A`–`E862`（**E863 是节能叶子，别用**） |
| tooltip | 原生 `TOOLTIPS_CLASS` + `TTF_TRACK|TTF_ABSOLUTE`；**`TTM_ADDTOOL` 只吃 `TTTOOLINFOW_V1_SIZE`（这台机器 56 字节），`sizeof(TOOLINFO)`=72 会被拒** |
| 点击 | 任意位置 → `AnchorPublish(kAnchorQuickSettings)` + `SendChord({VK_LWIN,'A'})` |
| 跟随 | `CompanionTick()` 拿条的实际窗口矩形算 delta；**隐藏时只挪记录、不动窗口**，显示时再同步一次 |
| 显隐 | `CompanionVisibilityTick()`：光标在条上 → 显示；离开"条∪跟随窗口"（外扩 6px）→ 隐藏；快速淡入淡出 ~120ms |

**两个必须记住的坑（都踩过）**

1. **layered 窗口按 alpha 命中**：字形中间是透明像素，鼠标落在"扬声器"中间会**穿透**到底下的窗口
   （第一次测试点到的是浏览器的链接提示）。修法：整块铺一层 4% 白（`0x0AFFFFFF`），肉眼看不见但整块可点
   —— 和首格 Win 按钮同一招。任何"要能点"的区域都必须有 alpha。
2. **`DLog()` 是每行 `fopen`+`fclose`**：本轮一开始我在锚点/跟随里每帧打日志（拖动时 ~1500 行/秒），
   直接把拖动打成幻灯片 + 风扇起飞。**任何每帧路径都不许打日志**（除了限流的诊断行）。

**快速设置面板的锚定（用户选了"统一规则 A" + "测量"方案 b）**

- 面板真身：**`ControlCenterWindow`（`ShellHost.exe`，480x1020 满高侧栏）**，
  不是小弹窗；**媒体播放卡片和面板是同一个窗口**（命中测试证实），用户已确认"去不掉、接受"。
- 可见内容是**窗口底部对齐**的，窗口又能自由移动（外部 `SetWindowPos` 生效），
  所以纵向靠"移动窗口"实现，但**必须知道内容框**：
  - **横向**由 mod 负责（`AdjustCoreWindowPos` 的 dock 分支，`kind=2`）；
  - **纵向**由 dock 负责：`QuickSettingsBeginPlacement()` 在点击时抓一帧全屏，
    420ms 后确认前台是 `ControlCenterWindow` → 再抓一帧 → **只在面板窗口矩形内**做差分
    → 得到内容框 → 按"内容顶端=按钮下方 8px，放不下翻到上方，再夹进工作区"挪窗口。
  - 日志：`qs: content 480x990 already at 90 (button 166..226)`。
- **几何现实**：带媒体卡片时内容是 **480×990**，屏幕 1080 → 纵向只有 90px 余量，
  所以"贴着屏幕下边界"是**几何必然**（不是 bug）；没有媒体卡片时内容 ~600 高，就会正确落到按钮下方。
- 踩过的崩：`CaptureScreenInto()` 里 `DeleteObject(bmp)` 之后才 `assign(bits…)` → 读已释放内存 → dock 崩。
  已修（先拷再删）。

**修复记录（2026-11-16 00:0x）：拖条时托盘小窗像 30fps**

用户把现象收窄成一句关键信息：**只拖小窗时是正常的，只有"拖条、条带着小窗走"时才掉帧**。
这一句直接排掉了"小窗自己的拖动路径"，把范围压到"跟随"上，答案就在 `RenderTick()` 里：

```cpp
if (now - lastWatch >= 16) { ... CompanionTick(now); ... }   // 跟随被关在 16ms 清理门后面
```

`now` 是 `GetTickCount()`（1 ms 步进），而 `lastWatch = now` 只在过门时更新 → 实际间隔退化成
**21/28 ms 一跳**；条自己的位移走 `Present()`（每帧，139 Hz）。所以"条在顺滑地走、小窗在一格一格追"。

实测（`dev/t_followfps.ps1`，同一个注入拖动同时采样两个窗口的 rect，采样 28 万次/秒）：

| | 位移更新 | 中位间隔 | 最大间隔 |
|---|---|---|---|
| 修前 条 | 111.4 次/秒 | 7.0 ms | 18.7 ms |
| 修前 小窗 | **40.7 次/秒** | **28.4 ms** | 37.9 ms |
| 修后 条 | 105.7 次/秒 | 7.3 ms | 15.0 ms |
| 修后 小窗 | **105.7 次/秒** | **7.4 ms** | 14.8 ms |

修法（三处，都是同一个语义"条位移 → 跟随窗口同帧位移"）：

1. 抽出 `CompanionFollowTo(stripX, stripY)`：按"条的最新原点 - 上次原点"的 delta 位移跟随窗口，
   记账放在同一个静态变量里，**所以一帧之内被调用两次也不会位移两次**。
2. `Present()` 里、`presentSync==2` 的 `DwmFlush()` **之后**、条自己的 `UpdateLayeredWindow` **之前**
   调它 → 条的新矩形和小窗的新矩形落在**同一次合成**里（不是"小窗晚一帧"）。
3. `FlipTick()`（双击空白处闪避动画，走的是裸 `SetWindowPos`）和条的**拉伸**分支（per-message）
   各补一次调用 —— 这两条路都不经过 `Present()`，否则同样会晚 1–2 帧。
4. `CompanionTick()` 里原来那段 delta 逻辑改成调同一个函数（作为"不经过 Present 的位移"的兜底），
   `cadence:` 10 秒统计行加了 `companion moves` 字段，以后再退化能直接看出来。

验收数据：偏移漂移 **0,0 px**（`offset at start 521,80 -> at end 521,80`），全程"相对静止偏移"
平均 **0.00 px / 最大 4 px**；拖动 10 秒 CPU **13–16% 单核**（改前同条件 13.3%，空闲 0.5%）——
每帧多一次 `SetWindowPos`，量级和文档里的 10.5% 一档，没有回到"风扇起飞"。
**手感仍需用户确认**（这是他历来只能自己判断的部分）。

**这条给以后的教训**：`RenderTick()` 里那个 16 ms 门只适合"便宜但不必精确"的清理
（状态轮询、菜单/焦点看门狗）。任何**和条的几何绑在一起**的东西都不能放进去 —— 它的实际节拍
不是 16 ms，而是 16 ms 加上 `GetTickCount()` 的量化，会到 21–28 ms。

**本轮新增的测量/操作脚本**（都在 `dev/`，别重复造）
- `t_followfps.ps1` —— **本轮的主力证据**：拖条，同时采样条与小窗的 rect，输出两者更新率、
  中位/最大间隔、相对偏移漂移；结束时**自动把条拖回原位**。（小窗只在鼠标上条时出现，
  所以脚本先把光标停到条上等淡入。）
- `t_dragfps.ps1` —— 只量一个窗口的位移更新率（`-Target traybar|strip`），用于"拖动本身是不是被节流"。
- `t_walk.ps1 -Class … -X … -Y …` —— 用真拖动把某个窗口挪到指定坐标（`SetWindowPos` 会被 ini 覆盖，
  只有走拖动路径才持久化）。抓取点默认取条的 `layout:` 里的 chevron，**但见下面的坑**。
- `t_hit_at.ps1 x y …` —— 一堆屏幕点的 `WindowFromPoint`，透明档里判断"这个像素能不能点"最快的办法。
- `tray_drag_shots.py` —— 拖某窗口边抓帧边记录的探针（模板相关性定位），留给"看屏幕到底怎么动"的场合。

**新踩的两个坑**
- **透明档里雪佛龙字形的中心是"洞"**：`^` 只有细笔画，格子中心是 alpha=0 的像素 → 注入的按下会
  **穿透**到后面的窗口（实测 `WindowFromPoint` 返回 `Chrome_RenderWidgetHostHWND`）。抓条要用
  **Win 按钮的四块白方块**（client 46,46）或先让它 hover 出底色，别按字形中心。
- **注入脚本失败时一定要把左键抬起来**：我第一版在"按下没落到目标窗口"时直接 return，
  左键就一直处于按下状态，后续几次注入全部失效（表现很像"dock 卡死了"，其实只是鼠标状态脏了）。
- 旧的排查线索（已排除项：每帧日志、每帧重传位图/z 序、WLAN 每秒查询）都还是有效的历史记录，
  只是**根因不在那里**，不用再回去查。

**相关脚本**：`dev/t_traybar_probe.ps1`（窗口 rect/可见性）、`dev/t_traybar_hit.ps1`（命中测试）、
`dev/t_traybar_drag.ps1`（真鼠标拖动并打印前后 rect）、`dev/t_qs_watch.ps1`（点小窗 + 观察前台）、
`dev/loggrep.ps1`（**正经 grep 日志**，`logtail.ps1` 只给 25 行且不认 `-Lines`）、`dev/anchordump.ps1`（锚点表）。

---

### 3.8 组框 R2（2026-11-16 00:2x）

**语义（用户 2026-11-16 00:1x 原话整理 + 5 个拍板）**
- 平时**只有条**按鼠标距离淡出淡入；组里的其他小窗**只有在鼠标上条**（= 用户想跟 dock 交互）时才**迅速淡入**，
  而且**只有鼠标移出组框**才淡出 —— 这样"从条走去看小窗"的路上不会让小窗在光标底下消失。
- 拍板：①**框内空白算"在组里"**（严格按上面那条，副作用是框很大时那片空白会让条保持不透明）；
  ②框线 **1px / 圆角 12 / 白色 ~25%**；③本轮**只做框**（出现、穿透、显隐联动），拖框边缩放留到 R3；
  ④组里只有条时**不画框**；⑤拖/拉小窗时框**实时**跟着变。

**实现落点（`dock.cpp` 的 `// ---- group box (R2)` 段，紧跟 companions 之后）**

| 项 | 关键点 |
|---|---|
| 数据 | `GroupBox g_groupBox`；ini 新节 **`[group]`**：`enabled/margin/lineAlpha/lineWidth/radius`（默认 1/8/64/1/12，**改完要重启**） |
| 几何 | `GroupBoxMembers()` = 条 + 所有 `enabled && follow` 成员的**外接矩形**；`GroupBoxRect()` 再外扩 `margin`；没有 follow 成员 → false（= 不画） |
| 窗口 | `DockGroupBoxWindow`，`WS_EX_LAYERED|TOPMOST|TOOLWINDOW|NOACTIVATE|`**`TRANSPARENT`**，**尺寸就是框矩形**（不做全屏窗口） |
| 绘制 | `FillRoundRing()`（新原语，和 `FillRound` 同一套子像素覆盖：外圆角距离 - 内缩圆角距离 = 环）；**只扫边框带**（`radius+lineWidth+2` 厚），成本按周长算；内部严格 alpha=0 |
| 同帧跟随 | `CompanionFollowTo()` 里多一句 `GroupBoxTranslate(dx,dy)`：条一帧移动多少，框就平移多少（**同一份 delta 记账**，和第 3.7 的修复同一个位置） |
| 实时重算 | 成员被拖动/拉伸、条的尺寸变化（`CompanionTick` 里的尺寸比较兜底）、组刚显示 → `GroupBoxRecompute()` |
| 显隐 | `CompanionVisibilityTick()` 里：`GroupBoxRect()` 就是"在组里"的判据（框内空白也算）；框的 alpha 和小窗用**同一个 target、同一个步进**（~120ms）；z 序 条 > 小窗 > 框 |
| 输入 | `WM_NCHITTEST → HTTRANSPARENT` + `WS_EX_TRANSPARENT`：本轮框**一点点击都不吃**（连 1px 线也不吃）。R3 把边线变成缩放把手时要**去掉 `WS_EX_TRANSPARENT`** 并改 `HTCLIENT` |

**证据（都在 `dev/`）**
- `t_groupbox.ps1`：`geometry matches the members + margin 8: True`；框内 `WindowFromPoint` → 底下的窗口（条/Chrome）；
  **鼠标停在框内空白处（826,292）→ 框和小窗都还 visible**；离开框 25px → 两者都 `visible=False`。
- `t_followfps.ps1`（现同时采三个窗口）：拖条时 `strip 102.1/s | companion 102.1/s | frame 101.4/s`，
  `frame mean 0.01px max 4px`，结束时 `frame 798,136-1543,298 expected ... -> exact`。
- `t_groupbox_live.ps1 -Dx 150 -Dy 80`：约 100 万个采样里 **2036 个（0.2%）偏离 >1px，分 3 段**（约 10ms 总计）
  —— 就是"逐条消息重算"的 1–2 帧中间态；若是松手才重算会是一整段 1.2s。
- 外观：`dev/groupbox_corner.png`（框左上角 8× 放大：1px、圆角 12、~25% 白，抗锯齿无台阶）。
- 开销：空闲 0.6–0.9% 单核（改前 0.5%）；拖条 10 秒 13–19%（改前 13–16%，窗口不同不可精确对比，同档）。
  框的窗口在隐藏时**零成本**（只在 `CompanionTick` 里被 `GetWindowRect` 顺手看一下尺寸）。

**这轮踩到/要注意的**
- 框窗口**必须** `WS_EX_TRANSPARENT`（R2 时的做法）：否则 1px 边框线会吃掉点在那条线上的点击
  （`WindowFromPoint` 会返回框自己；实测加了之后返回的是底下窗口）。
  → **R3 推翻**：框是缩放把手了，`WS_EX_TRANSPARENT` 已去掉，改成"只有 margin 环有 alpha"。见 §3.9。
- `FillRoundRing` 千万别写成整块遍历：框可以到 900×300，成员一拖动就是**每条消息**一次重绘。
- 框的几何**不能**用"当前 GetWindowRect(条)"在 `Present()` 里算：那一刻条的矩形还是旧的（ULW 还没跑），
  只能用 delta 平移（`GroupBoxTranslate`）。重算只在"事件"里做（显示、成员拖动/拉伸、条的尺寸变化）。

---

### 3.9 组缩放 R3（2026-11-16 00:3x–00:4x）

**语义（用户 2026-11-16 原话 + 3 个拍板）**
- 原话："组缩放时将组在长、宽上的变化比例也应用给条的外框……目前是全透明的，条外框也透明，
  且调整完会 shrink，所以会只感觉到图标变多/少的抖动，但是实际上非完全透明的时候条外框不会 shrink，
  能看到条外框连续正常变化，所以**图标抖动无所谓，允许它抖动**。"
  → 做法就是**直接按比例改每个成员的窗口矩形**，不去算"图标该多大"。
- 拍板：①拖边 = **对边固定**；②缩到最小时**停在最小值**（拒绝继续缩）；③（R2 已定的）框内空白算"在组里"。

**实现落点（`dock.cpp` 的 `// ---- group scaling (R3)` 段）**

| 项 | 关键点 |
|---|---|
| 抓取环 | `GroupBoxGrabBand()` = `min(margin, 10)`，**画在 margin 里**（所以永远盖不到成员）；像素 alpha **4**（≈1.6% 白，看不见）——layered 窗口按 alpha 命中，**"看不见但能抓"必须有非零 alpha** |
| 命中 | 去掉 `WS_EX_TRANSPARENT`；`WM_NCHITTEST` 只在环上返回 `HTCLIENT`，其余 `HTTRANSPARENT`；`WM_SETCURSOR` 给四个 size 光标 |
| 状态机 | `BoxScale`：`box0/strip0/comp0/origin/edges`（bit 1/2/4/8 = 左/右/上/下，和条自己的 `EdgeAt` 同编码） |
| 缩放数学 | 比例取自**成员外接框**（框矩形减去 margin），所以 margin 不参与失真；`ScaleMemberRect()` 把每个成员的原矩形映射到新外接框；对边固定 = 只改被拖那一侧 |
| 成员 | 条：`g_cfg.x/y/w/h` + `SetWindowPos`，它的 `WM_SIZE → PaintAndPresent → ComputeButtons` 自己重排（图标尺寸/格数随之变，就是"抖动"）；小窗：`CompanionSetRect(…, repaint=true)` |
| 最小值 | 每个成员的 `minIcon + 2*pad`（条和小窗自己的边拖也是这个），取最严的一侧当 `sxMin/syMin`，不够就把比例抬回去 |
| 跟随让路 | `g_boxScale.active` 时 `CompanionFollowTo()` 直接 return（否则条的位移会被再施加一次）；缩放期间由缩放代码独占所有矩形 |
| DIB | `GroupBoxEnsureDib()` 改成**只增不减 + 64px 对齐**：缩放时每条约消息都会改尺寸，重分配 800×250 的 DIB 是要命的 |

**证据（`dev/t_groupscale.ps1 -Edge right|left|bottom|corner -Dx -Dy`）**
- 右边缘 +200：`frame 773→973`，`strip ×1.264`、`companion ×1.262`，左边不动，`frame == members + margin: True`。
- 左边缘 +120：`frame 745→625`，右边缘固定在 1579 不动，`×0.835 / ×0.837`。
- 下边缘 +60：`frame 高 171→231`，条高 `92→128`、小窗高 `60→83`（`×1.391 / ×1.383`）。
- 角 +80/+40：两个轴同时缩放，几何仍 `exact`。
- 收缩 `-900`：`frame 宽 1053→159`，小窗宽正好停在 **38 = minIcon(18) + 2*pad(10)**，再拖不动 → "停在最小尺寸"。
- 条的 `layout:` 日志同步变化：`cap 9 → 10 → 11`（icon 已经顶到 `maxIcon=72`，多出来的宽度变成格子）。
- 缩放结束 `SavePosition()+SaveSize()` 落盘：ini 里 `[dock] 962,184 598x92`、`[traybar] 1402,270 169x60`，重启后原样回来。
- 环与内部的分工：`(900,320)`（框内空白，离边 66px）→ `Chrome`（穿透）；`(1000,330)`（离下边 8px，在环里）→ 框自己。

**这轮踩到的坑**
- **`WindowFromPoint` 判断不了抓取环**：环的 alpha 只有 4，`WindowFromPoint` 会报"下面的窗口"，
  但真实按下**能**抓到（用 `t_groupscale.ps1` 里 `ThreadCapture(box) == box` 验证）。别用 WindowFromPoint
  判环；判内部穿透仍然有效（那里 alpha=0）。
- 抓取环宽度 = `margin`（上限 10px）：把 `[group] margin` 调成 0 就等于关掉了组缩放。
- 组缩放期间**不能**让 follow 路径同时跑，否则小窗位移被施加两次（已在 `CompanionFollowTo` 里置空）。
- **写文档别用 `Set-Content`**（一次性把我中文全变成乱码，只能 `git checkout` 重做）：用 edit/write 工具，
  或 Python 显式 `encoding='utf-8'`。

**修掉的 bug（2026-11-16 00:44 用户报告）：快速拉框边时小窗会消失**

- 现象（用户原话）：快速拉尺寸时"会判定我鼠标超出组框，从而小窗口消失（条继续根据距离调整透明度），
  但是尺寸调整这个状态是存在的，还能继续拉动"；慢速拉动不会，即使拉很远也不会。
- 根因：`CompanionVisibilityTick()` 的"别淡出"白名单只有**小窗自己的** `dragging/resizing`，
  **没有组缩放**。框边永远落后光标一到两条消息；2800 px/s 时光标早就跑到框外 → 判"离开组"。
  慢速时落后只有几个像素，正好落在 `InflateRect(6,6)` 的滞后里，所以看不出来。
  条那边是同一个根因：`CursorInCompanionGroup()` 也返回 false → 条按距离淡出（正是他看到的"条继续按距离调透明度"）。
- 修法：新增 `GroupScaling()`（= `g_boxScale.active`），① 加进可见性白名单；
  ② `CursorInCompanionGroup()` 在缩放期间直接返回 true（条不再按距离淡出）。
- 证据：`dev/t_groupscale_fast.ps1 -Dx 700 -Ms 250`（~2800 px/s，30 万采样）：
  小窗/框隐藏比例 **71.7% → 0.0%**，且缩放全程有效；`t_groupbox.ps1` 后两段仍是"离开框 → 淡出"，
  说明白名单没有把正常淡出也堵死。

**留给用户确认的**：缩放跟手程度；条的图标格数跳动是否可接受（他说允许）；环本身完全看不见，
如果希望"鼠标靠近框边时浮出一条更亮的高亮提示"，那是一个额外的小功能（`WM_NCHITTEST` 里已经知道在不在环上）。

---

### 3.10 R4（2026-11-16 01:0x）：音量滚轮 + 每窗口样式覆盖 + 右键菜单

**用户这一轮砍掉/新增的**
- 砍掉：**wifi 格数**（只要"WLAN / 有线 / 未连接"三态，早就有了）、**电量档位**（悬浮 tooltip 就能看）。
- 澄清（本来就已经实现、不用做）：**有线切换** = 按当前连接换图标（`E874`/`E839`/`E871`）；
  **文案** = tooltip 文字（`SEU-WLAN（信号 84%）` / `以太网` / `未连接` / `音量：8%` / `音量：静音` / `电池：99%，正在充电`）。
- 新增：**悬浮在音量格上滚轮 = 每格 ±2% 音量**。

| 项 | 实现 | 证据 |
|---|---|---|
| 音量滚轮 | `WM_MOUSEWHEEL`（**注意 lParam 是屏幕坐标**）→ 只认第 2 格（音量）→ `kTrayVolumeStep=2`；往上滚时如果静音先取消静音（否则"看着没反应"）；改完立刻重画 + 刷新 tooltip + 打一条 `tray bar: wheel +2% -> 12%` 日志 | 注入 3 格：`8% → 10% → 12% → 14%`；再 −1 ×3 回到 `8%`。探针 `dev/t_wheel.ps1 -X -Y -Notches` |
| 滚轮能到未聚焦窗口 | 本机开着"悬停在非活动窗口上时滚动它"，条一直靠这条吃滚轮（翻页），小窗同理——不用 hook、不用抢焦点 | 同一次注入里先验了条：`scroll=0 → 2` |
| 每窗口样式覆盖 | 新 ini 键 **`[traybar] radius / pad / gap`**，**不写或 -1 = 继承 `[dock]`**；集中在 `CompanionPad/Gap/RadiusPercent()`，绘制、`TrayCells()`、自身最小尺寸、组缩放的最小值都走它 | 日志 `tray bar: style pad=4 gap=6 radius=200% -> corner 37 px (overrides pad=4 gap=-1 radius=200)`；恢复后 `pad=10 gap=6 radius=77% -> corner 28 px (overrides -1/-1/-1)`；截图 `dev/traybar_override.png`（pad=4 时图标明显变大） |
| 右键菜单 | `CompanionShowMenu()`：`跟随条（在组内）`（勾选）/ `重置为默认尺寸（3 格）` / `显示组框`（勾选）/ `Dock 设置…`；每项立即生效并写回 ini；`g_popupOpen` 期间抑制缩略图 | 菜单截图 `dev/compmenu_open.png`；点"显示组框"→ `group box: menu -> enabled=0`，框 `visible=True → False`；再点 → `enabled=1`，悬停条后 `visible=True` 且几何 `exact`。探针 `dev/t_rclick.ps1`、`dev/t_menupick.ps1` |
| 新增一行启动日志 | `tray bar: style pad=… gap=… radius=…% -> corner … px (overrides …)`：以后"我的 ini 到底生效了没"不用截图 | 见上 |

**坑**
- `WM_MOUSEWHEEL` 的坐标是**屏幕坐标**（其它鼠标消息是客户区），忘了转换就会"只有在某个位置滚才有效"。
- 小窗的滚轮测试必须**先把光标停在条上**再移过去：小窗隐藏时那个点上是别的窗口（第一次测试就是这么
  把滚轮发给了 Chrome，日志里什么都没有）。
- `重置为默认尺寸` 用 `kTrayCellCount*(icon+gap)-gap+pad*2`，和 `CompanionLoad()` 的默认值同一公式；
  改了公式要两处一起改。

**未由人手复核**：滚轮手感（一格 2% 是否合适）、右键菜单的排版/文案、`跟随条` 与 `重置尺寸` 两个菜单项
机器上没有点过（只点了"显示组框"，因为它可逆且不动尺寸）。

---

## 4. 改代码前必须知道的 11 件事

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
   同理（R3）：组框的**抓取环**也必须有非零 alpha（现在 4/255 ≈ 1.6% 白，看不见但能抓）；
   而且 `WindowFromPoint` 对这种极低 alpha **不可靠**（会报下面的窗口），判它要用真实按下
   （`t_groupscale.ps1` 里的 `ThreadCapture(box) == box`）。
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
10. **"和条的几何绑在一起"的东西不能放在 16 ms 的清理门后面**（本轮 bug 的根因，见 §3.7 修复记录）。
    `RenderTick()` 里 `if (now - lastWatch >= 16)` 那一段的实际节拍是 **21–28 ms**（`GetTickCount()`
    量化 + 过门才更新 `lastWatch`），只适合状态轮询/菜单看门狗这类"便宜但不必精确"的活。
    条的位移走 `Present()`（139 Hz）；附属窗口的跟随必须**跟着 `Present()` 同帧**走
    （`CompanionFollowTo()`），否则旁边一个"一格格追"的小窗会让整条看起来掉帧。
11. **组缩放（R3）期间由 `g_boxScale` 独占所有矩形**：`CompanionFollowTo()` 会让路（否则条的位移
    被再施加一次）。同理，任何"由条推导出来的几何"都不能在缩放期间自己再动一遍 ——
    缩放代码改完条/小窗以后自己 `GroupBoxRecompute()` 就把框摆正了。
    还有一条**派生**规则：凡是"指针在不在组里"的判定，在缩放期间都要短路成 true
    （`GroupScaling()`）——框边永远落后光标 1–2 条消息，快速拖动时按几何判会把整个组淡掉
    （2026-11-16 的 bug，见 §3.9 末尾）。

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
| **`t_followfps.ps1 -Dx -Dy -Ms -StepsPerSec`** | 【本轮主力证据】拖条，同时采样条与托盘小窗的 rect：两者更新率/中位间隔/最大间隔、相对偏移漂移（应恒 0）；**结束时自动把条拖回原位** |
| **`t_dragfps.ps1 -Target traybar\|strip`** | 【本轮】只量一个窗口自己的位移更新率，判断"拖动本身有没有被节流" |
| **`t_walk.ps1 -Class -X -Y [-GrabX -GrabY]`** | 【本轮】用真拖动把窗口挪到指定坐标（`SetWindowPos` 会被 ini 覆盖，只有拖动路径才持久化）。抓取点默认 `layout:` 的 chevron 中心，**但透明档里那里是字形的洞**，按不动就用 `-GrabX 46 -GrabY 46`（Win 按钮）。注意两者的抓取偏移记录时机不同（条在 `LBUTTONDOWN`、小窗在越过阈值那一下），脚本里按类偏 6 px —— 记错就会正好差 6 px |
| **`t_hit_at.ps1 x y …`** | 【本轮】一堆屏幕点的 `WindowFromPoint`：透明档里判断"这个像素能不能点"最快的办法 |
| **`t_groupbox.ps1 [-Margin 8]`** | 【R2】组框四连检查：几何 == 成员外接 + margin、内部点击是否穿透、鼠标停在框内空白处是否保持显示、离开框 25px 是否淡出 |
| **`t_groupbox_live.ps1 [-Dx -Dy]`** | 【R2】拖小窗时框是否**实时**跟随：20 万次/秒采样"框 vs 成员外接 + margin"，报告偏离 >1px 的采样数与段数（松手才重算会是一整段） |
| **`t_groupscale.ps1 [-Edge right\|left\|bottom\|corner] [-Dx -Dy]`** | 【R3】拖框的边/角缩放整组：打印三个窗口的缩放比例、对边是否固定、`frame == members + margin`；同时验证抓取环吃按下、框内空白仍穿透 |
| **`t_groupscale_fast.ps1 [-Dx -Ms]`** | 【R3 修 bug 用】快速拉框边（默认 700px/250ms ≈ 2800 px/s）时采样小窗/框的可见性，输出"拖动过程中被隐藏的采样比例"，正确的实现必须是 0% |
| **`t_wheel.ps1 -X -Y -Notches`** | 【R4】在某个屏幕点注入滚轮（正数向上）。先去把光标停在条上再移过去，否则小窗是隐藏的、滚轮会发给下面的窗口 |
| **`t_rclick.ps1 -X -Y`** | 【R4】先扫过条再右键某个点，**故意把菜单留着不关**（另一个进程截图用），再用 Esc 关 |
| **`t_compmenu.ps1 -X -Y -PickX -PickY`** | 【R4】右键开小窗菜单 + 点某一项，前后打印框的可见性（验证"菜单命令真的执行了"）。**别叫它 `t_menupick.ps1`——那个名字早就被 App 菜单探针占了** |
| **`tray_drag_shots.py`** | 【本轮】拖动时抓帧 + 记录 rect 的探针（模板相关性定位），用于"屏幕到底怎么动" |
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
| **`t_traybar_probe.ps1`** | 【本轮】打印 `DockTrayBarWindow` 的 rect / 可见性 / ex-style（判断"有没有建出来、是不是被隐藏"） |
| **`t_traybar_hit.ps1`** | 【本轮】把小窗的可见性和**命中测试**摆出来（`WindowFromPoint` 在中心点是否回到它自己） |
| **`t_traybar_drag.ps1 -Dx -Dy`** | 【本轮】真鼠标抓小窗第一格拖动 → 打印前后 rect（验证拖动 + 存档） |
| **`t_qs_watch.ps1`** | 【本轮】点小窗 → 每 120ms 打印前台窗口类/rect（看快速设置有没有弹、弹到哪） |
| `t_qs_move.ps1` / `t_qs_move2.ps1` / `t_qs_probe2.ps1` / `t_qs_vertical.ps1` | 【本轮】快速设置窗口的探针：命中测试/移动/缩放/把窗口移到负 y 看内容跟不跟 |
| `t_win_a_state.ps1` | 【本轮】Win+A 的分步状态（任务栏 y、前台类、命中点）——**Win+A 偶发不生效**时先用它** |
| `glyphsheet.py` / `glyphsheet2.py` / `glyph_tray_check.py` / `glyph_bolt_check.py` | 【本轮】把 `Segoe Fluent Icons` 的码位渲染成对照表（挑 wifi/音量/电池字形用） |

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
