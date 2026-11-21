# 交接：下一轮从这里开始

> ## 2026-11-22 00:0x：**新会话先读 `NEXT_TASKS.md`**
> 这一轮（H3 收尾 + 逐窗口玻璃参数 + 色调 + 组框角抓取）已经结束，用户确认"效果已经不错"。
> **下一轮的 5 件新任务、当前状态快照、代码地图、必须遵守的坑，全部写在 `NEXT_TASKS.md` 里** ——
> 那份是最新的入口，本文（§3.x）降级为历史查阅。
> 当前 HEAD：`78aecf2`；最新源码备份：`dock.cpp.bak52_sharedrows`。

> ## ⛔ 先读这一条（2026-11-17 16:30）
> **任务栏那一套现在是"用户确认 OK"的稳定状态，动之前必须读 §3.19。**
> 涉及：`TaskbarDenyExpansion/TaskbarDenyClear`、render tick 里的 deny 生命周期、
> `OpenPowerUserMenu()` 的 deny+`Sleep(40)`、`NativeTrayPageKeyboard()`、
> `TrayJobProc()` 里"不再弹自绘宫格"，以及 mod 里的 `g_allowOpen` latch 与
> `MouseAllowedToShow()` 的判定顺序。
> 这些地方**没有一处是多余的**：每一条都对应一个实测出来的故障（§3.17/§3.18/§3.19 有对照表）。
> 想改就先跑一遍 §3.19 末尾那 5 条判据。
> 存档：git tag **`known-good-2026-11-17-1630`**；`dock/dock.cpp.bak31_known_good_1630`；
> mod 源码快照 `windhawk/local@taskbar-hidden-until-win.wh.cpp.1.0.4_known_good`。

> **阅读顺序（新会话照这个来，别从旧文档倒着翻）**
> 1. 本文 **§0 三分钟版本**（项目是什么、什么能用、下一步做什么）
> 2. 本文 **§3.16**（托盘=原生浮窗，本轮最新、最容易踩坑：cloak 协议、为什么不能 SW_HIDE、
>    为什么必须工作线程、以及"任务栏偶发露头"的两个机制 + 待 Compile 的 mod 修改）
> 3. 本文 **§3.15**（H1 两个 bug 的结论：H1.1 = Windhawk 必须排除 `SearchHost.exe`；H1.2 = 托盘双击）
> 4. 本文 **§2 现场**（当前 ini 值、mod 版本、怎么重启）+ **§4 改代码前必须知道的 12 件事**
> 5. `PLAN_COMPONENTS.md`（**下一步的全部内容**：H2 设置按组件重构的决策 + H3 玻璃共享快照设计）
> 6. 需要时再看：本文 §3.11–§3.13（组/浮窗几何、设置面板结构）、`PLAN_GROUP.md`、`PLAN_COMPANION.md`
> `HANDOVER_TODO_GLASS_LAG.md` 只当历史查，不要重读 §1–§4.9。
> **待用户做的一件事**：**可选** Compile 一次 `Taskbar hidden until Win` **1.0.3**
> （`windhawk/local@taskbar-hidden-until-win.wh.cpp`，已同步到 `C:\ProgramData\Windhawk\ModsSource\`）。
> 1.0.3 只把共享块（deny/allow）的读取从"20ms 缓存"改成"每次直读"，纯稳健性；
> **现在装的 1.0.2 + dock 侧 40ms 余量已经能挡住 Win+X**，不编也不影响主 bug 的修复。
> 主 bug 结论在 **§3.17**：Win+X 会真的把任务栏抬起来 + 展开许可死锁 + cloak 掩盖"已经站起来"的栏。
> **下一轮第一件事**：`^` 的 native flyout 现在会退回自绘宫格（`Win+B` 在这台机器上当前完全不生效，
> 与 mod 无关，实测见 §3.17），先杀 `StartMenuExperienceHost` + `SearchHost` 再复测。

> 写于 2026-11-15 23:40，2026-11-16 18:3x 更新（R1–R4、G1–G3 全部完成；
> **下一步的计划写在 `PLAN_COMPONENTS.md`：两个 bug 修复 + 设置按组件重构**）。
> 上一轮（图标拖动重排 + 动效 + 边界滚入）的过程在 `HANDOVER_TODO_GLASS_LAG.md` §4.10–§4.17，
> **别重读历史排查**，看本文即可。
> 工作目录已从 `common_workspace` 改名为 `fly_bar`（`C:\Users\20979\RP_Projects\fly_bar\`），
> 文档里的旧路径已全部改过来。

> **进度（2026-11-20 21:4x）**：H2a、H2b 已完成；H3 的第一步（共享抓图管道 `BakeGlass()` + 浮窗真玻璃 +
> 每帧预算 `captureBudgetMs`）也已完成并验证 —— **当前状态看 §3.23**。
> **接下来（按顺序）**：①H3c（拖动时的"冻结全工作区快照" + `dragNoCapture`）；②`bgMode=图片`；
> ③`PLAN_COMPONENTS.md` §3.4 的 A10 三个小问题（玻璃层 vs 图片背景的正交关系）；
> ④§3.16 末尾那条"任务栏偶发露头"的 mod 修改**等用户 Compile**。

---

## 0. 三分钟版本

- 项目：`dock/`（一个自绘的 Win11 图标条 + 托盘宫格 + 若干可拖动小浮窗），源码 `dock/dock.cpp`
  单文件 ~10000 行。
- 玻璃背景"位移/抖动"的根因是 `UpdateLayeredWindow` 的矩形和像素没落在同一次合成里，
  修法是 `presentSync=2`（ULW **之前** `DwmFlush()`）。**这一条别动**。
- **已经能用的**（本轮及之前）：
  - 第一格固定 **Windows 按钮**：左键开始菜单、右键 Win+X，和 `^` 同一套槽位规则（§3.2）；
  - **开始菜单 / Win+X / 快速设置** 三个 shell 弹窗都能**跟着条上的按钮**摆位置（§3.2、§3.4、§3.7）；
  - **附属窗口框架 + 托盘三合一**（网络/音量/电量）：独立小窗、真实状态、悬停 tooltip、
    点击弹快速设置、可拖动/拉伸、跟随条位移、鼠标上条淡入（§3.7、`PLAN_COMPANION.md`）；
  - **组**（R2/R3/G1/G2）：外接矩形 + margin 的 1px 框、内部是不可见但可点的板面（拖整组/右键组菜单）、
    margin 环缩放整组、`屏蔽缩放`/`屏蔽位移`、多组（组 1 = 默认组含条，小窗右键 `组 ▸` 换组）；
  - **设置面板**（G3）：顶部页签 `全局 / 条 / 托盘 / 组 N`，每行绑一个 ini 键，高度随页自适应，
    从哪个窗口的菜单进就落在哪一页。
- **下一步（`PLAN_COMPONENTS.md`）**：
  1. **两个 bug**：①开始菜单里点搜索框/按任意键就消失（预期能直接输入；首要怀疑 Windhawk mod 的
     XAML 改写把"视觉位置"和"输入/焦点"拆开了）；②原生托盘里"要双击"的程序在宫格里点不开。
  2. **设置按组件分**：改名 `浮窗 / 图标条 / 玻璃`；页签由"这个对象有哪些组件"决定
     （条 = 浮窗+图标条+玻璃，玻璃浮窗 = 浮窗+玻璃，非玻璃浮窗 = 只有浮窗）；
     浮窗页放每窗样式（背景类型/颜色/圆角/内边距/淡出距离），玻璃页放**全局唯一**的玻璃参数。
  3. **玻璃共享快照**：多个玻璃窗口共用一份（建议全屏）快照，各自裁剪烘焙 —— 同时消灭
     "拖动超过 256px 边距就用旧快照"的老问题。

---

## 1. 必读（按顺序，30 分钟够）

| 顺序 | 文件 / 章节 | 为什么 |
|---|---|---|
| 1 | **`PLAN_COMPONENTS.md`（全文）** | **下一轮要做的全部内容**：两个 bug（开始菜单输入 / 托盘双击）+ 设置按组件重构 + 玻璃共享快照 |
| 2 | **本文 §0–§4** | 现场、模块地图、改代码前必须知道的 12 件事 |
| 3 | **本文 §3.11–§3.13** | 组实体化 → 多组 → 设置面板（当前的组/浮窗/面板结构都在这三节） |
| 4 | **本文 §3.2 / §3.4 / §3.7** | 三个 shell 弹窗的锚定链路（**开始菜单那个 bug 要看这三节**）+ 附属窗口 + 跟随修复 |
| 5 | **`PLAN_COMPANION.md`**（短） | 附属窗口/组的语义、ini 结构、R1–R4 的取舍 |
| 6 | `HANDOVER.md` **§1 语义模型**、**§3 关键实现**、**§5 坑（血泪清单）**、**§9 用户习惯** | 项目的基本盘；§5 里 50 多条坑不要重踩 |
| 7 | `HANDOVER_TODO_GLASS_LAG.md` **§4.10 / §4.13 / §4.15 / §4.16 / §4.17** | 玻璃延迟的最终结论、混色搬进抓图、透明档热区、重排与动效 |
| 8 | `HANDOVER.md` §6 代码地图 | 找函数用 |

> `HANDOVER_TODO_GLASS_LAG.md` 的 §1–§4.9、§4.12、§4.14 是**历史排查过程**（含几次错误假设）。
> 只需要知道结论；不要照着重新验证一遍。

---

## 2. 现场（2026-11-16 18:3x）

| | |
|---|---|
| 构建 | `dock.cpp` → `build.ps1`（MSVC 18 / SDK 26100）→ 部署到 `%LOCALAPPDATA%\Programs\Dock\` |
| 重启 | `dev/redeploy.ps1`。**先杀 dock 再 build**，否则 `build.ps1` 的复制报"文件被占用"（脚本以错误退出，看起来像编译失败） |
| 条 | 实测 `x=464 y=-27 w=793 h=114`（用户会自己摆，别当固定值；`layout:` 行给的是 client 坐标） |
| 托盘小窗（浮窗） | 实测 `x=1282 y=-15 262x93`、`follow=1 group=1`；ini 里是 **`[traybar]`** 一节 |
| ini `[dock]` | **玻璃档已开**：`material=1 / lightMode=1 / glassOpacity=65 / tintStrength=148 / tint=#A6101010 / blurRadius=6 / refreshHz=144 / captureHz=20 / presentSync=2 / radius=77 / pad=10 / maxIcon=72 / hoverMs=150 / fadeStart=0 / fadeEnd=80`。⚠️ **不是全透明档了**（2026-11-16 傍晚用户自己打开的）→ `FullyTransparent()` 为假、`ShrinkToIcons()` 不生效、**抓图管线在跑**（这正是 §3 想改的部分） |
| ini `[group]` | `enabled=1 / margin=8 / lineAlpha=183 / lineWidth=1 / radius=22 / blockResize=1 / blockMove=1`（后四项是用户自己调的：线更亮更圆，**两个屏蔽开关都开着** → 拖任何成员都是拖整组，测试时注意） |
| ini `[traybar]` | 位置/尺寸 + `enabled/follow/hasPos` + **`group=N`**（1=默认组，0=独立，N=第 N 组）+ 样式覆盖 `radius=-1 / pad=-1 / gap=13`（-1 = 继承 `[dock]`）；**改完要重启 dock** |
| ini `[group.N]` | G2 起每组一节（组 1 仍是 `[group]`），由组菜单/面板直接读写 |
| Windhawk mod | `fly_bar/windhawk/dock-flyout-anchor.wh.cpp`（**0.2.0**，2026-11-15 23:01 编译）；`ModsSource` 里是同一份；`@include` = explorer / ShellExperienceHost / ShellHost / StartMenuExperienceHost |
| **Windhawk 全局排除（必需）** | `HKLM\SOFTWARE\Windhawk\Engine\Settings\Exclude` 里**必须有 `SearchHost.exe`**。否则 `windhawk.dll` 会被注入 SearchHost，**Windows 搜索面板整体出不来**（点开始菜单的搜索框/按任意键 → 开始面板直接被换掉然后什么都没有；`Win+S` 也空白）。上游 issue #389 / #560，详见 §3.15 |
| git | 仓库在 `dock/`，`.gitignore` 覆盖产物/截图/帧转储 → **`git add -A` 就够** |

最近提交（倒序）：`（计划）PLAN_COMPONENTS.md` → `bafff34` G3 设置面板 → `f393f4a` 修组拖动只动条 →
`4800ad5` G2 多组 → `4e98f96` 修拖组时玻璃抖 → `d41d2ca` G1 组实体化 → `6826a09` 组计划 →
`ecb1952` R4 音量滚轮+样式覆盖+右键菜单 → `089131d` 修快速拉框边闪没 → `bdd8233` R3 组缩放 →
`f96388f` R2 组框 → `9d9be89` 修拖条时小窗掉帧 → `8d4dced` 交接文档 →
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

### 3.11 G1 组实体化（2026-11-16 14:2x–14:3x）

**语义（用户原话 + 7 个拍板，详见 `PLAN_GROUP.md`）**
- 组内空白按住拖动 = 移动整组；空白右键 = 组菜单；`显示组框` 搬进组菜单并改名 `显示边框线`。
- `屏蔽缩放` / `屏蔽位移` 两个独立开关（当前都关）：前者让成员不再响应自身拉伸（光标也不再变），
  后者让"按住成员拖动"变成移动整组。**组自身的缩放/移动不受影响**；**图标拖动仍是重排**。
- 拍板：板面**完全不可见**只接鼠标；拖组 = 按住移动 ≥4px；成员热区保持现状（用户坚持）；
  本轮只做 G1；ini 结构不变；`显示边框线` 关掉后**组仍然存在**（只是不画线）。

**实现落点（`dock.cpp`）**

| 项 | 关键点 |
|---|---|
| 成员列表 | `GroupMember{ HWND, Companion* }` + `GroupMembers(out)`（条在前，`comp==nullptr` 就是条）；`GroupBoxMembers/Rect`、组缩放的"逐成员最小尺寸/逐成员落点"全部改成遍历它 —— G2 加组/加小窗不用再动几何代码 |
| 板面 | `GroupBoxPaintBoard()`：整块填 **alpha 1**（premultiplied white，0.4%），圆角外的像素清零；**alpha 1 实测能接真实按下**（`WindowFromPoint` 也认） |
| 命中 | `WM_NCHITTEST` → `HTCLIENT`；但**我们自己的 UI 在场时让位**：`g_popupOpen‖g_menuOpen‖g_setWnd‖g_gridVisible` → `HTTRANSPARENT` |
| 拖组 | `GroupDrag` 状态机：按下记 `grab = cursor - (g_cfg.x,g_cfg.y)`，移动 ≥4px 后 `g_cfg + g_dragMovePending` → **复用条的拖动通道**，条/小窗/框在 `Present()` 的同一次合成里落下（§3.7 的纪律，零重复几何） |
| 两个开关 | `GroupBlockResize()` 让条与小窗的 `EdgeAt()` 短路（含 `WM_SETCURSOR`）；`GroupBlockMove()` 在成员的 press→drag 转移处改调 `GroupDragBegin()`。两者立即生效并写回 ini |
| 组菜单 | `GroupShowMenu()`：`✓显示边框线` / `✓屏蔽缩放` / `✓屏蔽位移` / `Dock 设置…`；小窗菜单里的 `显示组框` 已删除 |
| `enabled` 新语义 | 只是"画不画那圈线"；窗口**永远创建**（板面/拖组/右键/环都在）。线开关走 `GroupBoxRepaint()`（几何没变、只换像素） |
| z 序 | **不再**在显示时 `SetWindowPos(HWND_TOPMOST)` 提框窗口（提了会压住先弹出的 shell 弹窗）；它创建时就是 topmost，后来的弹窗自然在它之上 |

**证据（`dev/`）**
- `t_groupdrag.ps1`（临时 `margin=40` 才有地方抓）：抓点 `543,206` → `DockGroupBoxWindow`；拖 +200,+120 →
  条 +200,+120、小窗 +200,+120、框 +200,+120 且尺寸不变、`frame == members + 40: True`。
- 命中边界：框内 3px 缝 `1357,60` → `DockGroupBoxWindow`；框外 6px / 25px → `Chrome`（穿透仍在）。
- `t_groupmenu.ps1`：菜单项执行后日志 `group: menu -> line=0/1`、`blockResize=1/0`、`blockMove=1/0`；
  **边框线像素实测**：线开时 y=5 处 `152,153,160`（sum 465），线关时同点 `118,119,129`（sum 366）= 只剩板面那 0.4%。
- `屏蔽缩放` A/B：同一位置按小窗左边缘拖 −40 → 开：移动（1614→1580，宽 308 不变）；关：拉伸（274→308，`resize start edge=1`）。
- `屏蔽位移`：拖小窗 +100,+50 → 条 +100,+50、小窗 +100,+50、相对偏移不变（762,8）；日志 `drag redirected to the group (blockMove)`。
- 拖组帧率/开销：拖组期间 `cadence:` 里 `companion moves` 与 `repaints` 同步上升，`captures` 被抑制
  （`busy` 里加了 `GroupDragging()`，玻璃档拖动不会每帧抓图）。
- `显示边框线=0` 时板面仍可点（`DockGroupBoxWindow`）—— 符合"组还在只是不画线"。

**坑 / 几何现实**
- **紧凑布局里没有"空白"可抓**：你这套布局条占 563–1356、小窗 1359–1621，中间只隔 3px，剩下的就是 8px margin，
  而 margin 又是缩放抓取环（9px）——所以默认 margin=8 时"板面"几乎不存在。想用板面拖整组，要么把
  `[group] margin` 调大（40 就有 30px 的环内空白），要么开 `屏蔽位移` 之后直接拖条/小窗（这才是紧凑布局的正解）。
- **小窗圆角外是透明像素**：按在小窗的圆角"缺口"上会抓到板面（= 拖整组），不是抓小窗。这是 layered 命中的必然。
- 测试探针必须"先把光标停在条上"再移到板面：组隐藏时那个点是别人的窗口。

**未由人手复核**：拖组手感；光标在板面上是箭头（故意不换 size-all，避免"光标乱跳"）；
菜单文案；`屏蔽缩放`/`屏蔽位移` 组合使用（两个都开时：拖成员=拖组、拖边=不拉伸，机器验过单开）。

**修掉的 bug（2026-11-16 14:48 用户报告）：拖组时条的玻璃背景抖**
- 现象：**拖组空隙**（板面）或**开屏蔽位移后拖小窗**时，条的玻璃背景出现"位移/抖动"；**直接拖条**就没有。
- 根因：`CaptureBackdrop()` 里"拖动时的抓图边距"只认条自己的 `g_dragging`/`g_resizeEdge`：

  ```cpp
  const int M = (g_dragging || g_resizeEdge) ? g_bakeMargin : (blurRadius>0 ? 64 : 0);
  ```

  组拖动时这两者都是 false → 用户当前 profile（`glassOpacity=1 / blurRadius=0`）算出的边距是 **0 px**，
  而拖动期间又禁止抓图 → 条一动就出快照范围、只能拿旧快照画 → 玻璃滑动/抖动。
  直接拖条时 `g_dragging=true` → 边距 256 px → 覆盖住位移 → 不抖。
  **不是"更新优先级"问题**，是快照边距没覆盖到"组拖动"这条路径。
- 修法：`const bool moving = g_dragging || g_resizeEdge || GroupDragging();`
- 证据（新增永久计数器：`cadence:` 后面那条 `… frames were painted out of a stale backdrop snapshot`）：
  同样一次 ~420 px 的拖动——
  **修前：20 帧用了过期快照（边距 0）；修后：1 帧（边距 256）**；
  对照组"直接拖条 ~510 px"也是 **2 帧** —— 组拖动现在与条自身拖动同档。
  （一次超过 256 px 的单向拖动，尾部仍会掉几帧：这是"拖动期间不抓图"的既有取舍，与修前无关。）

---

### 3.12 G2 多组（2026-11-16 15:1x）

**语义（用户 5 个拍板，详见 `PLAN_GROUP.md` §9）**
- **组 = 实体**：`g_groups[kMaxGroups=4]`，每组自己的设置/框窗口/淡入淡出/手势状态。**组 1 = 默认组**（含条）。
- **建组**：小窗右键 → `组 ▸ 默认组 / 组 2 / 组 3 / 组 4 / 移到一个新组…`；**不建空组**。
- 组 1 的显示规则不变（鼠标上条 → 整组淡入）；**无条组**的成员按距离淡出（不然碰不到它），
  **框**在鼠标进任一成员/框内时淡入。
- 单成员组**合法**但**不画框**（<2 成员），它的组设置**叠加进成员的右键菜单**（用户原话）。
- `解散本组` 只出现在 id>1 的组里；成员回组 1。

**实现落点**
| 项 | 关键点 |
|---|---|
| 模型 | `struct Group{id, 设置, hwnd/rc/alpha/dib, shown, scale, drag}` + `g_groups[4]` + `g_groupCount`；`GroupById/GroupOfWindow(GWLP_USERDATA)/DefaultGroup` |
| 成员 | `GroupMembers(Group&, out)`：id==1 加条，再加所有 `groupId == g.id` 的附属窗口；`< 2` → 无框（`GroupBoxRect` 返回 false） |
| 窗口 | **启动时把 4 个组的框窗口全建好**（隐藏）：id 稳定，菜单里新建的组和启动时存在的一模一样 |
| 状态从 `static` 搬到 `Group` | `shown`、`BoxScale`、`GroupDrag` 都变成每组成员；`box0/strip0/comp0` → `members0[]` |
| 跟随 | `CompanionFollowTo()` 只带 `groupId == 1` 的小窗 + **组 1 的框**（其他组各自独立） |
| 拖动 | 组 1 仍走"驱动条 → `g_cfg + g_dragMovePending`"（同帧合成）；组 N>1 没有条，按按下时的成员矩形**绝对**定位再重算框 |
| 缩放 | `GroupScaleTo(Group&)` 遍历 `g` 的成员（每组各自的最小尺寸/落点） |
| 开关 | `GroupBlocksResize/Move(Companion*)`：小窗看自己那组，条看组 1 |
| ini | `[group]` = 组 1（**兼容旧配置**），`[group.N]` = 组 N；`[traybar] group=N`（没这个键就按旧 `follow` 推：`0→0`，否则 `1`）；写入时 `group` 和 `follow` 都写 |
| 语义 | `groupId == 0` = 不属于任何组（= 旧的 `follow=0` 独立模式） |

**证据（`dev/`，本机实测）**
- 启动：`groups: 1 in use (max 4)`、`group 1: frame 555,5 1074x109 (margin 8, line=1, blockResize=0, blockMove=0)`；
  `t_groupbox.ps1` → `geometry matches the members + margin 8: True`。
- 菜单：小窗右键有 `组 ▸`（截图 `compmenu_g2.png` / 子菜单 `compmenu_g2_sub.png`：`✓默认组（跟随条）/ 组 2 / 组 3 / 组 4 / 移到一个新组…`）。
- 移到组 2：日志 `tray bar: saved 1322,3 262x79 (follow=0 group=2)`、`tray bar: group 1 -> 2`；
  之后**拖条 → 小窗不动**（`companion 1322,3` 不变）＝ 真正独立。
- 单成员组的菜单（截图 `compmenu_g2_single.png`）：`组 ▸ / 重置尺寸 / ─ / ✓显示边框线 / 屏蔽缩放 / 屏蔽位移 / 解散本组 / ─ / Dock 设置…`，
  且勾选状态是**该组自己的**（组 1 的 `blockResize/blockMove=1` 时，组 2 这两项仍是未勾）。
- `解散本组`：`tray bar: saved … (follow=1 group=1)` + `group 2: dissolved`，框与几何立刻恢复
  （`frame 555,5-1629,114`, `geometry matches: True`），ini 回到 `follow=1 group=1`。
- 回归：`t_followfps.ps1` 拖条时条与小窗**同步 108.3 次/秒**（`ratio 1.00`、偏移漂移 0.00px）。

**坑**
- **`DockGroupBoxWindow` 现在有 4 个**，而且平时都是隐藏的：探针/脚本里 `FindWindow` 式的查找会抓到
  隐藏的那个（表现：`rect=0,0-10,10`、`visible=False`，看着像"框没出来"）。`dev/` 里的探针已改成
  **优先返回可见的那个**，并在每次读之前重新找。
- `Group` 的成员访问（`g.scale.active` 等）需要完整类型：`CursorInCompanionGroup()` 这种早于组定义的函数
  只能用**提前声明的自由函数**（`PointerInDefaultGroup(POINT)`）。
- 组 1 的 ini 节名保持 `[group]`（没有迁移），新组才是 `[group.N]`。

**未由人手复核**：菜单里 `组 ▸` 的层级是否顺手；多个组同时存在时的观感（现在只有一个附属窗口，
所以"组 2"永远只有 1 个成员 → 永远没框，必须再加一个附属窗口才能看到真正的多组画面）。

**修掉的 bug（2026-11-16 15:36 用户报告）：组拖动只动了条**

- 现象：`屏蔽位移` 开启后，拖**组内空白**或**拖小窗**，只有条在动，小窗不动、框也不跟；
  松手时框才跳一下（更新尺寸）。直接拖条则一切正常。
- 根因：G2 我给 `CompanionFollowTo()` 加了 `if (DefaultGroup().drag.active) return;`
  （本意是"组拖动自己管所有矩形"）。但**组 1 的拖动只驱动条**（`g_cfg` + `g_dragMovePending`），
  小窗和框正是靠这个函数带上的 → 被自己堵死了。组 N>1 的拖动才自己绝对定位、根本不走这条路。
- 修法：删掉那句（保留 `GroupScaling()` 的那句——缩放确实自己摆每个成员）。
- 证据（两条路径都验过，`blockMove=1`／`margin=40`）：
  拖小窗 +100,+60 → 条 `584,59→684,119`、小窗 `1368,56→1468,116`、框 `+100,+60` 且几何 `exact`，
  日志 `group 1: drag start / done`；拖板面 +100,+60 → 三个窗口同步位移、`frame == members + 40: True`。
- 附带发现：你这套布局里**条和小窗有 9px 重叠**（条右 1377 / 小窗左 1368），所以"条与小窗之间的缝"
  其实不存在，默认 `margin=8` 时确实没有板面可抓（要靠 `屏蔽位移` 或加大 margin）。

---

### 3.13 G3 每窗口设置面板（2026-11-16 15:4x）

**语义（用户 3 个拍板）**：顶部一排页签；按 §9 那张表切分（全局只留材质/性能，条放排版，托盘放覆盖项，
组放组设置）；"归属哪个组"**只在右键菜单里改**，面板不重复。

**实现落点（`dock.cpp` 的 `// ---- settings UI (G3)` 段，整段重写）**

| 项 | 关键点 |
|---|---|
| 数据 | `SPage{title, section, rows, count, kind, groupId}` + `g_pages`（**打开面板时重建**，所以菜单里新建的组立刻出现），`g_page` 当前页，`g_rowVal` 当前页的值 |
| 行表 | 四张：`kRowsDock`（7）/ `kRowsStrip`（9）/ `kRowsTray`（3，`-1` = 继承，值列显示"继承"）/ `kRowsGroup`（7）；`SRow` 多了 `onText/offText`，开关不再写死"玻璃/纯色" |
| 读写 | `PageVal/PageSet` 按页类型分派：Dock → `[dock]` + `LoadConfig()`（含 captureHz 夹紧写回、`ArmRepaintTimer`）；条 → `[dock]` + `ApplyStripStyle()`（重排 + 小窗重绘 + 组框重算）；托盘 → `[traybar]` + 就地改 `radiusOv/padOv/gapOv`；组 → `Group` 结构 + `GroupSaveFlag`/`[group.N]` |
| 页签 | `TabRect(i, count)` 等分；点击切页 → `PageLoad()` + `SettingsResizeForPage()` + `SettingsPaint()` |
| 高度 | **随页自适应**：`g_setH = kRowsTop + rows*kRowH + 56`；切页时释放 DIB 再 `SetWindowPos`（不然 3 行的页会留一大片空） |
| 入口 | `ShowSettings(hintKind, hintId)`：条菜单 → 条页、小窗菜单 → 托盘页、组菜单 → 该组页 |

**证据（`dev/t_settings_shot.ps1` 一键截图，可带 `-Tab N` / `-Close`）**
- 从**托盘右键 → Dock 设置…** 进 → 面板直接落在 **托盘**页（`g3_tray.png`：圆角/内边距/格子间距三项都显示"继承"），
  面板 `760x352` = 3 行。
- 点页签：`全局` → `760x584`（7 行，`g3_dock.png`：背景类型/外观/玻璃不透明度/色调浓度/模糊/刷新 144/截取 20）；
  `组 1` → 7 行（`g3_group1.png`：显示边框线=显示、线不透明度 64、线宽 1、边框外扩 8、圆角 12、两个开关）；
  `条` → `760x700`（9 行）。
- 写路径（意外但有效的验证）：一次误点把 **条页的"图标动画时长"拖到 460** 并写进 ini —— 日志里之前的
  `hover zoom: ... (duration 150 ms)` 证明原值是 150，已还原；顺带证明"改即落盘 + 立即生效"。

**坑**
- 面板高度原来是"12 行固定"，分页后必须按页重算，并且**换页要释放旧 DIB** 再 `SetWindowPos`。
- 探针点菜单项/滑杆**别凭截图目测坐标**：我按目测点错了一行（把 `hoverMs` 改成 460）。
  页签/行的坐标公式：页签 `y = top+64..108`、行 `i` 的滑杆中心 `y = top+142+i*58`、`x = left+370..(left+590)`。

**未由人手复核**：面板观感（页签宽度、字体、空行）；托盘页的"继承"是否够直观；
组页里改 `margin`/`radius` 的手感（这会立刻改框，可能想让它在松手时才生效）。

---

### 3.14 下一步（2026-11-16 18:3x 的计划，**下一轮从这里开始**）

> 本轮**没有改代码**，只写了计划。全部细节在 **`PLAN_COMPONENTS.md`**，这里只放"下一轮开场三句话"。

**H1（先做，两个 bug）**
1. **开始菜单输入失效**：点搜索框 / 按任意键 → 菜单消失（预期：能直接输入 / 点搜索框能聚焦）。
   首要怀疑 **Windhawk `dock-flyout-anchor` 的 XAML 改写**（`HorizontalAlignment` + `Margin` +
   `RenderTransform` 同时用，视觉位置和输入/焦点可能被拆开）。**第一步就是禁掉这个 mod 做 A/B**，
   计划里 §1.1 有四步排查顺序和每步的判据。
2. **托盘图标要双击的程序**在宫格里点不开（我们只发一次单击）。方案：配置名单
   `[tray] doubleClick=<exe,...>` + 可选自动重试，**先问用户选哪种**。

**H2（设置按组件重构）**
- 改名：`托盘 → 浮窗`、`条 → 图标条`、`全局 → 玻璃`；
- 页签由**对象拥有哪些组件**决定（不是按角色写死）：
  图标条 → `浮窗 + 图标条 + 玻璃`；玻璃浮窗 → `浮窗 + 玻璃`；非玻璃浮窗 → 只有 `浮窗`；
- **浮窗页**：每窗自己的背景类型（玻璃/纯色/**图片**占位）、颜色（先黑/白）、圆角、内边距、
  完全显示距离、完全透明距离（要新增 `fadeStart/fadeEnd` 覆盖，目前读的是全局）；
- **玻璃页**：全局唯一（外观/玻璃不透明度/色调浓度/模糊/刷新率/截取频率），**不给每窗独立设置**，

**H3（玻璃共享快照）**
- 多个玻璃窗口共用一份（建议全屏）快照，各自裁剪烘焙；顺带消灭"拖动超过 256px 边距就用旧快照"的老问题。
- 用户已表态：性能"保持目前量级即可"，多玻璃叠加导致的下降不管（那是用户对自己配置的选择）。

**开工前先问用户 `PLAN_COMPONENTS.md` §7 的 6 个问题**（双击方案 / 条的淡出距离归哪页 / 组设置归哪 /
图片入口 / 颜色范围 / "外观"这个开关到底全局还是每窗）。

---

### 3.15 H1（2026-11-16 19:0x–20:0x）：开始菜单搜索框 = **不是我们的 bug**；托盘双击 = **已做完并验证**

**H1.1 开始菜单输入（结论：**不是 dock、也不是我们的 mod —— 是 Windhawk 引擎注入 SearchHost；已修好**）**

最终链条（详见 `PLAN_COMPONENTS.md` §1.1 的表）：

1. 三种打开方式（外部 Ctrl+Esc / 外部 Win / dock 首格）症状一致；dock 被杀、换全新 Start 宿主、
   mod 读不到锚点之后**照样坏** ⇒ 与 dock 无关。
2. 真正发生的事：搜索窗口（`SearchHost.exe` 的 `Windows.UI.Core.CoreWindow`，标题"搜索"）
   被留在 **`32767,82`**（shell 的"藏起来"坐标）。按任意键/点搜索框 = 请求"切到搜索面板"，
   面板出不来，开始面板就被换掉了 ⇒ 用户看到"菜单消失"。`Win+S` 同样一片空白。
3. **禁用 `Dock Flyout Anchor` 后仍然坏**（面板位置确实回到原生的 `553..1365`）⇒ 不是 mod 的 XAML 改写。
4. 在 Windhawk 全局高级选项里**排除 `SearchHost.exe`** 后，现象变了（`Win` 有时要按很多次、
   搜索框没光标、按字母既不输入也不收起 = shell 状态机卡住），**但杀掉 `StartMenuExperienceHost` +
   `SearchHost` 之后彻底好了**：`Win` → 开始菜单；按字母 → **搜索面板正常出现、字母进去了**
   （截图 `dev/ab2_2_typed_q.png`）；`SearchHost` 窗口停在 `460,82`（不再是 32767）。

⇒ **环境前置条件：Windhawk 必须全局排除 `SearchHost.exe`**（已写进 §2 的表）。
⇒ 以后再遇到"开始菜单/搜索怪怪的"，第一件事是**杀 `StartMenuExperienceHost` + `SearchHost`**，
不要先怀疑 dock。
⇒ 我们的 mod **不需要**任何修改就能恢复；`@include` 里也不要加 `SearchHost.exe`。

**仍然要补的（防御性，当前代码路径进不去）**：`CoreWindowUI::SetWindowPos_Hook` 的 SearchHost 分支
两个 switch 缺 `case dock` → `xNew/yNew` 未初始化就被 `SetWindowPos` 用掉。哪天有人把
`SearchHost.exe` 加回 `@include`，它会把搜索窗口丢到随机坐标（正是 32767 那种现象）。
补法：`case dock:` 走 `DockAnchor` kind=1 的 `Place()`，并给两个 switch 加 `default:`。

**H1.2 托盘双击（代码还在，但默认已经不用了 —— 见下面"托盘改成原生浮窗"）**

- **2026-11-16 22:5x 起 `[tray] native=1`（默认）**：`^` 打开的是 **shell 自己的溢出托盘浮窗**
  （`TopLevelWindowForOverflowXamlIsland`），我们只把它搬到 `^` 下面。之后一切原生：双击、右键菜单、
  鼠标钩子。实测 `Windhawk`（发什么消息都不理它）在搬过去的浮窗里**点一下就能开**，`WorkBuddy Manager` 同理。
  - 打开方式：合成 Win（任务栏只认 Win）→ 点原生 `^`（`TrayNotifyWnd.left+13`，任务栏中线）→
    把任务栏藏回去（`WM_TIMER 2`，浮窗不受影响）→ `PanelPlacement()` 摆到 `^` 下方。
  - 关闭：shell 搬走后**不会**因点外面自动关，所以我们用 `NativeTrayPark()` 把它挪到 `(0,2000)`，
    下次点 `^` 时按"已打开"走关闭分支；点 `^` 也能直接关。
  - 拿不到浮窗时**回退到自绘宫格**；`[tray] native=0` 可整体回退。
  - 现场日志：`panel: place ... -> 958,157 (293x193)` + `tray: native flyout ... moved 1403,827 -> 958,157`。
- 旧的转发机制（`[tray] doubleClick=*` 的 `DOWN/UP/DBLCLK/UP`、`autoDoubleClick`）只在
  `native=0` 时才会用到。**注意**：真正"要双击"的 app 等的是 `WM_LBUTTONDBLCLK`（PostMessage 合成不出来），
  所以那套只在部分 app 上有效；原生浮窗这条路没有这个问题。
- 双击/兜底的旧记录见 `PLAN_COMPONENTS.md` §1.2。

**另外**：顺手量了玻璃的现状成本（对 H3 有用）：条 921x242 的烘焙图，
`paint=26.27ms (glass 25.63) / bake=25.33ms`，`160 repaints / 160 captures in 10s`。
⇒ **一个玻璃窗口 ≈ 半个核**；H3 必须"每次 tick 一个预算 + 轮转"，不能每窗各抓一份（详见
`PLAN_COMPONENTS.md` §3.3）。

---

### 3.16 托盘改成"原生浮窗"（2026-11-16 23:0x–00:0x，用户实测通过）

**目标（用户拍板）**：宫格不再自己画、自己转发点击；**点 `^` 就把 shell 自己的溢出托盘浮窗
（`TopLevelWindowForOverflowXamlIsland`）叫出来、摆到 `^` 下面**，之后一切交互都是原生的
（双击 / 右键菜单 / 有鼠标钩子的 app 全部正常）。开关：**`[tray] native=1`（默认）**，`=0` 回到自绘宫格。

| 环节 | 做法 |
|---|---|
| 打开 | `Win+B`（把键盘焦点交给托盘，**不弹开始菜单**）→ 等任务栏 rect 上屏 → `Space`（激活焦点所在的 `^`）→ 浮窗出现 |
| 摆放 | `SettleFlyout()`：从按下 Space 起每 15ms 找一次，**一出现就搬**，并在滑入动画期间**持续钉住**（shell 在动画结束时会自己再定位一次） |
| 任务栏 | 见下面的 cloak 协议；**不要**用 `SW_HIDE`（隐藏后 shell 再也显示不回来，Win/Win+X 全废），**不要**用 `SetWindowPos`（shell 立刻弹回），**不要**跨进程 `DwmSetWindowAttribute`（`E_ACCESSDENIED`） |
| 关闭 | 浮窗被点掉/被挪走后：**把键盘焦点还给打开前的窗口**（否则托盘抱着焦点，shell 过几秒会把任务栏重新展开），发 shell 隐藏定时器，再保持 cloak 500ms |
| 兜底 | 拿不到浮窗 → `PostMessage(WM_APP+21)` 回 UI 线程 → 用自绘宫格（日志 `falling back to the built-in grid`） |
| 线程 | 整个开/关序列跑在**工作线程**（`TrayJobProc`）。在窗口线程里 `Sleep` 会饿死 `WH_MOUSE_LL` → **全系统鼠标卡顿**（用户实测"点完几百毫秒内很卡"） |
| 关闭后立刻再点 | cloak 请求在按钮当次**强制写**（绕过节流），否则快速二次点击会落在"上次释放"和"本次请求"之间 → 看见完整的 Win+B 过程 |

**任务栏 cloak 协议（dock ↔ `taskbar-hidden-until-win`）**
- 共享块 `Local\DockTaskbarCtl_v1`：`{ magic='DTC1'(0x31435444), version=1, cloakUntilMs, pad }`，
  `cloakUntilMs` 是 `GetTickCount()` 截止时间（0 = 不 cloak）。dock 建块（空 DACL，抄 `AnchorEnsureExists()`）。
- mod 每 20ms 读一次：`cloakUntilMs` 未过期 → 对 `Shell_TrayWnd`/`Shell_SecondaryTrayWnd` 设
  `DWMWA_CLOAK=1`（mod 在 explorer 里，所以允许）；否则解 cloak。
- **释放不是立刻的**：只要任务栏窗口还压在显示器上就继续 cloak（否则隐藏动画那几百毫秒会被点亮）。
- **用户按 Win 时**：mod 只有在 `!DockWantsCloak()` 时才解 cloak（dock 自己那次程序化 Win+B 不能亮出来）；
  并且 `TaskbarOnScreen()` 把 **cloaked 当成"不在屏幕上"**，这样浮窗关掉后第一次按 Win 仍然是
  "允许一次展开"而不是"把已经展开的再藏起来"。
- mod 源码：`windhawk/local@taskbar-hidden-until-win.wh.cpp`，运行时用
  `C:\ProgramData\Windhawk\ModsSource\` 里那份（**改了要用户在 Windhawk UI 里 Compile**）。
  本轮给它加了 `-ldwmapi` 和 `#include <dwmapi.h>`。

**还剩下的极小概率现象（2026-11-17 00:1x 用户又复现了几次，机制基本锁定）**
现象：与本轮无关的任务栏活动里偶尔（不可复现）任务栏露一下，偶尔还**不自动收起，直到点别处**。
**新的复现线索（关键）**：在条上的 Win 按钮上**快速循环 左键 → 右键 → 左键** 几次就有机会触发；
**与鼠标靠近下边界无关**（所以不是"悬停"那条）。⇒ 指向 **mod 的展开许可 `g_allowOpen`**：
- 右键 Win 按钮 = `Win+X`，真的按了 Win ⇒ mod `g_allowOpen = true`（允许一次展开）；
- 紧接着左键 Win 按钮 = `Ctrl+Esc` 开开始菜单 ⇒ 开始菜单本身会向 shell 请求展开，**此时许可还亮着**
  ⇒ 任务栏被展开；而这一刻没有任何人负责把它收回去（我们只在 Win+X 那次排了 650ms 的隐藏），
  于是它就立在那儿，直到点别处。
- 旧代码只在 **500ms 的 Watchdog** 里撤销许可，这个窗口足够两个动作挤进去。

**已实现（需要用户在 Windhawk UI 里 Compile 一次才生效）**：把"任务栏已在屏幕上 ⇒ 撤销许可"
挪进 20ms 轮询里的 **100ms 门**（`Wh_Log`: `taskbar on screen -> expansion permission revoked (poll)`），
窗口从 500ms 缩到 100ms；并且 `!win`（Win 还按着时不撤，避免干扰 Win+X 的和弦）。
**注意**：那次撤销用的是 `TaskbarOnScreen()`，而它把 **cloaked 当成不在屏幕上**——所以我们的托管浮窗
（托盘浮窗）期间不会被误撤；浮窗关掉、cloak 释放后如果任务栏还立着，下一次轮询就撤掉。
- **兜底仍在**（dock 侧，不需要 mod）：`HideNativeTaskbar()` 之后 2.5s 内每 350ms 再要一次隐藏，
  日志 `win button: taskbar still on screen - asked again`；这条专门对付"shell 推迟了隐藏请求"。

**下次排查的话**：`dev/loggrep.ps1 -Pattern "taskbar still on screen|hid the native taskbar|via a remembered handle|native flyout|falling back"`，
看事件前后有没有 `via a remembered handle`（= 当时枚举不到任务栏 = 已经展开）以及有没有
`falling back to the built-in grid`。**不要在窗口线程里加 sleep**（见上表）。

---

### 3.17 "任务栏偶发露头"的真因（2026-11-17 00:3x，**mod 已改，等 Compile**）

**上一节那个"展开许可 `g_allowOpen`"的猜测只对了一小半。实测是一条完全不同的链**（
`dev/t_winbtn_repro.ps1`，干净测量，时钟全程没人动键鼠）：

| 步 | 动作 | 任务栏 |
|---|---|---|
| A | 干净状态：右键 Win 格 → 250ms 后左键 | 全程 `y=1078`，**不动** |
| B | 用一次托盘浮窗（`^` 开 + `^` 关） | `y=1078`，不动 |
| C | **只按一次右键 Win 格（= Win+X）** | **+213 ms 从 1078 抬到 1020，然后一直立着**（1.5s 后仍 1020，`cloaked=0` = 用户真的看得见） |

而同一时刻 dock 每 350ms 都在求它收起来（`win button: taskbar still on screen - asked again` ×7），
**shell 完全不理**。⇒ 真因：

1. **Win+X 这一下本身就是一次真 Win 按下**，shell 为了让菜单贴着开始按钮，会把任务栏**展开**
   （不只是"可能滑上来"，实测 213ms 就上来了）。这是 `TrayUI::Unhide` / `ShouldTaskbarBeExpanded`
   的**正常路径**，旧 mod 的"Win 按下 ⇒ 允许一次展开"正好为它开门。
2. 任务栏一站起来，**只要 Win+X 的弹窗还开着，shell 就不收回**（它自己的隐藏定时器被忽略），
   于是"露一下 / 不自动收起，直到点别处"。用户"快速左右键循环"= 其中每一下右键都在赌这次会不会展开。
3. 与"左键 Ctrl+Esc"无关（A 再证）。左键只在**许可被死锁**（见下）时才让开始菜单把任务栏顶上来。

**顺手发现的两个真 bug（与复现无关也得修）**

- `g_allowOpen` 是个 bool，**只在"看到任务栏在屏幕上"时才清**。于是任何"不展开任务栏的 Win 按下"
  （Win+X / Win+D，以及 dock 自己合成的 Win+X、Win+B）都会把许可**永久焊死**；之后任何请求
  （悬停、Ctrl+Esc、弹窗锚定）都能把栏顶上来。
- 托盘浮窗用完之后 shell 会把任务栏留在**展开（y=1020）但被 cloak 遮住**的状态（实测 00:20 持续了 6 分钟）。
  这时按 Win，旧 mod 直接**解 cloak** → 一条本来就立着的任务栏**当场现形**；这也是"露头"的一条来源。

**改法（两边都要，语义是"谁需要它站起来"）**

- 共享块 `Local\DockTaskbarCtl_v1` 加了扩展（`'DTC2'`，老 mod 只读前 16 字节所以兼容）：
  `allowUntilMs`（dock 需要一次"升起"，但用 cloak 遮住 = 托盘浮窗）/ `denyUntilMs`（dock 自己按 Win+X，
  **谁都不许站**）。dock 写、mod 每 20ms 读一次缓存（hook 里只读内存，不开映射）。
- mod：`MouseAllowedToShow()` = deny ⇒ false；allow ⇒ true；Win 按着 ⇒ true；否则 `AllowValid()`
  （**带截止时间**，按下 1200ms / 松手后若还没站起来只留 400ms / 站起来立刻撤）。
- mod：按 Win 时如果栏是"cloaked 且真的在屏幕上"，**先要它收起来、不立刻解 cloak**，
  等真下屏了 `CloakTick()` 再解（否则就是上面那条"当场现形"）。
- dock：`OpenPowerUserMenu()` 先写 `deny=1200ms` 再发 Win+X；托盘两条路径先写 `allow`（升起来后清零）。

**验证（写在这里，Compile 之后照着做）**

1. `dev/t_taskbarctl_dump.ps1`：右键 Win 格时能看到 `deny=+1200 → 0` 倒计时（已验，dock 侧 OK）。
2. `dev/t_winbtn_repro.ps1`：C 段现在必须是 **`minY=1078 maxY=1078 riseAt=-1`**
   （改前 `minY=1020 riseAt=213ms`）。这是这次修改的判据。
3. `dev/t_tray_stuck.ps1`：托盘浮窗流程照旧（浮窗能开、能摆到 `^` 下面），第 5 步按 Win 时
   先 `y=1078` 再让开始菜单把栏带上来（旧行为是"原地现形"）。
4. 可能被 deny 影响的地方：**Win+X 菜单本身还能不能弹**（我们是靠 anchor mod kind=4 自己摆它的）。
   如果菜单不出来了，把 dock 的 `TaskbarDenyExpansion(1200)` 换成 `TaskbarCloakForce()`
   （让栏照样展开、只是不可见），其余不用动。

**1.0.1 实测结果 + 由此挖出的第二个更大的 bug（2026-11-17 00:37）**

- **deny 有效**：`dev/t_winbtn_repro.ps1` 的 C 段从 `minY=1020 riseAt=213ms` 变成
  **`minY=1078 maxY=1078 riseAt=-1`** —— 右键 Win 格再也不抬任务栏了。✅
- 但随即暴露：**"cloak 着 + 已经展开"的任务栏是个死锁**。
  - 实测：`SetWindowPos(Shell_TrayWnd, y=1078)` 从 dock 进程发出去被**立刻revert**（doc 早就这么写，这次复验）；
    `WM_TIMER 2`（TrayUI 自己的隐藏定时器）在 cloak 状态下**完全无效**；
    ⇒ **shell 收不回一条 cloaked 的任务栏**（它的收起动画根本不跑）。
  - 而 1.0.0/1.0.1 的 `CloakTick()` 是"**等它下屏了再解 cloak**"⇒ 它永远不下屏 ⇒ **永远不解 cloak**。
    以前这个死锁是"按 Win 时解 cloak"意外打破的——代价就是那条**已经展开的栏当场现形**（正是用户报的现象）。
    1.0.1 把这次"解 cloak"改成"先求它隐藏" ⇒ 死锁再也打不破：
    按 Win **什么都不发生**；`^` 的托盘 Win+B 路径也跟着废（`focus=elsewhere` → Space 打不开浮窗 →
    退回自绘宫格）。实测 00:38 连续 6 轮全是 `focus=elsewhere` + `falling back to the built-in grid`。
  - ⇒ **1.0.2 的改法**：`CloakTick()` 在 dock 不再要求 cloak 时**立刻解 cloak 并求它隐藏**（再 1.5s 内每 100ms 重求一次，
    条件是 `!WinKeyDown() && !AllowValid()`，绝不跟"Win 想看栏"抢）。代价：关托盘浮窗时任务栏会
    **正常地收起一次**（和普通自动隐藏任务栏关掉浮窗时一样），换掉"看不见但已经站起来"的死状态。
  - 同时把 dock 托盘路径里那个 `TaskbarAllowExpansion(2500)` **撤掉**（改回只清 deny）：
    "提前把许可给它"很可能就是让 shell 先展开、进而跳过"把键盘焦点交给托盘"那一步的原因
    （实测 `focus=elsewhere`）。Win+B 自己那下 Win 按下已经够它升起来了（实测 200–450ms）。
    `allow` 字段留在协议里，暂时没人写。
- **教训**：任何"先遮住、等条件满足再放开"的补偿机制，都要问一句**"那个条件会不会永远不满足"**。

**1.0.2 实测（2026-11-17 01:0x–01:1x）**

- **主 bug 已修并验过**：`dev/t_winbtn_taskbar.ps1 -Mode cycle -Gap 180 -Cycles 10`（8 秒内 20 次左右交替）
  → 任务栏全程 `y=1078`，**一次都没抬**；`t_winbtn_repro.ps1` C 段 `minY=1078 riseAt=-1`。
- **deny 的时序坑（真正的坑）**：dock 在发和弦前 1 ms 写 deny，而 mod 当时每 20 ms 才读一次共享块
  ⇒ **请求迟到**，右键照旧把栏顶上去了（`01:0` 那轮 C 段 `riseAt=166ms`）。
  外部写 deny 后等 300 ms 再发 Win+X 是**能挡住**的（`t_deny_winx.ps1`），这就把原因钉死了。
  修法：dock 写完 deny 后 `Sleep(40)`；mod 1.0.3 里 `MouseAllowedToShow()` 改成**直读共享块**（不再吃缓存）。
- **托盘 `^`（native flyout）当前不可靠，但不是这次改坏的**（`dev/t_winb_space.ps1` / `t_allow_winb.ps1`）：
  - `Win+B` 现在**什么都不做**：既不把键盘焦点交给 `Shell_TrayWnd`，也不抬任务栏，
    而且**跟 mod 的许可无关**（我直接往共享块写 `allow=+20s` 也一样无效）；
  - 它**曾经好使**（00:37:48 `focus=tray`，01:0x 我手搓的探针也成过一次），所以是 shell 侧的状态问题
    （§3.15 的老经验：**先杀 `StartMenuExperienceHost` + `SearchHost`**，别先怀疑 dock）；
  - 现状：`^` 会走 `keyboard(MISSING) → mouse(MISSING) → 自绘宫格`，功能不丢但体验退步。
    → **下一轮第一件事：重启 shell 那三个宿主，再跑 `dev/t_tray_rounds.ps1 -Rounds 4`**。
- **顺手修好的两条**（都有实测支持）：
  - **关闭托盘浮窗**：浮窗开着时它**自己持有键盘焦点**，直接发 `Space` 就能关掉；
    原来先发 `Win+B` 反而把焦点挪走、`Space` 打空（`t_tray_close.ps1`：开着时 `Space` → `vis=False`，
    `Win+B`+`Space` → 无效）。现在 `NativeTrayPageKeyboard()` 开头就走这条分支。
  - **`HomePowerUserMenu` 之后接左键**：deny 生效后 Win+X 的菜单照样弹（anchor mod kind=4 摆位），
    没有再出现"菜单出来但任务栏站着"。
- **1.0.3（源码已就绪，Compile 可选）**：只把 deny/allow 的读取从"20 ms 缓存"改成"每次直读"，
  纯稳健性。不 Compile 也能用 —— dock 侧那 40 ms 余量已经够。

**⚠️ 写 mod 源文件必须"无 BOM"（2026-11-17 01:2x 踩的）**

用 `Set-Content -Encoding UTF8` 改这个 .wh.cpp 会写出 **UTF-8 BOM**，Windhawk 就报
**`Couldn't find a metadata block in the source code`**（它的解析器要求 `// ==WindhawkMod==` 在第 0 字节，
BOM 让它变成前 3 个字节）。正确写法：

```powershell
$t = [System.IO.File]::ReadAllText($p)          # 不带编码时默认 UTF8 且保留原样
[System.IO.File]::WriteAllText($p, $t, [System.Text.UTF8Encoding]::new($false))   # 关键：$false = 不写 BOM
```
或者直接用仓库里的 edit/write 工具改。检查：
`[System.IO.File]::ReadAllBytes($p)[0..2]` 必须是 `2F 2F 20`（`// `），不是 `EF BB BF`。

**1.0.2 之后：托盘打开/关闭的第二次返工（2026-11-17 01:1x–01:2x，用户报"托盘弹出任务栏收起、
托盘收起任务栏弹出"）**

用户现象：点 `^` 打开托盘 → **任务栏收起**（其实是我加的 cloak 把它遮住了，因为 shell 为托盘把栏顶上去了）；
再点 `^` 关托盘 → **任务栏弹出并且再也不收**（解 cloak 时那条本来就站着的栏现形，而 shell 在这个状态下
不认隐藏定时器），只能**按两次 Win 让开始菜单开关一次**，栏才跟着收起。

根因还是同一句话：**托盘这条路径根本不需要任务栏站起来**。实测（`dev/t_winb_space.ps1`）：
任务栏停在 `y=1078` 时，`Space` 一样能把 shell 的托盘浮窗打开。所以：

- `NativeTrayPageKeyboard()` 现在**一开始就 `TaskbarDenyExpansion(2000)`**（和 Win+X 同一招），
  整条 Win+B + Space 序列期间任务栏**一步都不许动**；`Space` 之后立刻清 deny。
- 于是"打开托盘"时任务栏没有站起来 → 不需要 cloak 去遮 → 关闭时也没有"已经站着的栏"要收
  ⇒ 用户报的那两个现象一起消失。实测（`dev/t_tray_openclose.ps1`，一轮开+关+点桌面）：
  **全程 `bar y=1078`，cloak 只在浮窗打开期间被要求（而且栏本来就在屏幕外，遮不遮都看不见）**。
- 顺带：`Space` 会**重试 3 次**（每次 200 ms 内等浮窗出现）。因为 `Win+B` 在这台机器上时灵时不灵
  （见下），一次不成就放弃太浪费。
- **`Win+B` 的可靠性**：专门量过（`dev/t_winb_scan.ps1`）——带/不带 scan code 各 5 轮，**0/5** 拿到焦点；
  直接往共享块写 `allow=+20s` 也没用（`dev/t_allow_winb.ps1`）⇒ **跟 mod / cloak / 许可都无关**。
  它 00:37 和 01:16 各成功过一次，怀疑与"用户当时正在动键鼠"有关（注入的 Win 和弦会被物理输入搅掉，
  `HANDOVER.md` §3.2 记过同样的事）。**下一轮复测请让用户别碰键鼠**，再跑
  `dev/t_tray_rounds.ps1 -Rounds 5`；如果那时仍然 0/5，就改用"直接 `ShowWindow(SW_SHOWNOACTIVATE)`
  那个浮窗窗口"（不必按 Win+B），代价是"点外面自动关"要自己实现。

---

### 3.19 ⛔ 稳定状态（2026-11-17 16:30，用户确认"完全符合预期"）—— 别碰

这一版是靠**三条互相配合的机制**撑起来的，任何一条单独看都像"多余/可以简化"，删掉就回退到某个已知故障。
下表左边是代码位置，右边是**删掉它会立刻出现的现象**（都实测过）。

| 位置 | 机制 | 删掉/改动的后果 |
|---|---|---|
| dock `OpenPowerUserMenu()` | 发 Win+X 之前 `TaskbarDenyExpansion(1200)` + **`Sleep(40)`** | shell 为了锚定 Win+X 菜单会把任务栏抬起来（+213ms），然后弹窗开着时拒绝收回 ⇒ **快速左右点 Win 格时任务栏露头并且不收**（原始 bug）。`Sleep(40)` 是给 mod 的 20ms 缓存留余量，删了 deny 会"迟到" |
| dock render tick（`g_denyClearAt` 那段） | 浮窗在屏上时每 400ms `TaskbarDenyExpansion(1500)`；**只在浮窗消失 700ms 后才 `TaskbarDenyClear`** | 原来每帧都在"没有浮窗在屏 ⇒ 清 deny"，把打开路径刚写的 deny 18ms 就擦掉 ⇒ **托盘升起时任务栏跟着升、关掉后任务栏出现且不收**（§3.18） |
| dock `NativeTrayPageKeyboard()` | ①开场就 `TaskbarDenyExpansion(2000)`（成功后**不清**，交给 render tick 续期）②不等"任务栏升起来"（那圈 500ms 轮询纯白等）③关闭走 `Space`，300ms 没关掉就 **`NativeTrayPark()`**，**绝不落进打开分支** | ①托盘把栏顶起来 ②点 `^` 卡半秒 ③`Space` 失败后落进 Win+B 分支，把浮窗又 toggle 开 ⇒ **"收起了又自己弹出来"**（稳定复现过） |
| dock `TrayJobProc()` | 原生浮窗没出现时**不再弹自绘宫格** | 宫格要再等 1s 才出来，而且和 shell 抢下一次点击；用户 2026-11-17 明确要求去掉，**自己按 Win 手动兜底** |
| mod `g_allowOpen` | 就是**普通 bool latch**（按下置真、看到栏在屏才撤），**不要再改成"带截止时间"** | 我 11-17 凌晨改过 deadline（按下 1200ms / 松手后 900ms），shell 请求展开常常更晚 ⇒ **按 Win 只出开始菜单不出任务栏**（用户最不能接受的一条）。Win+X 那种"按了 Win 但不该抬栏"由 dock 的 deny 负责，**不是**靠许可过期 |
| mod `MouseAllowedToShow()` | 判定顺序 **deny → allow → WinKeyDown → latch**，且只读 `g_dockCtl` 缓存（**不要在 hook 里 `ReadDockCtl()`**） | 顺序变了：物理 Win 键会盖过 deny，Win+X 又把栏顶起来；在 hook 里开文件映射会让 shell 的动画路径变慢（hook 可能每帧都被调用） |
| mod `CloakTick()` + `g_hideAskUntil` | dock 不再要求 cloak 时**立刻解 cloak 并求隐藏**（再 1.5s 内每 100ms 重求，条件是 `!WinKeyDown() && !AllowValid()`），`Wh_ModAfterInit` 里也会先收栏 | 旧版是"等它下屏才解 cloak"，而 **cloaked 的任务栏 shell 永远收不回去**（收起动画不跑、`SetWindowPos` 被 revert、`WM_TIMER 2` 无效）⇒ 死锁：按 Win 什么都不发生 |

**验收判据（改完必须全过，5 条）**
1. 快速左右交替点 Win 格 10 轮（20 次）→ 任务栏 rect **全程 `y=1078`**（`dev/t_winbtn_taskbar.ps1 -Mode cycle -Gap 180 -Cycles 10`）。
2. 单次右键 Win 格 → 同样不抬栏（`dev/t_winbtn_repro.ps1` C 段 `minY=1078 riseAt=-1`）。
3. 按 Win → 开始菜单 + 任务栏一起出；再按 → 一起收。
4. 点 `^` 开托盘 → **任务栏不跟着升**；再点 `^` 收 → **不出现任何东西**（`dev/t_tray_watch.ps1`，任务栏 y 全程 1078）。
5. 托盘开着时点 Win 格 → 只出开始菜单，**任务栏不出现**。
   （第 3/5 条的注入会被 UIPI 过滤，**只能用 dock 自己的注入或让用户手工验**，见 §3.18 末尾。）

**已知未做（不要顺手"修"掉稳定逻辑去凑）**
- Win+X 菜单摆到位后**几秒会被 shell 挪回原生位置**（anchor mod 的 armed 窗口过期）。
- 托盘 `^` 偶发不弹出（`Win+B` 把键盘焦点交给托盘这一步在 shell 侧不稳定）；现在**不再兜底**，等下一次点击或手动按 Win。

**卡顿怎么查出来的（2026-11-17 16:5x，第二轮）**

第一轮我只是把 WLAN 查询搬到工作线程，用户反馈"还在、且没变短"。于是**不再猜，先量**：在
`TrayStateRefresh` / `CompanionVisibilityTick` / `CompanionTick` 的 state+visibility /
companion 的 hover 重绘 / `CompanionPresent` 五处加了"只在慢的时候才打一行"的计时日志（`slow: ...`），
再用探针把光标"停在条上 → 离开 4 秒让它淡出 → 分 10 步滑进小窗"复现。结果一目了然：

`
slow: companion fade present 6.0 ms      ← 每一帧淡入都在 DwmFlush（144Hz 一帧 7ms）
slow: companion fade present 4.5 ms
slow: companion fade present 5.8 ms      ... 一次淡入 8–10 行
slow: tray state refresh 11.8 ms (volume 11.8)   ← 音量 COM getter 偶尔 12ms，也在这条路径上
`

**真凶是 CompanionPresent() 里的 DwmFlush()**：原来条件是
`presentSync==2 && (dragging || resizing || alpha != alphaTarget)`，而「透明度在变」并不改变几何，
根本不需要等合成 —— 但它每帧都等，于是 120ms 的淡入把 UI 线程（连同 `WH_MOUSE_LL`）**连续卡 8–10 次**。
现在只对 `dragging || resizing` 做 flush。同时把**音量/电量也搬到同一个工作线程**（自带 MTA 公寓和自己的
`IAudioEndpointVolume`，因为接口指针不能跨公寓用），UI 线程只剩"加锁拷一份快照"。

**还剩的那点**：每次小窗出现仍有一次 `companion visibility tick` 3.8–7.1 ms（ShowWindow + 两次
z-order 断言 + 重画 DIB + 锚点发布；隐藏时不再每 3 秒重画了，因为 wifi 信号每采样都会抖 1-2%，
那会让隐藏状态下每 3 秒白重画一次，5–15ms）。一帧的量级，属于可接受范围。

**给以后的人**：slow: ... 这些日志阈值是 3/4ms，平时不出现；**一旦出现就是"指针会卡"的直接证据**，
照它点名的那一行去查，不要再凭猜。探针：`dev/t_tray_watch.ps1`（开/关浮窗并采样）+
把光标"停条上 → 离开 4s → 分步滑进小窗"的脚本（见本节上面的命令）。
**顺带修掉的卡顿（2026-11-17 16:4x，用户报"鼠标从外面滑进三图标小窗时边界卡顿"）**
- 根因：`CompanionVisibilityTick()` 在"隐藏→可见"那一刻会 `c.stateAt = 0; c.netAt = 0` 强制刷新，而
  `QueryNetwork()` 是 `WlanOpenHandle/EnumInterfaces/QueryInterface`（RPC 进 WLAN 服务，几十毫秒）**跑在 UI 线程**上
  ⇒ 饿死 `WH_MOUSE_LL` ⇒ 指针在边界处卡住。滑出再滑入不卡，是因为那时不再强制刷新。
- 修法：**网络状态搬到工作线程**（`NetQueryProc`，3s 周期 + `NetQueryNudge()` 立即唤醒，UI 线程只读
  `g_netSnapshot` 快照，加锁只保护一次结构体拷贝）；"隐藏→可见"只保留廉价的音量/电量刷新 + 唤醒工作线程。
- 音量/电量仍在 UI 线程（一个 COM getter + 一个 struct），COM 对象在启动时就已创建，不会在进场时付激活成本。
### 3.20 H2a 已落地（2026-11-17 17:3x）：设置按组件分（结构/改名/ini 迁移）

**用户 2026-11-17 17:2x 拍板（这次问了 6 个，全部按推荐选项）：**
1. 组的淡出距离 → 量到 **组成员外接矩形 + margin**（= 画组框那圈）；
2. 我们自己的弹窗（宫格/设置/菜单/缩略图）→ **算"在组里"，整组保持全亮**；
3. background=solid → **给一个不透明度滑杆，默认 92%**（不搞完全不透明）；
4. 数据模型 → **H2 就落地"背景 + 玻璃层"两层**（不是三选一）；
5. "拖动时是否更新背景" → 放**玻璃页**，关掉 = **沿用冻结的旧底图**（用户选了这个；
   代价是拖动时背景会"粘在窗口上"，已告知并记录在案）；
6. 节奏 → **H2a（结构/改名/迁移，行为不变）→ 用户验 → H2b（浮窗样式生效 + 组距离）**。

**H2a 做了什么（dock.cpp 的 settings UI 段，整段重排）**
- 页签由**组件集合**算出，不再按 kind 写死：enum Component { kCompFloat=1, kCompBar=2, kCompGlass=4 } +
  SettingsBuildPages(hintObj, hintId, &hint)。对象 → 页签：
  | 对象 | 页签 |
  |---|---|
  | 图标条（条） | 浮窗 图标条 玻璃〔bgMode=透过背后 且 玻璃层开〕 组 1 |
  | 玻璃浮窗 | 浮窗 玻璃 组 N |
  | 非玻璃浮窗 | 浮窗 组 N |
  | 组（从组菜单进） | 只有 组 N |
- 页内行表按组件拆开：kRowsGlass（全局玻璃）、kRowsFloatDock（条的浮窗）、
  kRowsFloatTray（浮窗的浮窗，-1=继承）、kRowsBar（图标条专有）、kRowsGroup（组）。
- SPageKind 换成 kPageGlass / kPageFloatDock / kPageBar / kPageFloatTray / kPageGroupKind；
  菜单入口改成"哪个对象"：ShowSettings(kObjStrip|kObjCompanion|kObjGroup, groupId)。
- SRow 新增 choices/choiceCount：**N 选一分段按钮**（背景类型三项、纯色颜色两项），
  渲染在 SettingsPaint()，命中在 RowFromX()；原先的 0/1 toggle 与滑杆不变。

**ini（向后兼容，老配置一个值都不用改）**
- 新增 [dock] bgMode=0|1|2（透过背后 / 图片 / 纯色）、glassLayer=0|1、color=0|1、
  solidOpacity=0..255（默认 235）、dragNoCapture=0|1（H3 用）。
- material 变成**派生值**：material = (bgMode==0 && glassLayer)，只因为旧绘制路径还认它。
  迁移：缺 bgMode 时按 material 推（1→bgMode=0,glassLayer=1；0→bgMode=2,glassLayer=0），
  所以**现有 profile 的观感完全不变**（本机 material=1 → 透过背后 + 玻璃层开）。
- [traybar] 的同名键 -1 = 继承 [dock]（CompanionBgMode()/CompanionUsesGlass()）。
- 打开面板时日志打一行 settings: obj=N group=N -> K page(s): 浮窗 | 图标条 | ...，**页签集合最好的验证入口**。

**H2a 里"只存不生效"的（H2b/H3 接）**：color、solidOpacity、bgMode=图片（image= 键还没建）、
以及浮窗自己的玻璃底（§2.4.3：浮窗的玻璃是 H3 的活，现在选玻璃 = 保持现有 4% 白 + 字形）。
**bgMode/glassLayer 不是占位**：它们真的切换"玻璃路径 vs 纯色/无玻璃路径"（等价于旧 material）。

**H2b 待做（用户验完 H2a 再动）**
1. adeStart/fadeEnd 两行从 图标条 页搬到 组 N 页，值迁到 [group]/[group.N]，
   计量改成 GroupAlphaTarget()：距离 = 到 组成员外接矩形 + margin，组内成员（含条）共用一个 alpha；
   我们自己的弹窗算"在组里"（保持全亮）。**这条会顺带改掉条的淡出手感**（距离基准从"条自身"变成"组框"）。
2. 浮窗的 color/solidOpacity 真绘制；bgMode=图片 的界面入口（文件选择框仍留 H3）。
3. dragNoCapture（拖动时是否更新背景）接进 H3 的抓图路径。
### 3.21 组框"移出再移回之后不显示"（2026-11-20 20:5x）

**用户报告**：把三图标小窗 移到一个新组 再移回 默认组 之后，**组框线不显示**（显示边框线 是开的）。

**我的复现**：干净重启后按 组 ▸ 组 2 → 组 ▸ 默认组 走一遍，**框线正常回来了**
（日志 group 1: place 438,-34 1080x157 repaint=0 ... vis=1）。所以不是"移动本身把状态搞坏"。

**最可能的原因（已修）**：移动那一步是在**菜单里点的**，之后用户把鼠标放到**设置面板**上继续调——
而 CompanionVisibilityTick() 判"在不在组里"只看"指针在成员上 / 在框内"，**我们自己的弹窗不算**
⇒ 整组被判"离开" ⇒ 框淡出。等用户再看条时，框的 alpha 已经 0，看起来就是"框线没了"。
（PLAN_COMPONENTS §7-A4 本来就要做这条，用户 2026-11-17 已拍板"弹窗算在组里"。）

**改动（三处，都很小）**
1. CompanionVisibilityTick()：**指针落在我们自己的弹窗上**（设置面板 / 缩略图 / 转发的应用菜单，
   另外 g_menuOpen 一开就算）时，视为 shown —— 用 PtInRect 精确判，避免"弹窗一存在整组就常亮"。
   （第一版我写成"弹窗存在就算"，结果框线**一直不消失**，当场就改回精确判定。）
2. DistanceToWindow()：同样把这三个弹窗按"距离 0"算（否则指针在面板上时条会淡掉）。
3. 组框**重新出现**时补一次 GroupPresent()：SW_HIDE 之后的窗口会保留**上次 present 的 alpha**，
   补一次可以消掉任何"窗口 visible 但 alpha 停在 0"的脏状态。

**顺带留下的诊断日志**（都是事件触发，不是每帧；出现即证据）
- group N: place x,y WxH repaint=R painted=WxH alpha=A target=T en=E vis=V
- group N: no frame (members<2) -> hidden (alpha=A target=T)
- group N: target -> T (shown=S box=B alpha=A)

**还没做**：H2b（adeStart/fadeEnd 搬到组页 + 组矩形距离 + 浮窗 color/solidOpacity 真绘制）。
### 3.22 H2b 落地（2026-11-20 21:0x）：距离归组 + 浮窗纯色背景

**① 淡出距离搬到"组"（用户 2026-11-17 拍板：相对"组成员外接 + margin"测算）**
- Group 新增 adeStart/fadeEnd；[group] / [group.N] 里读写；缺省值**继承 [dock] 的同名键**
  ⇒ 老 profile 不用改 ini，手感不变。
- 新增 GroupBounds(g)：**单成员组也成立**的组矩形（成员外接 + margin）；GroupBoxRect() 仍然要求 ≥2 成员
  （框只画 2 成员以上），两者分工明确。
- CompanionAlphaTarget() 重写：组内所有成员**共用同一个 alpha**（组 latch shown → 255；
  否则用**该组自己的** fade 值，量到 GroupBounds）。groupId == 0（不属于任何组）保持旧行为（量到自己、全局值）。
- UpdateAlpha() 里条自己的 alpha 改成 GroupFadeAlphaForStrip()（默认组的 fade 值 + 组矩形），
  即"条也按组测算"。**副作用（已告知）**：条开始淡出的距离比"按条自身"大一圈（= margin 的余量）。
- 面板：完全显示距离 / 完全透明距离 两行从 图标条 页搬到 组 N 页（H2a 的组件矩阵不变）。

**② 浮窗纯色背景真的画出来了（只做了浮窗，条的纯色还没做）**
- TrayRepaint() 的底层填充：[traybar] bgMode=2（纯色）时用
  solidOpacity<<24 | (color ? white : black)；否则保持原来的 4% 白洗（= 透过背后 / 玻璃待 H3）。
- 不透明度下限夹到 3，否则整块 alpha 0 会让窗口不可点（layered 按 alpha 命中，老坑）。

**还没做（下一步/H3）**
- 条自己的 `bgMode=solid`（[dock]）：现在等于"无玻璃 = 透明"，没有实心块 → 2026-11-20 21:2x 已补上（`337a7e4`）。
- `bgMode=图片`（image= 键 + 文件选择框）仍只有界面占位（见 §3.23 末尾"H3 剩下"）。
- dragNoCapture（拖动时不更新背景，用户选了"沿用冻结旧底图"）要等 H3 的抓图路径。
### 3.23 H3a 落地（2026-11-20 21:2x–21:4x）：抓图管道共享 + 托盘浮窗真的有玻璃

> 上一节"还没做"里的第一条（条的实心块）已经在 `337a7e4` 里补完了；本节是 H3 的第一步。

**① 一份管道、每个窗口一份烘焙（PLAN_COMPONENTS.md §3 的骨架）**
- 新增 `struct GlassTarget`（`bmp/bits/w/h/origin/valid/marginUsed/at/lastMs/dirty`）：一个玻璃窗口
  "带边距、已经模糊+上色"的图。条 = `g_stripGlass`；浮窗 = `Companion::glass`。
- 原来 `CaptureBackdrop()` 里的 300 行搬进 `BakeGlass(t, winRect, margin, tag)`：
  抓（PrintWindow 或屏幕回读）→ 裁剪 → 降采样 → 模糊 → 升采样 → lift/tint/opacity，全部按 `tag` 打日志
  （`bake[strip]: ...` / `bake[companion]: ...`）。
- 返回三态 `BakeResult`：`kBakeOk` / `kBakeFailed`（保留旧图）/ `kBakeNoBudget`（这次跳过，下帧再来）。
  ⛔ **失败必须清掉 dirty**（老代码就是 `g_bakeDirty = false; return;`）：否则每帧重试一次 15 ms 抓图。
  因预算被跳过则**必须保留 dirty**，否则这张图要等下一个 captureHz 才补。
- 条自己的 `CaptureBackdrop()` 只剩"算边距 + 调 BakeGlass"（拖动 256 / 静止 64），行为不变。

**② 抓图时排除我们**所有**窗口（不只是正在被烤的那一个）**
- `IsOurWindow()` / `CollectOurWindows()`：条、浮窗、宫格、缩略图、设置面板、菜单、背景层。
- `GrabScreenExcluding(list, ...)` 一次给所有可见窗口打 `WDA_EXCLUDEFROMCAPTURE`，抓完立刻撤回。
  只排一个的话，两扇互相压着的玻璃会把**对方的玻璃**拍进自己的底图，而且是永久性错误（每次都拍错版本）。
- 没有我们窗口可见时直接抓（不打标记）；拿不到 exclusion 标记的老系统：条退回"藏一下再抓"（仍 500 ms 限流），
  浮窗直接放弃这次抓图（藏它会闪，看不见的抓图不如不抓）。

**③ 浮窗（托盘三合一）现在真的有玻璃**
- `[traybar] bgMode=透过背后 + glassLayer=开`（缺省 = 继承 `[dock]`）时，`TrayRepaint()` 在 4% 底洗之上用
  `CompanionPaintGlass()` 把烘焙图按圆角覆盖 + 边缘光贴上去（`EnsureFloatMask` 缓存掩码，形状不变）。
  底洗保留 ⇒ 第一张图还没到 / 抓不到时仍然可点。**关掉的办法**：`[traybar] glassLayer=0`（回到老观感，已实测）。
- 命中不变：满覆盖处 alpha=255，整个圆角块都是按钮，图标照旧叠在上面。

**④ 每帧预算 + 只抓看得见的（PLAN §3.3）**
- `[dock] captureBudgetMs`（默认 8，面板在"玻璃"页）：一帧里**第一张**抓图必做，第二张只有
  "这一帧还没花到 8 ms"才做 → 两扇窗自然轮流，帧率不掉，玻璃底图刷新率摊薄。
- `g_bakeBudgetUsedMs` 在 `RenderTick()` 开头清零；条的抓图在 `Paint()` 里，天然先拿预算
  （浮窗的 `CompanionGlassTick()` 放在 PaintAndPresent **之后**）。
- `alpha == 0` 的窗口一张都不抓：实测空闲 10 s = `0 repaints / 0 captures`。

**⑤ 移动只重裁，不重抓**
- 浮窗移动**不再**把玻璃标脏：图是"钉在屏幕上"的，`CompanionGlassTick()` 用新偏移重画（~0.5 ms）。
- 只有"走出烘焙范围"才重抓；移动中给 **128 px** 边距（`kCompanionMargin`，并粘住 3 s —— 两种尺寸来回切会让
  DIB 反复重建）。静止仍是 64 px。
- 效果：拖条时浮窗跟着走，抓图从"每帧一次 ~15 ms"降到"整个拖动几次"。

**实测（本机 1920x1080，captureHz=20，blurRadius=25，lightMode=1）**

| 场景 | 数字 |
|---|---|
| 两扇玻璃都可见（指针在组内） | 196 captures/10s（条 110 + 浮窗 88），`paint=15.2ms`，`bake=12.9ms` |
| 只有条是玻璃（`[traybar] glassLayer=0`） | 155 captures/10s，浮窗 0 次 |
| 空闲（都淡出） | 0 repaints / 0 captures |
| 浮窗一张（373x209 静止 / 501x337 移动） | 0–16 ms / 15–31 ms |

**验收（三条都过）**
- 两扇玻璃同时在场都跟手：截图取样 条身 `#A69D9D` vs 浮窗身 `#A69E9E`（同一套玻璃参数、同一时刻）。
- 拖动 231 步（~8 s）没有 `stale backdrop snapshot` 行（256 px 边距够用；更长/更快的拖动仍会到那一步 → H3c）。
- 空闲 CPU 同量级（0 抓图）。
- 回归：`t_winbtn_taskbar.ps1 -Mode cycle`（9 s）任务栏一直 `y=1078`；`t_groupbox.ps1 -Margin 13` 几何 `True`。

**顺手做的**
- 部署的 ini 里有一段**重复的 `[dock]`**（末尾 `x=437 y=64`，老残留），已删。`GetPrivateProfile*` 只认第一段，
  所以之前没出事，但留着会误导人。**面板写值的代码仍可能重复追加同名键，下一轮要修**（写前先删旧键）。
- 新探针 `dev/t_dock_reload.ps1`：用 EnumWindows 找 `DockStripWindow` 再 post `WM_TIMER 2` 触发重载。
  这台机器上 `FindWindowW("DockStripWindow")` 从普通权限进程返回 0，别用 FindWindow。
- 坑：`dev/t_dragperf.ps1` 会**改条的大小**（只恢复位置，不恢复 w/h）。用过它必须重启 dock，
  否则条变小、按距离算的 alpha 全不对（这一轮就被它坑了一次）。

**还没做（H3 剩下）**
- H3c：拖动时"一次性抓整个工作区 → 冻结 → 只给正在动的玻璃窗口用"（用户 2026-11-16 拍板的方案），
  以及 `dragNoCapture=1`（用户 ini 里现在是 1 = 不更新，沿用冻结旧图）。
- `bgMode=图片`（`image=` 键 + 选图框）仍然只有界面占位。
- §4.5 的 `WDA_EXCLUDEFROMCAPTURE` 策略复核：现在抓图期间排除的是**所有** dock 窗口（范围比之前更宽）。

### 3.24 H3c 落地（2026-11-20 22:1x–22:2x）：拖动时冻结一份整工作区快照

**方案就是用户 2026-11-16 19:4x 拍板的那个**（PLAN_COMPONENTS.md §3.2）：静止各抓各的小块；
一旦有玻璃窗口开始**动**，抓**一次**整块工作区并冻结，只给"正在动"的窗口用。

- `struct GlassFrozen`（`Local` 于 dock 进程）：`rect`（工作区）、`w/h`、`px`（**原始**桌面，未模糊未上色）。
- `GlassDragActive()` = 条的拖动/拉伸 ∪ 组拖动(`DefaultGroupBusy`) ∪ 组缩放 ∪ 浮窗自己的拖动/拉伸。
  `GlassDragTick()` 在 `RenderTick()` 开头跑，管**上升沿**（`FrozenBegin()` 抓一次）和**下降沿**
  （`FrozenEnd()` + 把两份 bake 标脏，让它们从真实屏幕重烤一次）。
- `FrozenBegin()`：`dragNoCapture=1` → **不抓**（日志：`drag started with dragNoCapture=1 - no picture taken`）；
  否则 `GrabScreenExcluding()` 抓整个工作区（**排除我们所有窗口**），实测 **16 ms**（第一次 32 ms，
  含一次 8 MB 缓冲分配）。
- `BakeGlass(..., allowFrozen)`：移动中的窗口先试 `FrozenCropInto()`（一次 memcpy）→ 直接省掉 BitBlt；
  `bake[tag] ... grab=3` 就是"这张来自冻结图"。**裁剪是"求交集"不是"要求全覆盖"**：
  bake 带 256 px 边距，靠近屏幕边缘时一定越界，越界部分本来就在屏幕外，保持中性灰即可。
- 两条"不更新"的路径都守住了：
  - `dragNoCapture=1`（用户的旧选择）：拖动中**一张都不抓**，旧 bake 冻结，玻璃跟着窗口滑（已知代价）；
  - `dragNoCapture=0`（用户 22:1x 现用）：拖动中只从冻结图重烤（`crop + blur + tint`），**不再有屏幕回读**。

**实测（本机，1920x1080，dragNoCapture=0）**
- 拖 500 px：冻结图 16 ms 一次，**7 张 bake** 从它读出来（`grab=3`）。
- 拖 900 px / 3 连拖：每次拖动 1 张冻结图（16/16/32 ms），`no longer covered` 一条都没有。
- `dragNoCapture=1`：`drag started with dragNoCapture=1 - no picture taken`，拖动中 0 次条抓图。
- 回归：`t_winbtn_taskbar.ps1 -Mode cycle` 任务栏全程 `y=1078`；`t_groupbox.ps1 -Margin 13` 几何 `True`；
  拖动中/拖动后条与浮窗都还是玻璃（截图确认）。

**没验证的（要用户的手）**："拖动时底图钉在桌面上、不跟着窗口滑"这个观感。我这台探针拖不动条
（`SetCursorPos`+`mouse_event` 能让 `g_dragging` 变真、能抓冻结图，但条的窗口不跟手 —— 真鼠标才行；
组拖动 `t_groupdrag.ps1` 能拖动），所以"手感"这一条只能你亲自拖一下确认。

**新探针**
- `dev/t_glassdrag.ps1 -Dx -Steps -StepMs -Shot`：拖条的**底部内边距带**（不是图标，也不是边缘）横向来回，
  净位移 0；`-Shot` 拍拖动中途的全屏。注意：合成输入下条不跟手（见上），组拖动请用 `t_groupdrag.ps1 -Inset 6`。
- 坑：**测量脚本必须 DPI-aware**。不调 `SetProcessDpiAwarenessContext(-4)` 时 `GetWindowRect` 返回的是
  虚拟化坐标（793x86 会读成 634x69），我这一轮差点以为把用户的布局改坏了。

### 3.25 快速拖动整个组"卡顿"的真因（2026-11-20 22:4x，用户报"纯色也卡"）

**不是玻璃**（用户判断对了）：`bgMode=2 / solidOpacity=255` 时根本没有抓图
（`cadence: 0 captures`、`bake=0.00ms`）。

**实测（本机 144 Hz，`t_glassdrag.ps1` 拖条，`allowResize=0` 让内边距带能抓起来）**

| | 拖动中每 10 s | per-frame |
|---|---|---|
| 改之前 | 263 repaints / 144 companion moves | `paint 1.58 + present 0.18 + **sync 4.41 ms**` |
| 改之后 | **0 repaints** / 219 companion moves | `sync 0.00 ms (n=0)` |

两个原因叠在一起：
1. **拖动是"每帧一次"的**：`WM_MOUSEMOVE` 只记目标（`g_dragMovePending`），真正移动在 render tick 里，
   而 tick 上限 = `refreshHz`（这里 60 Hz）。144 Hz 屏幕上 60 Hz ⇒ 每步显示 2~3 个刷新周期 ⇒ 抖动。
2. **每帧还阻塞 4.3–4.4 ms 在 `DwmFlush()`**（`presentSync=2`，144 Hz 屏实测）。它以前从来没被量过：
   `frame:` 里的 `present=` 只包住两个真正的上屏调用，flush 在它外面。**现在 `frame:` 行多了 `sync=`**。

**改法（只对"像素与窗口位置无关"的配置生效）**
- 新增 `GlassBackdropIsPositional()` = `g_cfg.material == 1`（= 透过背后 + 玻璃层开）。
- 否则（纯色 / 全透明）拖动时走 `MoveStripNow()`：在**鼠标消息里**直接
  `SetWindowPos` + `CompanionFollowTo()` + `GroupRecompute()`，**不重绘**。
  没有重绘就没有"几何/像素配对"的问题，于是也不需要 flush。
- 玻璃配置**原样不动**（还是 tick 里 move+paint、还是 flush）—— 那条是 §3.19 的稳定状态，别为了手感改它。

**回归**：`t_groupbox.ps1 -Margin 13` 几何 `True`；`t_winbtn_taskbar.ps1 -Mode cycle` `y=1078`；
拖动中没有 `slow:` 行。

**两个坑（都真的踩了）**
- **`File.WriteAllText(path, $null)` 会把文件清成 0 字节**（.NET 把 null 当空串）。我用 PowerShell 改
  `dock.cpp` 时变量恰好是 null，整个文件被清空 —— 靠 `git checkout -- dock.cpp` 救回来。**改源码只用
  read/edit 工具**，别用写文件脚本。
- 探针抓条的位置：`EdgeAt()` 的缩放带是轮廓内 **10 px**，而 `pad=10` ⇒ **纯色档下内边距带全是缩放带**，
  想"移动"只能按在两个图标之间 6 px 的缝里（或临时 `allowResize=0`）。这是另一个待办（见下）。

**新的待办**：纯色/玻璃档下条没有可抓的"空白移动区"（pad 10 ≤ 缩放带 10），用户只能拖图标缝。
建议把 `EdgeAt` 的 band 改成 `min(10, pad)` 或按"离轮廓的距离 ≥ pad-2"判定。

### 3.26 H3 收尾（2026-11-20 22:5x）：抓图排除策略收紧 + 图片背景落地

**① `WDA_EXCLUDEFROMCAPTURE` 策略复核（PLAN §3.1-4）**
- 以前抓图时给**所有** dock 窗口打排除标记。现在**只给与抓图矩形相交的窗口**打（每个窗口两次调用，
  实测 **0 ms**，已记进 `bake: screen grab ... (excluded N of M window(s), X ms)`）。
  实测：条的 bake 只排除条自己（`1 of 2`），因为条和浮窗并不重叠。
- 抓完恢复窗口**原来**的 affinity（`GetWindowDisplayAffinity` 先读再还原），不再一律写 `WDA_NONE`。
- 拿不到标记的老系统：只在条是抓图对象时退回"藏一下再抓"（判据从 `exclude[0]` 改成"列表里有没有条"，
  因为现在列表可能为空/被过滤）。
- 用户可感知的变化：别的程序截图/录屏时，dock 消失的范围从"整块"缩到"正在被烤的那一扇、几毫秒"。

**② 图片背景（`bgMode=图片`）真的能画了**
- 新 ini 键 `[dock] image=<path>`；`[traybar] image=` 留空则**继承** `[dock]` 的图（和其它样式键一致）。
- 解码走 WIC（`wincodec.lib` 已链接），格式 PNG/JPG/BMP 都行；**等比覆盖（cover）**：短边铺满、
  溢出居中裁掉，双线性采样。按 (路径, 宽, 高) 缓存 —— 每帧重新解一张 4K 图是不可能的。
- 解码失败（路径错、文件坏）也记住"失败"，否则每帧都会重试一次（`EnsureImage` 里那个 `!im.ok` 分支）。
- 玻璃层叠在图片上时**只上色调不模糊**（PLAN §3.4 A10 的那个问题按这个口径先落地）：照片本来就平滑，
  再烤一遍纯属浪费。`lift + tint` 的公式和玻璃底图完全一致，所以两种背景看起来是同一个材质。
- 条：`Paint()` 里 `bgMode==1` 走 `DrawImageBgStrip()`（复用 `g_covMask`/`g_rimMask` 圆角覆盖 + 边缘光）；
  浮窗：`TrayRepaint()` 里复用 `EnsureFloatMask` 的掩码。图还没到/失败时退回原来的底色，不会白屏。
- 实测：临时用一张 800×300 渐变+圆形的测试图，两个窗口都正确 cover 显示；验完已把 ini 恢复成用户的
  `bgMode=2 / solidOpacity=255` 并把 `image=` 删掉。

**还没做：选图框**。面板的 `SRow` 只有"滑条/开关/多选"三种行，没有"动作按钮"行，加一个要动
行布局 + 点击分发 + `GetOpenFileNameW`。所以现在只能手写 ini 的 `image=` 路径。**这是下一步唯一的缺口。**

### 3.27 矛盾设置的锁 + 图片背景的入口/图库（2026-11-21 01:5x）

**① 互相矛盾的设置现在会被锁死（用户 2026-11-21）**
- `SettingsRowDisabled(p, i)`：`背景=纯色` → **玻璃层**（强制显示"关"、灰掉、点了没反应）；`背景≠纯色` → **纯色颜色/纯色不透明度**灰掉；`背景≠图片` → **背景图片**行整行不显示。
- `SettingsRowVisible(p, i)`：隐藏行**不占高度** —— `RowAt()` 按可见行映射 y，`SettingsResizeForPage()` 按可见行算高度，
  `SettingsPaint()` 开头会重新对齐高度（图片行出现/消失时面板自己变高变矮，否则最后一行被切掉）。
- 实际效果（截图 + 取色验证）：`图片` 档 → 玻璃层=开可点、纯色两行变成 #48484A/#878787 灰；`纯色` 档 → 玻璃层两粒都灰、显示"关"。
- ⚠️ 玻璃**页签**是打开面板时按组件算的，所以在面板开着的时候切到纯色，玻璃页签会留到下次打开才消失（无害）。

**② 图片背景的入口 + 图库**
- 浮窗页多一行**背景图片**（只在 `背景=图片` 时出现）：显示当前文件名 + 两个方按钮
  **◷ 历史**（`IFileOpenDialog` 直接开在**图库文件夹**、只能从里面挑；图库为空时改成用 Explorer 打开那个文件夹，
  让人自己管理/放图）和 **＋ 新增**（从任意位置选图 → 复制进图库 → 立刻成为背景；对话框**不**默认指向图库，避免歧义）。
- 图库 = `dock.ini` 同目录下的 `backgrounds\`；代码里**从不列举/管理**它（改名、删除、换图都用资源管理器）。
- 切到"图片"档且本节没有 `image=` 时，自动套用**图库中最新的一张**（从没用过图库就保持空，显示"（未设置）"）。
- `image=` 的读写：`[dock] image=` / `[traybar] image=`（空=继承 `[dock]`），见 §3.26 的解码/cover 逻辑。

**③ 图片背景的排版还差一步（用户同一轮要求的视觉规格，尚未做）**
规格：短边对齐窗口短边、右侧清晰原图 + 整窗模糊放大图作底 + 主色渐变、原图左缘羽化；缩放时按"提前算好
（导入时算模糊底+羽化遮罩，之后只缩放）能否实时"来定策略。**下一轮先量这个计算成本，再决定实时还是松手后重算。**

## 4. 改代码前必须知道的 12 件事

1. **`presentSync=2`（`Present()` 里 ULW **之前** `DwmFlush()`）不是优化，是正确性修复。**
   合成器"下一帧才应用新矩形、但 layered 位图立刻生效"→ 每次移动后的 5–7 ms 是
   "新内容 + 旧几何"，表现为背景向后偏/抖动（幅度 = 速度 ÷ 重绘率）。
   改成 1（放在后面）或 0（去掉）都会复发。详见 `TODO_GLASS_LAG.md` §4.10。
2. **每帧的重活只在抓图和图标**：`CaptureBackdrop()` 一次 ~8–9 ms（屏幕回读有 ~7 ms 固定开销，
   面积再小也省不了）；`Paint()` 每帧只有 0.37 ms（混色已经烤进烘焙图，圆角/边缘光走缓存的
   `g_covMask`/`g_rimMask`）。**任何"每帧加一点计算"的改动都要先看这个预算。**
3. **抓图边距是动态的**（H3 后是 `GlassTarget::marginUsed`，条 = `g_stripGlass.marginUsed`）：
   静止 = 0（只抓条自己），拖动/拉伸 = 256（靠重新裁剪而不是重抓）。浮窗同理：静止 64 / 移动 128。
   `covered` 是**包含**判定（不是相等），否则拉伸时会每帧重抓 → 闪。
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
12. **G2 之后"组"是复数**：`g_groups[4]`（组 1 = 默认组，含条）。任何"某一个组"的代码都必须带
    `Group&` 参数；"这个附属窗口属于哪一组"看 `c.groupId`（0 = 不属于任何组）。三个易错点：
    ①**不要再用 `g_trayBar.follow` 判"在不在组里"**（它现在只是 `groupId == 1` 的镜像）；
    ②`DockGroupBoxWindow` 有 4 个、平时全隐藏 —— 探针必须挑**可见的**那个；
    ③组 1 的 ini 节是 `[group]`，新组是 `[group.N]`（没有迁移代码，靠这个区分）。

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
| **`t_settings_shot.ps1 [-Tab N] [-Close] -Out <png>`** | 【G3】截设置面板；`-Tab N` 先点第 N 个页签（同时打印面板尺寸，用来验证"高度随页自适应"）。页签坐标 `top+64..108`，行 `i` 的滑杆中心 `top+142+i*58` |
| **`t_compmenu.ps1 -X -Y -PickX -PickY`** | 【R4】右键开小窗菜单 + 点某一项，前后打印框的可见性（验证"菜单命令真的执行了"）。**别叫它 `t_menupick.ps1`——那个名字早就被 App 菜单探针占了** |
| **`t_groupdrag.ps1 [-Dx -Dy -Inset -Margin -Steps -StepMs]`** | 【G1】先在条上预热，再按框内板面拖 N 像素：打印条/小窗/框的位移与 `frame == members + margin`。**默认要看 `margin=40`**，否则紧凑布局里没有空白可抓 |
| **`t_groupmenu.ps1 [-Item 1..4] [-X -Y]`** | 【G1】右键框（默认按框线左端）→ 点第 N 项 → 打印帧矩形并回读日志里的 `group: menu ->` |
| **`t_click.ps1 -X -Y [-Double]`** | 【G2】DPI-aware 的单击（选菜单项用）。菜单项的坐标要先用截图量：本机主菜单从光标处向右下展开，第一项约 +12px、之后每项 +26px |
| **`t_zorder.ps1`** | 【G1】把几个类名在 z 序里的相对位置打出来（`ControlCenterWindow` 这类 shell XAML 窗口 EnumWindows 看不到，只能靠 `WindowFromPoint` 判） |
| **`tray_drag_shots.py`** | 【本轮】拖动时抓帧 + 记录 rect 的探针（模板相关性定位），用于"屏幕到底怎么动" |
| `acrylic_test.cpp` + `buildtoy2.ps1` | DWM 磨砂可行性验证（还没用上，见 `HANDOVER.md` §3.6 末尾） |
| **`t_winbtn.ps1 -Button left\|right`** | 【本轮】从 `layout:` 日志读首格矩形 → 真鼠标点一下 → 打印任务栏/弹窗状态 + 截图 |
| **`t_wingrid.ps1 [-KeepOpen]`** | 【本轮】按 `layout:` 的 `chevron=` 点开宫格并报告落点（旧的 `t_gridplace.ps1` 按老公式算位置，已不准） |
| **`loggrep.ps1 -Pattern <正则> -Last N`** | 【本轮】日志正经 grep。`logtail.ps1` 只给最后 25 行、而且**不认 `-Lines`**，别用它判断"有无某条日志" |
| **`t_winbtn_repro.ps1 [-SkipClean]`** | 【§3.17 主力判据】干净测量"任务栏到底站没站起来"：A 段干净右键+左键、B 段用一次托盘浮窗、C 段只按一次右键；每步打印 `y=1078/1020` + `cloaked` + 用户空闲时长（有人在用就自己标红）。判据：C 段必须 `minY=1078 riseAt=-1` |
| **`t_taskbar_state.ps1 [-Hide] [-Watch N]`** | 【§3.17】`Shell_TrayWnd` 的 rect / vis / cloaked（DPI-aware）。`-Hide` = 给它发 TrayUI 的隐藏定时器；`-Watch` 打印每次变化 |
| **`t_taskbarctl_dump.ps1 [-Watch N]`** | 【§3.17】读 `Local\DockTaskbarCtl_v1`：`magic/ver/cloak/allow/deny`，含"还有多少毫秒到期" |
| **`t_tray_stuck.ps1`** | 【§3.17】用一次托盘浮窗，再逐步看任务栏（开浮窗 → 关 → 求隐藏 → 按 Win ×2），验证"展开+cloaked 残留"还在不在 |
| **`t_winbtn_gapsweep.ps1`** | 【§3.17】扫"右键→左键"的间隔（120/200/300/450/700/1000ms），每轮报 `minY/maxY/riseAt` 和前台窗口类（判断 Start 有没有真的开） |
| `t_winbtn_permission.ps1 -Mode baseline\|after-winx\|after-left-latched` | 【§3.17】"悬停下边界"是不是能把栏顶起来（判定展开许可有没有被死锁）。**注意**：Win+X 弹窗开着时悬停不一定产生 unhide 请求，阴性结果不能当结论 |
| `t_winbtn_taskbar.ps1 -Mode right-only\|right-then-left\|left-only\|cycle` | 【§3.17】按方案注入点击、10ms 采样任务栏 rect 的最早版本（被 `t_winbtn_repro.ps1` 取代，留着看细节；**`-Mode cycle` 是最终验收用的那一条**） |
| **`t_win_hover_toggle.ps1`** | 【§3.17】不碰 dock：悬停下边界 5 秒（必须不动）+ 连按两次 Win（必须"藏/显"）+ Esc |
| **`t_deny_probe.ps1` / `t_deny_winx.ps1`** | 【§3.17】自己往共享块写 `deny`，验证"mod 到底读不读这个块"以及"deny 生效时 Win+X 抬不抬栏" |
| **`t_allow_winb.ps1` / `t_winb_probe.ps1` / `t_winb_space.ps1`** | 【§3.17】`Win+B` 到底给了谁焦点、要不要任务栏先升起来才能 `Space` 打开浮窗（结论：不用；但 `Win+B` 本身会失效，见 §3.17） |
| **`t_tray_close.ps1`** | 【§3.17】浮窗开着时用 `Space` / `Win+B`+`Space` 关它（结论：纯 `Space` 就行） |
| **`t_tray_rounds.ps1 -Rounds N`** | 【§3.17】连开连关 N 轮 `^`，统计 native flyout 成功/退回宫格的次数（下一轮复测就用它） |
| **`t_cloak_focus.ps1`** | 【§3.17】cloak 与 `Win+B` 焦点的关系探针（**注意**：dock 会把自己的 cloak 请求清掉，别用它读状态） |
| **`t_tray_openclose.ps1`** | 【§3.17】用户报的"托盘开→任务栏收起 / 托盘关→任务栏弹出"那一轮的完整走查：Win×2 归一 → `^` 开 → `^` 关 → 点桌面，每步打印 bar/cloak/浮窗 |
| **`t_winb_scan.ps1 [-NoScan]`** | 【§3.17】`Win+B` 给不给托盘焦点：带/不带 scan code 各 N 轮，输出成功率 |
| **`t_tray_watch.ps1 -Clicks -Gap`** | 【§3.17】一边点 `^` 一边 15ms 采样"任务栏 y/cloak + 所有 `TopLevelWindowForOverflowXamlIsland` 窗口（可见性/坐标）+ 前台"，用来抓"浮窗被谁关了/托盘自己又弹出来" |
| **`t_dock_reload.ps1 [-Delay ms]`** | 【§3.23】改完 ini 让运行中的 dock 重载（EnumWindows 找 `DockStripWindow` → post `WM_TIMER 2`）。这台机器上 `FindWindowW` 从普通权限进程返回 0，所以别用 FindWindow |
| **`hoverat.ps1 -X -Y -Out -Wait`** | 【§3.23】把光标放到指定点并**回读坐标确认**（`SetCursorPos` 会因 UIPI 静默失败），再截全屏。测玻璃/淡入都用它 |
| **`t_glassdrag.ps1 -Dx -Steps -Shot`** | 【§3.24】拖条的底部内边距带（不是图标/边缘）横向来回，净位移 0；`-Shot` 拍中途全屏。**合成输入下条不跟手**（真鼠标才行），组拖动用 `t_groupdrag.ps1 -Inset 6` |

---

### 3.18 2026-11-17 下午：回滚（**这一节比 §3.17 更权威**）

用户 15:40 的反馈：①按 Win **只出开始菜单不出任务栏**；②宫格按钮开托盘 → 再点收起 → **收起了又自己弹出来**（稳定）；
③托盘开着时点 Win 格 → **任务栏稳定出现**（延迟几百毫秒）；④点宫格到托盘出现**要等几百毫秒**。

**定性：①②④ 是我 17 日凌晨那几处"加码"引入的，已回滚；③是 deny 时序问题，已修。**

| 现象 | 真因 | 处置 |
|---|---|---|
| ① Win 只出开始菜单 | 我把"展开许可"改成了**带截止时间**（按下 1200ms / 松手后只留 900ms），而 shell 请求展开常常晚于这个尾巴 ⇒ 被自己挡掉 | **回滚成原来的 bool latch**（按下置真、看到栏在屏幕上才撤）。Win+X 那种"按下但不抬栏"改成**由 dock 写 deny 负责**，不再靠许可过期 |
| ② 托盘收起后又自己弹出来 | 关闭那段我先发 `Space`，**失败后没有 return，直接落进了"打开"分支**（Win+B + Space），把 shell 的浮窗又 toggle 开了（日志：`Space did not close it, trying Win+B` → 3.4s 后又 `flyout open`） | 改成：`Space` → 300ms 内没关掉就 **`NativeTrayPark()`**（和"点外面"同一个关闭动作，立刻生效），**绝不落进打开分支** |
| ③ 托盘开着点 Win 格 → 任务栏出现 | "任务栏不许展开"的 deny 只在**开托盘的一瞬间**写 2s，之后就撤了；shell 过几百毫秒才来请求展开 ⇒ 放行 ⇒ 栏站起来（再由 cloak 遮住，等解 cloak 时就"弹出来"） | deny 改成**跟随浮窗生命周期**：浮窗在屏幕上每 400ms 续 1500ms，浮窗消失后 `TaskbarDenyClear()`。顺带把"托盘开着时按 Win 也让栏站起来"一起挡掉 |
| ④ 点宫格要等几百毫秒 | 打开路径里有一圈"等任务栏升起来"的 500ms 轮询（这条路径下栏**永远不会升**，纯白等） | 删掉那圈；只等键盘焦点（≤300ms） |

**还有一个更要命的测量教训**：我这个会话里的探针是**低完整性进程**，`keybd_event` 合成 Win 键会被 UIPI 过滤
⇒ 我量到的"`Win+B` 0/5 拿到焦点"、"注入 Win 不抬任务栏"**都不可信**（dock 自己注入的是中等完整性，用户的物理按键更不用说）。
⇒ **以后凡是 Win 键相关的验收，只能靠 dock 自己的注入或用户的手**，别再用探针下结论。

**现状（15:5x）**：dock 已重编译重启；mod 源码 **1.0.4**（= 回滚许可 + 保留 deny/allow + 保留 cloak 释放修复 + 初始化收栏），
已同步到 ModsSource（**无 BOM**：前 3 字节必须是 `2F 2F 20`），**等用户 Compile**。

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

### 3.28 图片背景的三处修正（2026-11-21 20:5x）

- **玻璃页对"图片背景+玻璃层开"的窗口消失了**（用户报的 bug）：页签原来按 `CompanionUsesGlass()`（= 是否烤屏幕底图）判断，
  而图片背景不烤底图、却**确实吃玻璃层的色调**。新增 `CompanionHasGlassLayer()`（= 层开且背景不是纯色）用于页签；
  条那边也从 `bgMode == 0 && glassLayer` 改成 `glassLayer && bgMode != 2`。
- **玻璃页里没有意义的行现在会灰掉**：当**没有任何窗口**在烤屏幕底图时（全是图片/纯色），
  `玻璃不透明度 / 背景模糊半径 / 背景刷新帧率 / 背景截取频率 / 每帧截取预算 / 拖动时不更新背景` 全部灰掉不可点；
  `外观` 和 `色调浓度` 保留（它们对图片背景有效）。判据 `AnyScreenBackdrop()`。
- **竖向窗口的排版**：`h > w` 时整布局逆时针转 90° —— 清晰图贴**顶部**并水平居中、羽化在它的**下缘**向下渐隐、
  主色渐变最浓在**下缘**。实测把浮窗临时改成 81×245 截图确认（清晰带在顶、向下平滑过渡），之后恢复 233×79。

**⛔ 一条必须记住的坑**：部署的 `dock.ini` 是 **ANSI/GBK**，里面会有中文图片路径。
我这轮用 PowerShell `[System.IO.File]::ReadAllText($p)` + `WriteAllText(..., UTF8Encoding)` 改 ini，
把 GBK 字节当 UTF-8 解码再写回 → **中文路径被永久毁掉**，dock 日志出现
`image: cannot decode ...\锟斤拷幕锟斤拷图...`，图片背景整块失效（上一轮的锐度修复也因此没生效）。
修法：**改这个 ini 必须用 `[System.Text.Encoding]::GetEncoding(936)`** 读写；改完用 Win32 `GetPrivateProfileStringW` 回读确认。

### 3.29 任务 1 落地（2026-11-22 00:1x–0x）：z 序看门狗 + 截图时让位

**先量再改的两条实测结论（`dev/t_ztry.ps1`，别凭直觉推翻）**

1. **`WS_EX_TOPMOST` 是"带"，不是"排名"**。任何**后来**出现/被抬起的 topmost 窗口都合法地压在我们上面
   （实测：我们的条 z#20 → 新 topmost 窗口 z#17）。而本程序里 `Present()`/`CompanionSetRect()`/`GroupPlace()`
   全都特意带 `SWP_NOZORDER`，**没有任何一处会把它抢回来** → 这就是用户说的"某段时间起新召出的窗口总压住 dock，
   过一阵同样的应用又好了"：变量在**对方**，不在 dock。
2. **回来的路只有一条**：对**已经 topmost** 的窗口再调一次
   `SetWindowPos(h, HWND_TOPMOST, 0,0,0,0, SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE)` → 回到带的**最顶**（实测 z#20 → z#17）。
   对一个**丢了** topmost 的窗口做同样调用**不管用**：它会落到带的**最底**（实测 z#73，仍在另一个 topmost 之下）
   ⇒ 所以"从降级状态恢复"必须断言**两遍**。

**落地的东西（`dock.cpp` 的 "z-order policy (task 1)" 段，紧跟 `CollectOurWindows()`）**

- `ZWatchTick(now)`：挂在原有 16 ms housekeeping 里，自身 450 ms 节流；每次 `EnumWindows` 两遍
  （先收集我们的可见窗口 + 外接矩形，再从上往下找"压在我们上面、且和某个我们窗口相交"的**第一个**窗口）。
  命中或发现"我们某个窗口丢了 topmost"→ 按 **组框 < 浮窗 < 条 < 面板/设置/缩略图** 的顺序重新断言（最后断言的最靠上）。
- **不抢的**（`ZExemptClass`）：任务栏 `Shell_TrayWnd`/`Shell_SecondaryTrayWnd`、`XamlExplorerHostIslandWindow_WASDK`、
  `Windows.UI.Core.CoreWindow`（开始菜单/搜索/IME/通知宿主）、托盘浮窗、`#32768`/`tooltips_class32` 等。
  另外**托盘原生浮窗在屏上、或转发的应用菜单开着时整段不动**（§3.19 的托盘/任务栏状态全靠它）。
- **截图这半边（用户 2026-11-22 的定义，别做错）**：dock **要出现在截图和录屏里**，
  只是"截图过程中（框选、框选完的更多设置）要被压到后面、不能抢鼠标"。所以**没有**用
  `WDA_EXCLUDEFROMCAPTURE` 永久隐藏自己 —— 那是另一回事，用户明确否掉了。
  判定 = 一个**非 shell、topmost、占满≥90% 显示器**的窗口压在我们上面（或它就是前台）；
  一旦判定成"截图/全屏覆盖层"，就把我们**全部窗口降成非 topmost**（`ZDemoteOurs`），
  锁住那个 pid，直到它**没有可见的非 cloaked topmost 窗口**了（+900 ms 宽限）才断言两遍恢复。
  为什么要主动降级而不只是"不去抢"：我们自己的显示路径（`CompanionVisibilityTick`、组框 show 分支）会
  `SetWindowPos(HWND_TOPMOST)`，不降级的话 dock 会在框选拖到一半时自己弹回覆盖层上面。
  实测：SnippingTool 的覆盖层根窗口 `SnipOverlayRootWindow` 是 **cloaked** 的（真正可见的是它的 `XamlWindow` 子窗），
  而且它**只是间歇性地拿前台** —— 所以判定不能只看 `GetForegroundWindow()`，必须用 z 序证据（第一版踩过这个坑）。
- 新 ini 键 **`[dock] zWatch=1`**（0 = 整个看门狗关掉，纯 A/B 用）。日志 `zwatch: ...` 记每一次变更；
  `slow: zwatch scan X ms` 只在 >3 ms 时出现（实测平时 <3 ms，不出现）。

**验收现状**

- `dev/t_zfix.ps1`（新）：A 新 topmost 窗口压上来 → 看门狗自己爬回去；B 从外部把我们降级 → 恢复 topmost 且回到对方之上；
  C Win+Shift+S 覆盖层在前 → 我们变 tm=0 且在其下，覆盖层消失 → 恢复 tm=1。**连跑 3 次全 5/5 通过**。
- §3.19 自动化判据复跑通过：`t_winbtn_taskbar.ps1 -Mode cycle -Gap 180 -Cycles 10`（任务栏全程 y=1078）、
  `t_winbtn_repro.ps1`（C 段 minY=1078 riseAt=-1）、`t_tray_watch.ps1 -Clicks 2`（升/收全程 y=1078，cloak 正常）。
  第 3/5 条（开始菜单+任务栏一起出/收）仍需**用户手工验**。
- `dev/t_tray_watch.ps1` 里 `$strip = IntPtr.Zero` 的笔误已修（之前每次都拿不到条窗口、报错退出）。

**还没做的**：用户"10 分钟不被挡"的长时间验收要靠他自己在复现时段跑
`dev\t_zwatch.ps1 -Seconds 600 -Tag bad`（日志落在 `dev\zwatch_bad_*.log`，每行有 z#/topmost/覆盖者类名/前台），
再把它和"正常时段"的 `-Tag ok` 对照。**别在没跑过这两个日志之前改判定规则。**

#### 3.29.1 QQ 截图（Ctrl+Alt+X）实测 + "逛一下菜单 dock 就上来了"的真因（2026-11-22 01:2x）

**QQ 截图长什么样**（`dev/t_qqsnip.ps1 -Mode probe`）：按下 Ctrl+Alt+X 后 QQ 会放**两个全屏 topmost 窗口**，
同一个 pid：`QQScreenCapture Window Class`（标题 "QQScreenCapture BackView Window"）与 `Chrome_WidgetWin_1`
（标题 "QQ"，QQNT 是 Electron 套壳）。我们的条当场 tm=1 → 0，Esc 后 → 1。
⇒ 之前那条"非 shell + topmost + 占满显示器"的判定对 QQ 天然成立，不用为它单列白名单。

**用户报的现象**：选区一旦**把 dock 框进去**，只在选区里移动鼠标时 dock 老实待在下面；可是**去选区下面的
工具栏/菜单里逛一圈再回来，dock 就跑到选区上面了**。（选区没框住 dock 时它在上层，用户说可接受，因为那时
本来就不干扰截图。）

**真因不在看门狗**：QQ 的工具栏和它的菜单就贴在选区边上，也就是**贴着 dock**。鼠标移过去 = 进了 dock 的淡出半径
⇒ 浮窗淡入 ⇒ `CompanionVisibilityTick` 的显示路径里那几处 `SetWindowPos(c.hwnd, HWND_TOPMOST, ...)` 把整条链
（浮窗 + 条）重新塞回 topmost 带 ⇒ dock 立刻盖到选区上面。看门狗在整个会话里都在让位，是**我们自己的显示路径**把它拆了。

**修法（两层，都必要）**
1. 新增 `ZBandInsert()`（在 `QuickSettingsBeginPlacement` 的声明旁边，和 `g_zMode` 一起）：
   yield 期间返回 `HWND_NOTOPMOST`，其余时候还是 `HWND_TOPMOST`。改到的那两处自动路径：
   组框重新出现的 show 分支（两条 `SetWindowPos`）、浮窗出现的那段（移动那次在 yield 期间改成
   `SWP_NOZORDER` 的纯移动 + 两处 z 断言）。
2. **兜底**：`ZWatchTick` 在 yield 期间跑在**每个 tick**（~16 ms，不是 450 ms 轮询）——
   `ZAnyOursTopmost()`（~10 次 `GetWindowLong`）发现我们的窗口又带上 topmost 了，就 `ZDemoteOurs()` 压回去，
   150 ms 节流 + 5 s 一条日志 `zwatch: something of ours re-asserted topmost during a capture`。
   这一层照顾的是**没被点名**的那些断言（拖动、面板、缩略图、mod 里抬栏等）。

**验收**：`dev/t_qqsnip.ps1 -Mode flow` 全程实测（Ctrl+Alt+X → 在 dock 上拖一个选区 → 依次把光标停在
"工具栏下方 / 浮窗上 / 条上 / 回到选区中心" 各 700 ms）：**每一步 strip 和 tray 都是 tm=0**（浮窗甚至会淡入显示
vis=1，但不再把 dock 抬上去），Esc 后两者恢复到 tm=1。`dev/t_zfix.ps1` 也加了 D 段（snip 期间从外部强行
`HWND_TOPMOST` → 450 ms 内被压回去）和 E 段（snip 期间把光标停到浮窗上 → 两个窗口都还是 tm=0），现在 **6/6 通过**。

**⚠️ 上面第 1 层并没有盖住真正出问题的那个**（2026-11-22 01:2x，用户在真 QQ 上复现、日志抓到）：
真凶是**条自己的背景层更新**——`g_bgWnd` 那段 `UpdateBgWindow` 结尾有一句
`SetWindowPos(g_hwnd, HWND_TOPMOST, ...)`（注释 "keep the icon layer above the background"），
它**每次 alpha 变化都会跑**，也就是**每次淡入淡出**。光标一靠近 dock → 淡入 → 它把条塞回 topmost 带；
日志里那条 `zwatch: something of ours re-asserted topmost during a capture - demoted again` 就是兜底网把它压回去。
那句（和同一个函数里的 `g_bgWnd` 那句）现在都改成 `ZBandInsert()`。改完再跑真 QQ：
`01:21:54` 开、`01:22:00` 收，**全程没有再出现那条兜底日志**，tm 全程 0 —— 也就是说现在是我们自己的路径
一点都不抢，兜底网只是保险，不再被用到。

**给以后的人**：除了这两处，`HWND_TOPMOST` 还散在拖动/翻转/面板/缩略图/收缩展开等十几处**用户手势**路径里
（snip 期间根本点不到 dock，所以没动）。真要再收紧，就把它们一并换成 `ZBandInsert()`——它在非 yield 时
返回值恒等于 `HWND_TOPMOST`，**行为中性**，不会改变任何现有手感。

### 3.30 任务 2 落地（2026-11-22 01:3x）：双击闪避开关

- 新键 **`[dock] dodgeOnDoubleClick`**（默认 1 = 老行为），「图标条」页最后一行
  「双击空白处闪避（跳到另一侧）」，开/关。
- 断点只有两处：`WM_LBUTTONUP` 里那条"空白处第二次点击"分支（`g_cfg.dodgeOnDoubleClick` 不成立时连
  `IsBlankDoubleClick()` 都不进，顺手把 `g_lastBlankClickAt` 清掉），以及 `StartFlip()` 开头的兜底 return。
  图标双击启动/托盘按钮走的是同一 case 里的**别的分支**，完全不受影响；`g_flip.active` 期间的"只移动不重绘"逻辑一行没动。
- ⚠️ **踩到一个 UI 默认值的坑，顺手修了**：面板的行值走 `PageVal()`，它对"ini 里还没有这个键"的行一律按 **0** 显示，
  而 `LoadConfig()` 里这个键的默认是 **1** ⇒ 新配置打开面板会看到「关」，但其实功能是开的，点「开」也没反应。
  `SRow` 末尾新增 `int defv = 0;`（`PageVal` 用它做缺省），新的那一行写 `defv = 1`。
  其它行保持 0 = 行为不变；`glassLayer` 的缺省依赖 `materialOld`（迁移用），**静态 defv 表达不了，故意没动**。
- **验收**：`dev/t_dodge.ps1` —— 关：双击空白处条**不动**、日志里不产生新的 `flip:` 行；
  开：跳到镜像位置（这台机器 `y 41 -> 946`）并再次双击回到 `41`，4/4 通过。
  面板的写入路径也实测过（截图 `dev/dodge_row1.png` / `dodge_row3.png`：点「关」后 ini 变 0、点「开」变 1）。
- **给以后的人**：面板自动化点击很容易点歪一行。坐标换算是我这次用的（可以用）：
  截图是**面板 + 6 px 边框**，所以 `screen = panel.left + (imgX - 6), panel.top + (imgY - 6)`。
  我第一次少算了 30 px，把「滚轮翻页步长」从 1 点成了 4（**已改回 1**）。
  想省事就让用户自己点，或者用 `dock.exe --settings` 启动（`main()` 里有这个开关）先把面板打开再截图。

### 3.31 任务 3 落地（2026-11-22 01:5x）：贴边方角（"吸附"）变成每个窗口都有、各自能关

**先把定义钉死（用户 2026-11-22 01:34 的原话）**：这一项里"吸附"**只指一件事** ——
贴到工作区某条边时把**那条边的两个圆角**从配置半径动画收成 0。条本来就有（`UpdateSnap()` →
`g_cornerTarget[4]` → `AnimateCorners()` → `CornerRadiusAt()`），三图标浮窗从来没有（它画的是**统一圆角**：
`FillRound` + `EnsureFloatMask`，没有任何逐角状态）。判据沿用**长边决定**（横的只方上下、竖的只方左右，
用户明确选的），**组框不参与**。

**代码（三个改动点，都在同一条链上）**
1. `SRow`/流程不用变，新键 **`[dock] snap`**（默认 1）、**`[traybar] snap`**（`-1` = 继承条）。
   面板：两个「浮窗」页各一行「贴边方角」/「贴边方角（覆盖）」（`kRowsFloatDock` / `kRowsFloatTray`），
   `TrayKeyVal()` 加了 `snap`，`PageSet()` 的 `kPageFloatTray` 分支加 `g_trayBar.snapOv = v`。
2. `UpdateSnap()` 整体包在 `if (g_cfg.snap)` 里 —— 关掉就**永远不方角**（目标和配置半径一致）。
3. 浮窗有了自己的逐角状态：`Companion::snapAnim[4] / snapTarget[4]`，`CompanionSnapUpdate()` 用
   **`c.rc`（存的矩形，隐藏时也对）**、`CompanionSnapTick()` 在 `CompanionTick` 里每帧走一步（同 120 ms 缓动），
   **隐藏的窗口直接对齐目标**（没东西可动画、也没东西要重画）。
   绘制端把两处"统一圆角"换成逐角：`FillRound4F(rect, radius, factors, argb)`（`FillRound4` 变成它的薄壳，
   传 `g_cornerAnim`），`EnsureFloatMask(w,h,radius,factors)`（**缓存键里加了角系数**，玻璃底图和图片背景都用它）。

**又踩到两个"从 ini 改不生效"的坑，一并修了**
- `Reload()`（就是 `dev/t_dock_reload.ps1` 发 WM_TIMER 2 走的那条）**不重算条的 snap 目标** ——
  手改 `[dock] snap` + 重载，条一点反应都没有（验收脚本 F 段当场抓到的）。现在 `Reload()` 里调 `UpdateSnap()`。
- `RefreshCompanionAfterReload()` **不重读 `[traybar] snap`**（它只重画）。现在它重读这个键并 `CompanionSnapUpdate()`；
  **几何（x/y）故意还是不重读** —— 重载不该把窗口拽到别处。
- 顺带：`PageVal()` 里 `-1`（继承）在**开关行**上没法表达（只有两个药丸），会显示成「关」而实际是开。
  现在 `kPageFloatTray` 的开关行在读出 `-1` 时改为显示**生效值**（`GetInt(L"dock", key, row.defv)`）。
  这也顺带修好了「玻璃层」那行在浮窗页上的同样误报。

**验收**
- `dev/t_snap.ps1`（新，9/9）：A 浮窗贴底边 → `snap: traybar corners TL=1 TR=1 BL=0 BR=0`；
  B 它自己的开关关 → 全 1；B2 回到继承 → 又方；C `[dock] snap=0` 经继承生效 → 全 1；
  D 恢复 → 方；E 条贴顶边（`[dock] y=0`）→ `snap: corners TL=0 TR=0 BL=1 BR=1`；F 条的开关关 → 全 1；G 恢复 → 方。
  脚本会重启 dock 三次并把 ini 原样写回。
- **像素级证据**（一次性脚本，已删；截图留在 `dev/snapcmp_zoom.png`，左=开 右=关）：浮窗贴底边时，
  左下 10×10 角块亮度 **463.8（开）→ 162.6（关）**，同窗口中间对照组 **485.3 → 485.3 完全不变**
  ⇒ 真的只有角在变，不是整块变了。
- 条的观感回归：改了 `FillRound4` 之后重新截图（`dev/strip_now_crop.png`）与之前一致（圆角/玻璃/图标没变）。



