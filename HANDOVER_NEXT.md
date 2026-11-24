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

### 3.32 任务 4 落地（2026-11-22 02:0x–02:2x）：组的贴边隐藏 + 唤出区域

**用户给的数（2026-11-22 02:02，逐条照做，别自己改）**
- 与屏幕边界留 **15 px**；滑出到**完全看不见组框**再加 **5 px** 冗余；"最近边"= 四条边到对应屏幕边界距离的最小值，
  **只在开启瞬间判一次**，之后组只能贴着这条边滑动（到了屏幕角可以转弯）；唤出/隐藏都是动画但**要快**；
  "鼠标离开"的判定额外加 **20 px**（缩放时手会稍微出界）；唤出区域 **x px 厚**（0–10），
  **x=0 时不渲染但保留 1 px 的可点/可悬停厚度**；不可见模式下"自动隐藏"和"调完 x"各**闪两下、共 2 s**。
  边界用**显示器边界**（不是工作区）。

**ini（每组一份：`[group]` / `[group.N]`）**：`hideEdge=0|1`、`wakeExt=0..10`、`wakeVisible=0|1`（常显/仅闪烁）、
`wakeMode=0|1`（单击 / 进入）。面板在**组 N 页**：`贴边隐藏` + 三条子行，子行只在开关打开时可见
（`SettingsRowVisible`，面板高度自适应）。

**实现要点（`dock.cpp` 的 "贴边隐藏 (task 4)" 段，在 `GroupDragEnd` 之后）**
- 几何基准是 `GroupBounds()`（成员外接矩形 + group.margin）。**单窗成组不需要任何额外代码**——
  `GroupBoxMembers()` 对单成员故意返回 false（一圈框套一个窗口只是噪音），所以单窗组自然"没有框可滑"，
  滑的判定用的是 bounds。这一点用 `dev/t_hide2.ps1` 实测确认（见下）。
- `HidePlaceAtGap()`：把 bounds 摆到距离该边 15 px，并在另一个轴上夹进屏幕——**转弯就是这个夹紧 + 最近边重算**的副产品。
- `HideEdgeTick()` 每 16 ms 跑一次：算唤醒区 → 判鼠标是否在"组 ∪ 区域"（组那侧 +20 px）→ 触发隐藏/唤出 →
  按 `kHideAnimMs=160` 推进 `hideSlide` → 用 `GroupMoveBy()` 整体平移（组 1 走 `MoveStripNow`，别的组逐个
  `CompanionSetRect`）→ 画/藏唤醒区。
- 唤醒区是一个独立的 layered 窗口 `DockWakeWindow`（`HideWakePresent` 直接铺该组色调）：
  **常显** = alpha 40 常驻；**不可见** = alpha **1**（肉眼看不见，但 layered 窗口只有 alpha≥1 才能被点/悬停，
  和组框角那 4 个 1.6% 方块同一个套路），闪烁期间 alpha 96；`wakeMode=1`（进入）时窗口带 `WS_EX_TRANSPARENT`，不吃点击。

**踩到的坑（都实测过）**
1. **从面板打开开关会立刻自己滑出去**：那时鼠标在面板上，不在组里 ⇒ 现在 `HideEdgeAttach()` 给 1.5 s 宽限
   （`hideArmAt`），并且**我们自己的设置面板开着时一律不自动隐藏**。
2. **滑出距离算错**：一开始用 bounds 的厚度，结果还留 15 px 在屏幕内。正确是"从 bounds 的**远端**到该屏幕边的距离 + 5"，
   而且必须用**清醒时的** bounds 算，用当前（已经在滑的）矩形会自反馈。
3. **组小节名是 `[group.N]`（带点）**，不是 `[group N]`。第一版测试写错小节，白查了一轮。
4. `Reload()` 原本不重读组设置 ⇒ 手改 ini + `t_dock_reload.ps1` 对组的开关无效。现在有 `ReloadGroupsFromIni()`
   （只重读组键并重新贴边，**不动几何**——重载不该把窗口拽走）。

**验收**
- `dev/t_hide.ps1` **7/7**：开启 → bounds 贴到 15 px；鼠标离开 → 滑到 bounds 远端在屏幕外 5 px；
  唤醒区在边上、6 px 厚、跨度等于组宽；移进区域 → 回到**原来的位置**；关掉 → 不动、区域消失。
- `dev/t_hide2.ps1` **5/5**：把三图标窗单独放进 `[group.2]` 并只给那个组开隐藏 —— **单窗组照样贴边、滑出、
  点唤醒区回来**，而组 1（没开）的条一点没动。这就是"单窗成组不需要额外代码"的实证。
- **没自动化验过的**：闪烁的观感（2 s 两下）、屏幕角转弯的手感、开着隐藏时拖动的跟随感、组页那几行的实际排版。
  这几样请用户过一眼；不对再调常数（都在那一段顶部 `#define`）。

#### 3.32.1 当天晚上的五个修正（2026-11-22 23:3x–24:0x，用户逐条报的）

1. **`唤出方式` 的单击/进入接反了**：`wakeMode` 的值 1 是"进入"，而开关行左边那颗药丸 = **值 1**，所以
   `onText/offText` 必须写成 `(L"进入", L"单击")`。改的是 `kRowsGroup` 里那一行的两个标签。
2. **开了贴边隐藏就不再有按距离的淡入淡出**（两套叠在一起手感很怪）：`GroupFadeTarget()` 里
   `if (g.hideEdge) return 255;` —— 贴边隐藏接管了显隐，距离淡出整个让位。
3. **"两个窗口还是各淡各的" 是真 bug**（H2b 只做了浮窗那一半）：
   - `UpdateAlpha()` 里条用的还是 `DistanceToWindow()` + **全局** `fadeStart/fadeEnd`，而浮窗用的是**组矩形 + 组的**距离
     ⇒ 两条完全独立的曲线。顺带发现 `GroupFadeAlphaForStrip()` 写了但**从来没人调用**（死代码）。
   - 现在一组一个值：`Group::fadeTarget`（每 tick 由 `GroupFadeTarget()` 算，距离量到 `GroupBounds()`、用组的数）
     + `Group::fadeNow`（按同一个 ~120 ms 步进缓动）。条读 `DefaultGroupFadeAlpha()`，浮窗直接取自己组的 `fadeNow`
     （不再自己缓动）。`dev/t_fadefix`/日志实测两者逐帧同步：`tray 255→221→187→160` 与 `strip 255→221→187→160` 一模一样。
   - ⚠️ 顺带修掉一个隐藏坑：条的 alpha 原来**只在光标移动时才采样**，换成一个会动画的值后条会卡在最后一次采样值上
     （日志里根本没有 `fade: strip` 行）。现在 housekeeping 里每 tick 比一次 `g_alpha != DefaultGroupFadeAlpha()` 就
     `UpdateAlpha()`。
4. **右键去点菜单项的路上把组收起来了**：`TrackPopupMenu` 跑嵌套消息循环、渲染 tick 照样在跑，所以指针走向菜单项时
   被算成"离开组"。现在 `HideEdgeTick` 里 `interacting = g_popupOpen || g_menuOpen || g_setWnd || g_gridVisible || 缩略图可见`
   ⇒ 期间**不收起**并把 `hideArmAt` 一直往后推（关掉后再留 600 ms 宽限）。实测 `t_menuhold.ps1` 2/2：
   菜单开着时指针跑到 (300,800) 组不动，菜单关掉后 2.5 s 正常滑出。
   （探针里关菜单要用 `PostMessage(WM_CANCELMODE)` —— 合成的 ESC **不会**送到弹出菜单自己的循环里，我第一次白查半天。）
5. **唤醒区域需要自己的色调**（组本来没有色调属性）：新键 `[group] hue`（缺省 = 用条的颜色），组页多一行
   **唤醒区域色调**（复用浮窗那套预设色块 + 取色器：`HueFor(2)` / `SetHueFor(2,..)` / 拾色器 action 22，`g_hueGroup` 由页面设置）。
   顺带抓到 `HideWakePresent()` 里 **R/B 通道写反了**（`hue` 是 0x00RRGGBB，而 DIB 字是 0xAARRGGBB）——
   绿色看不出来，红色会渲染成蓝色。用"绿/蓝两个色调对比色带"的像素测试才揪出来（`t_hidehue.ps1` 3/3）。

#### 3.32.2 第三批（2026-11-23 00:0x）：隐藏方案三选一 + 调参时的反馈 + 淡出也躲开菜单

1. **`隐藏方案` 取代了布尔开关**（用户："组设置那块有点长了"）：新键 `[group] hideMode`
   **0 = 距离 / 1 = 贴边 / 2 = 从不**（`kHideModeNames = {L"距离", L"贴边", L"从不"}`；原本想写"鼠标距离/贴边隐藏"，
   但选择行的段宽只有 ~54 px，4 个汉字会被截成"鼠标…"，所以缩成两个字的标签）。
   - 行可见性：`fadeStart/fadeEnd` 只在 mode 0；`hue/wakeExt/wakeVisible/wakeMode` 只在 mode 1；mode 2 都不显示。
     组页高度实测：**990 → mode1 874 / mode0 758 / mode2 642**（`dev/t_hidemode.ps1`）。
   - 兼容：没有 `hideMode` 时按老的 `hideEdge` 布尔推（`GroupLoad`）；用户的 ini 已经迁成 `hideMode=1` 并删掉 `hideEdge`。
   - `GroupFadeTarget()`：mode 1（贴边接管）和 mode 2（从不）都直接返回 255。
2. **调参现在看得见了**（用户："调节唤醒区域属性时根本没有闪烁 / 颜色一直不变"）。根因：色带**只在组隐藏时**渲染，
   调参时组是醒着的 ⇒ 什么都不显示。现在：
   - 组页开着时，该组的色带**以 alpha 40 常显**（预览用；`g_previewGroupId` 由 `SettingsPaint()` 设）。
   - 改 `wakeExt` **或** 改色调 → 触发 2 s 闪烁（alpha 96），**两种可见性模式下都会闪**
     （老逻辑 `!wakeVisible` 才闪，所以"常显"模式下改 x 完全没反应）。
   - 实测：`t_hidemode.ps1` 段 2 在组页打开时色带 dG=+22（绿色调可见），修复前整条带子根本不上屏。
3. **距离淡出也要在右键菜单打开期间停住**（用户："根据距离淡入淡出时也需要前往右键菜单时不淡出"）。
   抽了个 `OurUiBusy()`（`g_popupOpen || g_menuOpen || g_setWnd || g_gridVisible || 缩略图可见`），
   三处共用：`UpdateAlpha` 的早退、`GroupFadeTarget`（返回 255）、`HideEdgeTick` 的 `interacting`。
   实测 `t_fadehold.ps1` 2/2：平时淡出正常（16 行 `fade:`），右键菜单开着时 **0 行**。
   ⚠️ 探针注意：`WM_CANCELMODE` 关闭 `TrackPopupMenu` **不可靠**（`t_menuhold` 那次关了，`t_fadehold` 那次菜单一直开着），
   所以验收脚本不要依赖"从外部把菜单关掉"，要么分段重启、要么用设置面板当"我们的 UI"。
4. **色带的默认色调**：组的 `hue` 为空 = 跟随条的色调（`HueFor(2)`），我把自己测试写进去的 `[group] hue` 清掉了。

### 3.33 任务 5 落地（2026-11-23 00:1x–00:3x）：z 带属性 + 桌面"贴纸"窗口

**先量的事**（`dev/_bottomprobe.ps1`，已删）：`SetWindowPos(h, HWND_BOTTOM)` 之后窗口落在 **z#446**，而
`Progman`（桌面）在 **z#447** —— 也就是"**紧贴桌面上方、所有应用窗口之下**"，正是要的位置，
**不需要** `SetParent(Progman/WorkerW)` 那套"塞进桌面"的技巧。（顺带：`SetParent` 到 shell 窗口那个试验**看不见**，
别走那条路。）

**第一步：把 z 带变成属性（"小修以适配两种逻辑"）**
- `ZBandFor(HWND)`：先看 task 1 的截屏让位（`g_zMode==1` → `HWND_NOTOPMOST`），再看窗口自己的带
  （`ZIsBottomBand(h)` → `HWND_BOTTOM`，否则 `HWND_TOPMOST`）。原来那些 `ZBandInsert()`/`HWND_TOPMOST`
  断言点全部改成"传自己的窗口"：组框显示、浮窗显示、条的背景层、task 1 的看门狗。
- 带属性：`[traybar] band` 0/1，浮窗页多一行「Z 序：最上 / 最下」；`CompanionCreate` 对 band 1 **不加** `WS_EX_TOPMOST` 并在创建后 `HWND_BOTTOM`；reload 也会应用。
- 看门狗 `ZScan`：bottom 带的窗口**不参与**"丢了 topmost / 有人压在上面"的判定（这两件事对它是设计如此）。

**第二步：「贴纸」窗口 `DockDecoWindow`**（`dock.cpp` 的 "贴纸窗口 (task 5)" 段）
- 内容只有背景三层（透过背后 / 图片 / 纯色）+ 玻璃层 + 圆角，**没有图标、没有托盘格子**；绘制全部复用
  `BakeGlass`（自己的 `GlassTarget`，`[deco]` 用 `g_glass[0]`/`g_hue[0]`）、`EnsureFloatMask`、
  `PaintImageBg`、`FillRound`/`SetPixelPremul`。
- `[deco]` 小节：`enabled x y w h bgMode glassLayer radius solidOpacity`；样式键 `-1` = 继承 `[dock]`，
  但 `DecoCreate()` 会**把生效值写回 ini**，所以它那一页永远不显示"继承"。
- 交互：左键拖动（松手写回 `x/y`）、右键菜单（设置… / 重载配置 / 隐藏贴纸）；条自己的右键菜单多了「贴纸窗口」开关。
- 设置页：`kObjDeco` + `kPageDeco` + `kRowsDeco`（背景 / 玻璃层 / 背景图片 / 圆角 / 纯色不透明度）。
- 抓图：**故意允许出现在用户截图/录屏里**（它就是桌面的一部分）；但我们自己的玻璃抓图把它当"自己人"排除
  （`IsOurWindow`/`CollectOurWindows` 加了 `g_decoHwnd`）。
- ⚠️ 踩坑：`ZIsBottomBand()` 第一版忘了加贴纸 ⇒ `SetWindowPos(ZBandFor(...))` 把它**提成了 topmost**（z#16，
  比条还高）。`dev/t_deco.ps1` 当场抓到（"not topmost" / "directly above the desktop" 两条一起红）。
- 另一个语义修正：`DecoUsesGlass()` 必须和浮窗一致 —— 只有 **透过背后 + 玻璃层** 才烤底图；
  图片背景是画图片再叠色调（第一版把图片背景也走了玻璃分支，贴纸会显示"背后的桌面"而不是图片）。

**验收**：`dev/t_band.ps1` 5/5（浮窗切到 band 1 → z#437、紧贴 Progman z#438、无 topmost、条不受影响）、
`dev/t_deco.ps1` 5/5（存在且几何对、非 topmost、紧贴 Progman、应用窗口仍能盖住它、关掉后窗口消失）；
贴纸的像素用 `PrintWindow` 抓下来看过（`dev/deco_paint.png`：图片 + 圆角，正确）。
**没有做的**：贴纸不参与组/吸附/贴边隐藏/淡入淡出（它是桌面装饰，永远可见），也不能放图标。

**用户 00:39 报的两条（已修）**
1. **开了玻璃材质却没有玻璃页**：贴纸原来只有一页。现在它有 `kRowsGlassDeco`（玻璃不透明度 / 色调浓度 /
   模糊半径 + 四条共享的节奏行）和一张「玻璃」页，出现条件是 `DecoHasGlassLayer()`（层开且背景不是纯色，
   和浮窗同一条规则）。**它还有自己的玻璃参数**：`g_glass[]` 从 2 个扩到 3 个，`[2]` 是贴纸（`[deco]` 的
   glassOpacity/tintStrength/blurRadius，`-1` = 继承 `[dock]`），`DecoPaint`/`DecoTick` 全部改用它。
   `PageSet` 的 `kPageGlass` 分支加了 `section == "deco"` 的处理（`LoadConfig` 已经会把 `g_glass[2]` 重读一遍）。
   实测日志：`settings: obj=3 group=0 -> 2 page(s): 贴纸 | 玻璃`。
2. **不能调整尺寸**：贴纸现在按边/角拖动缩放（边框 8 px、角 18 px 的抓取带，1/2/4/8 位定义和条/浮窗一致），
   最小 80x60，夹在自己的显示器内，光标形状跟着变（SIZEWE/NS/NWSE/NESW，内部是 SIZEALL），
   松手把 `x/y/w/h` 写回 `[deco]`；缩放时 `DecoEnsureDib` 重建 DIB、重画、并把玻璃烤图标记为脏。
   实测 400x240 → 470x280 且 ini 同步。
   验收：`dev/t_deco2.ps1` 3/3（两条页面 + 缩放 + 落盘）。

### 3.34 ⚠️ 任务 5 重做（**下一次会话从这里开始**，2026-11-23 00:52 交接）

**为什么重做**：用户 2026-11-23 00:52 一口气报了 7 条问题，并且指出根因——**我把它写成了平行的
`Deco` 实现**，而设计意图是：

> **贴纸 = 三图标浮窗（companion）完全一样的东西**，只有两点不同：**永远不隐藏（常显）**、**不显示图标/托盘格子**。
> 而且**可以新建多个**（有上限）。

我的上一版（`struct Deco` + 单实例 + 共用 `[deco]` 小节）满足不了，于是出现了下面这些自相矛盾的地方。
**不要再在 `Deco` 上打补丁**，按下面的方案重做。

**§3.34.1 用户报的 7 条，逐条对应**

| # | 现象 | 真因 |
|---|---|---|
| 1 | 角落很难触发尺寸调整 | 我自己写的 `DecoEdgeAt` 用 8 px 边带 / 18 px 角；companion 用的是 `EdgeAt()` 的 **24 px 角方块 + `cz`**，手感好得多。直接复用 `EdgeAt()` / `CompanionProc` 那套 |
| 2 | 图片背景下"模糊半径"无效 | 先确认**浮窗/条在同样情况下是否有效**（`PaintImageBg` + 图片合成里 blurRadius 的用法，见 §3.27/§3.28）。若它们有效 ⇒ 照它们的做法搬；若同样无效 ⇒ 那是既有行为，只是看起来像 bug，别在贴纸里"修"出两套 |
| 3 | 不能选自己的色调 | `g_hue[]` 只有 2 个（条/浮窗），贴纸借用了条的 `g_hue[0]`。要变成"每个实例一份色调"（`HueFor()/SetHueFor()` 现在用 `which` 0/1/2 索引，需要扩成按实例索引） |
| 4 | 背景与条绑定、改不了 | 贴纸的 `[deco]` 样式键 `-1 = 继承 [dock]`（我图省事），而用户要的是**独立**。应改成绝对值的行集（`kRowsFloatDock` 那种），section 用各自的 `[sticker.N]` |
| 5 | 要能新建多个（有上限防卡死） | `g_deco` 是单实例。必须把 companion 变成**多实例**（见方案） |
| 6 | 右键「隐藏贴纸」改成「删除」 | 它本来就贴桌面，没有"隐藏"的需求。菜单应为 设置… / 删除（销毁窗口 + 从 ini 删掉该实例） |
| 7 | 新建之初要纯色不透明，否则找不到 | 现在默认继承条的"图片"背景，新建后可能和壁纸混在一起。创建时写死 `bgMode=2`（纯色）+ `solidOpacity≈235` + 一个级联位置 |

**§3.34.2 推荐方案（复用 > 新建）**

1. **companion 多实例化**（这是重做的核心，别绕过）：
   - 现在是 `static Companion g_trayBar;` 单例，而 `Companion` 结构本身已经带自己的 `rc/dib/glass/alpha/style`，
     天然就是"一个窗口"。改成 `Companion g_companions[kMaxCompanions]` + `int g_companionCount`
     （或者 `std::vector<std::unique_ptr<Companion>>`）。
   - 每个实例加：`int id`、`wchar_t section[32]`（托盘那个仍是 `[traybar]`，贴纸是 `[sticker.N]`）、
     `bool deco`（贴纸 = true）。`iniSection` 现在是 `const wchar_t*`，换成实例自己的 buffer。
   - **必须逐个改掉的单例硬编码**（grep `g_trayBar` 的地方，约 40 处）：`CompanionTick`、`CompanionGlassTick`、
     `CompanionVisibilityTick`、`CompanionFollowTo`、`CompanionCreate/Save/Load/SetRect/EnsureDib/Tooltip*`、
     `TrayCells`/`TrayRepaint`（`if (c.deco) 跳过三个格子和 hover`）、`TrayStateRefresh`（deco 不需要）、
     `IsOurWindow`/`CollectOurWindows`、`GroupMembers`（见 §3.34.3）、`SettingsBuildPages`/`TrayKeyVal`/
     `PageSet`（都按实例取 section）、`AnchorPublish`（deco 不需要锚点）。
2. **z 带**：已完成的 `ZBandFor()`/`ZIsBottomBand()` 直接用 —— 贴纸实例恒为 bottom（现在是靠 `g_decoHwnd` 判的，
   多实例后改成 `c.deco`）。`[traybar] band` 那一行已经能用（浮窗页「Z 序」），贴纸实例固定 band=1。
3. **样式页**：贴纸实例的页签 = `浮窗`（用 **`kRowsFloatDock`**，绝对值，不继承条）+ `玻璃`（`kRowsGlassDeco` 那套，
   但玻璃参数要按实例索引：`g_glass[]` 从固定 3 个改成 `std::vector<GlassCfg>` 或者按实例 id 索引）。
   `hue` 行已经在 `kRowsFloatDock` 里 ⇒ 只要 `HueFor(which)` 支持"按实例"，3 号问题自动解决。
4. **创建/删除**：条右键菜单加「新建贴纸」（上限 `kMaxStickers = 8`，到了就不加并 DLog 一行）；
   贴纸右键菜单 `设置… / 删除`。删除 = `DestroyWindow` + 从 ini 删 section + 从数组里移除 + 重排 id
   （**注意**：重排 id 会让 ini 的 `[sticker.N]` 错位，建议**不重排**，删除后留空位，新建时找第一个空 id）。
5. **常显**：贴纸实例不参与距离淡出、不参与贴边隐藏（`hideMode` 强制 2 = 从不，或者干脆不给它那一页/那一行）。
6. **创建默认**：`bgMode=2`、`solidOpacity=235`、`radius`=条的、size 420x260、位置从屏幕中心级联偏移，
   `enabled=1`，**写完立刻画一帧**，保证"创建了就能看见"。

**§3.34.3 需要用户拍板的两个点（重做前问一句）**
- 贴纸**要不要能加入组**？（"与三图标窗口一致"意味着能；但组开了贴边隐藏就会把它滑出屏幕，和"常显"冲突。
  建议：贴纸可以入组（跟随组拖动/缩放），但组滑出隐藏时**跳过贴纸**。）
- 贴纸**要不要参与吸附（贴边方角）**？（同"一致"逻辑 ⇒ 要；实现上就是把 `c.snapAnim/snapTarget` 也用起来，
  代码已经是逐窗口的，应该免费。）

**§3.34.4 上一版留下什么、删什么**
- **保留**：`ZBandFor`/`ZIsBottomBand`/`[traybar] band` + 浮窗页「Z 序」行、看门狗对 bottom 带的豁免、
  `dev/t_band.ps1`、HWND_BOTTOM 的实测结论（见 §3.33）、`dev/t_deco.ps1`/`t_deco2.ps1`（改写成多实例版本）。
- **建议删除/替换**：`struct Deco` / `g_deco` / `g_decoHwnd` / `Deco*()` 一整套、`kRowsDeco` / `kRowsGlassDeco` /
  `kPageDeco` / `kObjDeco`、`[deco]` 小节。它们和多实例 companion 方案重复且互相矛盾。
- 当前状态：`[deco] enabled=0`（已关掉，桌面恢复原样），代码编译通过但**属于未完成的原型**，
  条右键菜单里那个「贴纸窗口」开关也一起去掉。

**§3.34.5 复核清单（做完贴纸要能过）**
1. 条右键 → 新建贴纸 → 屏幕上出现一块**纯色不透明**的窗口，右键有 `设置… / 删除`。
2. 设置里改背景/图片/圆角/纯色不透明度/玻璃参数/色调 → **只影响这一块**，条和三图标窗不变。
3. 拖四个角、四条边都能缩放（手感与三图标窗一致），松手位置尺寸落盘。
4. 新建到上限（8）时拒绝并提示；删除一块后能再建。
5. 重启后所有贴纸都回来（各自的 `[sticker.N]`），且**常显**（不淡出、不隐藏）。
6. 贴纸永远在所有应用窗口之下、桌面之上（`dev/t_band.ps1` 的判据可复用）。

### 3.35 任务 5 重做完成（2026-11-23 19:2x）：**一类浮窗**，三图标窗只是它的特化

**用户 18:32 的新设计（比 §3.34 更进一步，提示词优先于本文档）**
> 不是"贴纸"和"三图标"两类窗口，而是**一类**：拥有三图标窗除图标外的全部属性，**再加**两件事——
> ① z 序变成用户可调的窗口属性（`最上` / `最下`）；② 内容多样化（时间、天气、一堆快捷方式、
> 文件夹快捷方式，像手机桌面文件夹那样多个应用放一起，甚至可以混装）。
> 做法："把三图标窗改成通用窗，然后特化（z=最上、内容=三图标）得到现在的三图标小窗"。
> 另外：**贴边隐藏最终也要有**（之前说不要，现在要），所以它和三图标窗行为基本一致、也能进组。

**六个我当场问清、用户逐条拍板的点**（`ask_user_question`，别再自己猜）
1. 内容模型 = **容器 + 条目**（一个窗口里放若干条目），不是"一个窗口一种内容"。
2. 本轮范围 = 通用窗 + 内容接口 + **时钟 + 快捷方式网格**；**天气只留接口、不联网**（代码里没有任何网络模块）。
3. 条目怎么加 = 右键菜单 + 文件选择器 **+ 拖放**（用户明确要拖放）。
4. 新建默认 z 序 = **最下**（桌面），设置里可改最上。
5. 用户可见的名字 = **`浮窗`**（和设置页签一致）。
6. "文件夹快捷方式" = **普通文件夹图标**（点开 = 资源管理器），名称显示去掉 parent path 的部分
   （`D:/A/B/C/` → `C`），**悬浮显示完整路径**；应用和文件夹同一个逻辑，可混装在一个窗口里。

**落地形状（`dock.cpp` 的"浮窗的内容 (items)"段 + Companion 改造）**

1. **`Companion` 多实例**：`static Companion g_comps[kMaxComps]`（`kMaxFloats=8`，slot 0 = 托盘），
   并且 `static Companion& g_trayBar = g_comps[0];` —— 这条**引用别名**让原来 100 多处
   `g_trayBar.xxx` 一行都不用改，是一天里最省事的一个决定。`g_compCount` = 用到的槽位数。
   - 每个实例自带：`sec[24]`（`[traybar]` / `[float.N]`）、`id`、`content`、`hue/hasHue`、
     `glassCfg`、`img`（图片背景合成缓存）、`items`、`iconPxOv`、`captionOn`。
   - **id 就是槽位号**，删除后槽位空着、下次新建复用；`[float.N]` 永远指同一个窗口（不重排）。
2. **窗口过程不再认单例**：`CompanionProc` 用 `GetWindowLongPtr(h, GWLP_USERDATA)` 取 `Companion*`
   （和组框用 `GWLP_USERDATA` 存 group id 是同一个套路）。类名两个：托盘的仍是
   **`DockTrayBarWindow`**（**故意不改**，`dev/` 里 ~20 个探针脚本按这个类名找它），
   用户窗口是 **`DockFloatWindow`**、标题 `dock float N`。
3. **内容接口**（就这几个函数，加一种内容只碰它们）：
   - `FloatLayoutCells()` 布局（网格 + `itemPage` 翻页）、`FloatCellH()` 单元格高度（图标 + 名称）
   - `FloatContentPaint()` 绘制（玻璃/图片背景是公用路径，见 `TrayRepaint`）
   - `FloatItemAt()` 命中、`FloatItemActivate()` 左键动作、`FloatItemTip()` 悬浮文本
   - `FloatContentTick()` 自刷新节拍（时钟 1 Hz；`RotateTick` 里每窗一次，日志
     `float: content tick id=N`）
   - 条目类型：`kItemApp` / `kItemFolder` / `kItemClock` / `kItemWeather`（天气**只画 `—°` + "未接数据"**，
     菜单里那项也叫「添加天气（未接数据）」——数据源是下一步的事）
4. **ini**：`[float.N]` 用**绝对值**行集（`kRowsFloatWin` / `kRowsGlassWin`），**不再继承条**；
   新增键 `items=`（`;` 分隔：`clock` / `weather` / 任意路径）、`iconSize`、`caption`。
   `[traybar]` 的"继承条"语义**原样保留**（托盘还是 `kRowsFloatTray`/`kRowsGlassTray`）。
   例：`items=clock;C:\Windows;C:\Windows\System32\notepad.exe`
5. **z 序**：`band` 已经是每窗口属性；`ZIsBottomBand()` 改成遍历 `g_comps`。
   `最下` 的窗口**永远 alpha 255、不参与淡出**（它是桌面的一部分）。
6. **组 / 贴边隐藏 / 贴边方角 / 拖动缩放 / 玻璃烘焙**：全部是 `Companion` 的字段或遍历
   `g_comps` 的循环，所以浮窗**天然**具备（用户要的"行为和三图标窗一致"就是这样来的，没写新逻辑）。
   唯一新增判断：**不在任何组里的用户窗口强制 255**（它是用户摆在那儿的挂件，不该按鼠标距离淡出）。
7. **新建 / 删除**：条右键加「新建浮窗」（默认 `band=1`、纯色 235、色调=条的、`group=0`、
   300x210 级联摆放）；浮窗右键 `添加快捷方式… / 添加文件夹… / 添加时钟 / 添加天气（未接数据）/
   移除条目 ▸ / 清空全部条目 / 设置… / 删除这个浮窗`。删除 = 销毁窗口 + 删掉整个 `[float.N]` 段 + 释放槽位。
8. **拖放**：`DragAcceptFiles` + `WM_DROPFILES` → 逐个 `FloatItemAdd()`（应用/文件夹自动判别）。
9. **手改 ini 能生效**：`FloatsReloadFromIni()`（`Reload()` 里调用）按 ini 里现存的 `[float.N]`
   段**补建缺失的、删掉消失的、重读已有的**；`RefreshCompanionAfterReload()` 改成遍历所有实例。
   ⚠️ 这意味着**重载现在会重读每个浮窗的 x/y/w/h 并搬回 ini 里的位置**（旧代码故意不读几何）。
   因为每次拖动/缩放都会落盘，正常使用看不出差别；手改 ini 想搬窗口时反而是想要的。

**删掉的东西（§3.34.4 的清单，全部执行）**
`struct Deco` / `g_deco` / `g_decoHwnd` / `Deco*()` 全套、`kRowsDeco` / `kRowsGlassDeco` /
`kPageDeco` / `kObjDeco`、`[deco]` 的读取、条右键那个「贴纸窗口」开关、`DecoTick`。
`g_glass[3]`/`g_hue[2]` 也拆了：条用 `g_glassStrip` / `g_hueStrip`，浮窗用 `Companion::glassCfg` / `.hue`，
`HueFor()/SetHueFor()` 的 `which` 编码改成 `0=条 / 100+槽位=浮窗 / 200+组 id=组色带`
（`HueWhichForPage()` 一处决定；`g_hueGroup` 这个全局没了）。`[deco]` 段**留在 ini 里没删**（无害，不再读）。

**踩到的坑（都很值钱）**
1. ⛔ **`BlendPremul()` / `BlendScaled()` 原来写死 `g_bits`/`g_dibW`**（条的 DIB）。以前只有条画图标，
   所以看不出来；浮窗一画就画进条的缓冲区（还被条的尺寸裁掉）。现在两者都走
   `g_paintBits`/`g_paintW`/`g_paintH`（`SetPixelPremul` 一直是这么做的）。**症状：浮窗里只有文字没有图标。**
2. ⛔ **`small` 是 Windows 头文件里的宏**（`rpcndr.h`：`#define small char`），
   `std::wstring big, small;` 直接编译报"意外的类型 char"。改名 `timeLine`/`dateLine`。
3. ⛔ **绝不要用 PowerShell 批量替换 `dock.cpp`**：`Get-Content -Raw` 按 ANSI 读 UTF-8 源码，
   中文全部变成 `以太�?` 并且**不可逆**（我这次已经把 `QueryNetworkInto` 等好几行搞坏过一次，
   `git checkout -- dock.cpp` 全部重做才救回来）。**要么用 read/edit 工具，要么用 python 按字节改。**
   顺手用过一次 python 按行删 467 行（Deco 块）：`read` 的行号是 1-based，`lines[end-1]` 才是第 end 行。
4. `SettingsBuildPages` 里 `wantKind == kPageFloatTray` 的页现在按 `SPage::objId`（原本叫 `groupId`）
   区分实例；忘了改那一行的话，打开任何浮窗的设置页都会落到托盘身上。
5. 组 1 用的是 `hideMode=1`（贴边隐藏）：**把一个浮窗加进组 1，它会跟着组一起滑出屏幕**
   （这正是"和三图标窗一致"）。所以验收脚本测"组框包含它"之前先把 `[group] hideMode` 临时设成 2，
   否则量到的是滑出去之后的坐标。
6. 弹右键菜单期间**整个渲染 tick 会停**（`TrackPopupMenu` 的模态循环不吃 `WM_APP+1`），
   菜单一关就恢复。老代码的托盘菜单也是这样，暂时不管。
7. 这台机器上 `FindWindowW` 从普通进程找不到我们的窗口（老坑，§3.23）。
   新脚本一律 `EnumWindows` + 类名（`dev/t_float.ps1` 里的 `FW::All()` 可抄）。
8. **从 PowerShell 删 ini 段要传 `[NullString]::Value`**，不是 `$null`：`$null` 会被绑成**空字符串**，
   于是 `WritePrivateProfileStringW(sec, $null, $null, ini)` 只写出一个空键（ini 里多一行 `=`）而
   段还在。删 `[float.N]` 的一次性做法（我就是这么清掉测试窗口的）：python 按字节按行删，
   注意这个 ini **混用 CRLF 和 LF**（按 `\r\n` 切会把 LF 行和下一行粘在一起）。

**验收（都能复跑）**
- `dev/t_float_accept.ps1` **13/13**：写 `[float.7]` → 重载 → 窗口存在/几何/可见/无 topmost/
  紧贴桌面上方（z#428 vs Progman z#429）；拖一个文件夹进去 → `items` 追加；
  `band=0` → 变 topmost 且在条之上（z#17 vs 条 z#19）；`group=1` → 组框长到包含它（frame 1029x1239）、
  窗口自己没被搬走；删段 → 窗口消失。**脚本最后会把 ini 还原并重启 dock**
  （切隐藏方案会把组 1 重新贴到最近边并落盘，只能靠重启复位）。
- `dev/t_float.ps1`：`Dock*` 窗口清单（类名/标题/矩形/可见/topmost/z 序）+ `PrintWindow`
  截图到 `dev/float_N.png`（分层窗口在 z 最下也能抓，屏幕截图抓不到）。
- 像素证据：`dev/float_1.png`（时钟 19:11 + 日期 + 文件夹 + notepad，浅绿纯色圆角）、
  `dev/float_2.png`（拖进去的 `System32` + `explorer.exe`）、`dev/settings_float1.png`
  （浮窗页：背景/玻璃层/色调/纯色不透明度/圆角/贴边方角/内边距/格子间距/条目图标尺寸/图标下显示名称/Z 序）、
  `dev/settings_tray.png`（托盘页仍是 浮窗|玻璃|组 1，`（覆盖）` 行显示"继承"）。
- 回归：条的图标一个没少、托盘三格（wifi/喇叭/电池 + 图片背景）正常（`dev/strip_check.png`、`tray_check.png`）。

**没做 / 下一步（都还没问用户）**
1. **天气数据源**：`wininet.lib` 其实已经链了，Open-Meteo（无 key）可以直接用；需要"城市/坐标"设置项。
2. **条目重排**：现在只能追加/移除，没有拖拽排序，也没有"插入到第几个"。
3. **条目的溢出**：窗口装不下时滚轮翻页 + 右下角 `1/2` 指示；没有"自动长大"。
4. **图标尺寸/名称字号**没有自动适配（名称字号 = 图标 26%，11–18 px 夹紧）。
5. 右键菜单/设置页的**观感**只做了截图，没让用户实际点过（拖放、点击启动、缩放、组内跟随都待用户验）。

### 3.36 用户 20:00 报的四条（2026-11-23 20:0x–20:2x）

用户原话（四条，逐条对应下面的修法）
> 时间样式、字体很丑……那个字体看起来像是从白色背景里面抠出来的，还残留着一些白色边缘。至于时间，从 github 翻一翻有没有现成好看的样式
> 玻璃层参数调节时不影响它背景变化（透过、图片均是这样），这个应该改坏了。
> 软件名就不要显示 .exe 后缀了。
> 开关玻璃层时不会动态出现玻璃标签，需要关闭再打开，这个是共有问题。

**1. 字体"从白底抠出来" + 时间样式**
- 真因有两层：`DrawTextAlpha()` 原来用 `CLEARTYPE_QUALITY`（次像素渲染在透明目标上会留彩色边），
  又把覆盖率 **×2.5**（"细边会消失"），于是那些边变成一圈可见的白边；再加上旧 `FloatDrawCaption`
  画了两遍（偏移 1 px 的"阴影"），整块字像抠图。
- 现在：`ANTIALIASED_QUALITY`（灰阶）+ 无放大 + **2–3 倍超采样后盒式降采样**
  （`SUPER = px>=60?3 : px>=20?2 : 1`）。这是不引入 DirectWrite 也能拿到接近矢量光栅器的边缘层次。
- ⛔ 超采样有个坑：GDI 按字号对字宽取整，2 倍渲染再把同一字符串排进 2 倍宽的框，
  小字会多出 1–2 px ⇒ 面板里「透过背后」变成「透过背...」（我当场抓到）。
  所以**小字（<20 px）保持 1 倍**，字号到 20 才开 2 倍。
- 字色不再"猜"：`FloatTextMode()` 直接**量刚画好的背景**（采样 `c.bits`，反预乘算亮度），
  亮底给近黑 `#1A1C22`、暗底给近白 `#F7F8FA`；只有背景"基本透明"（透过背后没开玻璃，平均 alpha<60）
  才用白字 + **1 px 描边环**（桌面图标那套）。用户那张"浅色图片上白字"的窗口就是这么坏的。
- 时间样式做了两套，`[float.N] clockStyle` 0/1，面板一行「时钟样式」：
  - **极简**：`Segoe UI Light`，字号 = 短边 0.62 em（实测数字墨迹只占 em 的 0.54，
    所以想要"看起来占 1/3 高度"就得用 0.62），字距 `-px/18`，下面一行日期/星期，`0xB0` 透明度。
  - **翻页卡片**：深色圆角卡 HH / MM + 中缝 + 冒号点，底部日期。**静态**，没有翻页动画。
- 参考项目（用户让我去找的，都不是拿代码，只取样式）：
  [FullWidget](https://github.com/hmgvibe/fullwidget)（38 个组件，主题里有"玻璃上的字"，
  时钟分数字/指针/翻页/世界时钟，可 CSS 自定义）、
  [CleanClocks](https://github.com/javigalan99/CleanClocks)（2025，10 种极简 Rainmeter 时钟，
  带取色器和 12/24h）、
  [Mond Enhanced Suite](https://github.com/danielcrumpler/Mond)（极简时钟+日历+天气）、
  [winclock](https://github.com/osoulmate/winclock)（国产简洁桌面钟：时间/阳历/农历/星期/日程提醒）、
  以及 GitHub `flipclock` 话题下的一堆 Fliqlo 复刻（翻页样式来源）。

**2. 玻璃参数调了没反应（透过、图片都一样）**
两处，都是我在 §3.35 拆分多实例时弄坏的：
- `PageCompanion()` 只认 `kPageFloatTray`（浮窗页），而**玻璃页的 kind 是 `kPageGlass`** ⇒ 每次调
  玻璃参数，`PageSet` 拿到 nullptr，只去失效 `g_imgStrip`，托盘和所有浮窗的合成图/烘焙**一点都没动**。
  现在玻璃页按 `section` 名反查实例（`[dock]` = 条的自己的缓存）。
- 就算找到了实例，`c.glassCfg` 还是**创建时读的那份**：`LoadConfig()` 只重读 `[dock]` 的。
  新增 `CompanionLoadGlass(c)`，`PageSet` 写完 ini 立刻重读该实例。
- 实测：面板里把「背景模糊半径」拖到 70%，日志立刻出 `image: composed ...`，窗口背景肉眼从清晰变糊
  （`dev/glass_before.png` → `dev/glass_after.png`）。

**3. `.exe` 后缀**：`FloatItemLabelFor()` 现在去掉 `.lnk` / `.exe` / `.url`（大小写不敏感）。

**4. 开关玻璃层时页签不刷新**（共有问题，条/托盘/浮窗都一样）
`SettingsBuildPages()` 只在 `ShowSettings()` 时跑一次。现在面板记住"我在给谁开设置"
（`g_setHintObj` / `g_setHintId`，`ShowSettings` 里记），`PageSet` 写完 `bgMode`/`glassLayer`
就调 `SettingsRefreshPages()`：重建页签、**尽量保持当前页**（当前页还在就不跳），重排高度再画。
实测：浮窗页点「玻璃层：关」→ 日志 `settings: obj=1 group=0 -> 1 page(s): 浮窗`，玻璃页当场消失。

**顺手修的**：条目网格按"实际有几个条目"居中（以前 2 个条目在一排 5 列的格子里会靠左）。

**验收 / 证据**
- `dev/t_float_accept.ps1` 仍然 **13/13**。
- 截图：`dev/clock_minimal.png`（极简 20:21）、`dev/clock_flip.png`（翻页 20:21）、
  `dev/settings_float_clock.png`（浮窗页多了「时钟样式」行）、
  `dev/float1_now.png`（用户自己那块模糊图片背景的窗口：条目居中、名称为 "Windows"/"notepad"、
  白色文字带细描边）、`dev/bg_row_new2.png`（「透过背后」不再被截断）。

**自动化面板点击的坑（写脚本的人一定要看）**
dock 进程是 **DPI-unaware**（没有 manifest），而探针按 §1.5 必须是 per-monitor aware，
于是**跨上下文投递的鼠标坐标会被系统按 125% 重算**：我 post 的 (383,258) 到了程序里变成 (479,323)，
点到了别的行（把「纯色不透明度」拉成了 55%，排查了一轮）。**投递前除以缩放比**（这台机器 /1.25），
或者把探针改成 DPI-unaware。这次就是靠这个才把「玻璃参数」和「页签刷新」两条实测下来的。

**行尾警告**：有一次 `edit` 之后整份 `dock.cpp` 变成了 CRLF，那一次提交是"15701 增 / 15457 删"的
全文件噪声（已把文件改回 LF 并 amend）。现在有 `.gitattributes`（`*.cpp text eol=lf`）兜底，
提交前后请看一眼 `git show --stat`。

### 3.37 开机后"点哪都没反应"（2026-11-24 18:0x）

用户原话：**"电脑刚刚开机，我们的项目处处bug，你去点击试试，点哪都没有响应，topmost 的窗口也只有在桌面才会出来"**。
三个独立的问题，前两个是"看起来像 click 坏了"的真因，第三个是"处处卡"。

**1. 让位状态卡死（用户报的那条）**
- 现象取证：`DockStripWindow`/`DockTrayBarWindow`/组框全是 `topmost=False`，z#87/88，而 Progman 在 z#283
  ⇒ 它们被夹在"所有应用窗口之下、桌面之上"，所以只有显示桌面时看得见；点击自然落到前台应用上。
- 日志指认元凶：
  ```
  15:41:33 zwatch: capture overlay in front (cls=LockScreenBackstopFrame pid=15008) - stepping below it
  15:41:33 zwatch: yielding to a capture/fullscreen overlay (pid=15008) ...
  ```
  15:41 = 开机 27 分钟（用户锁了一次屏）。`LockScreenBackstopFrame` 是**锁屏背板窗口**：topmost、全屏、
  一直存在 ⇒ 命中 task 1 的"截图覆盖层"判据。而让位的**解除条件**是"该进程不再有 topmost 窗口"
  （`ZPidTopmostVisible`），锁屏窗口永远不消失 ⇒ `g_zMode` 卡在 1 两小时二十分钟，期间任何重新断言
  topmost 的路径都被"demoted again"打回去。
- 修法（三层）：
  1. `ZExemptClass` 加 `LockScreenBackstopFrame` / `LockScreenControllerProxyWindow` / `LogonUI` /
     `Windows.Internal.Shell.LockScreen`；
  2. 新增 `SessionLocked()`（`OpenInputDesktop` 拿到的桌面名不是 `Default`），**锁屏/安全桌面期间
     zwatch 整个停摆**并且把 latch 清掉——解锁后第一次轮询照常走"被降级→重新断言"的恢复路径；
  3. ⛔ 这个检查放在 **450 ms 的轮询里**，不要放每 tick：`OpenInputDesktop` 是系统调用 + 桌面句柄，
     90 Hz 下它自己就吃掉好几个百分点。
- 断言（可复跑）：手动 `SetWindowPos(strip, HWND_NOTOPMOST)` → 1.3 s 内看门狗把它提回 topmost。
  命中判据：`WindowFromPoint` 在条/托盘上必须返回 `DockStripWindow`/`DockTrayBarWindow`。
- 仍存在的**既有设计**（不是 bug，别再"修"）：`band=1` 的浮窗就是桌面挂件，被应用窗口盖住时点不到；
  要它常在最前就把设置里「Z 序」改成"最上"。

**2. 托盘比条低 100 px（组框 214 高套着一行 88 的成员）**
- `GroupMoveBy()` 对组 1 只做 `g_cfg += d; MoveStripNow()`，成员靠 `CompanionFollowTo()` 的差量带过去；
  而 `CompanionFollowTo()` **第一次调用会故意吞掉差量**（"启动时不要把窗口拽到别处"）。
  **开机 attach 正是这样一次跳变**（`hide: group 1 glue ... move=0,-100`）⇒ 条移了 -100，托盘没动。
- 修法：组 1 的分支里**自己移动成员**（遍历 `g_comps`，`group==1`），先用
  `CompanionFollowResync(g_cfg.x, g_cfg.y)` 把跟随差量的基准对齐（否则下一帧 `CompanionFollowTo`
  会再移一次），最后 `GroupRecompute(DefaultGroup())`。
- 断言：`hide`/`wake` 各走一轮，条 y=28、托盘 y=30（两者的固有 2 px 偏移来自用户自己的摆放），
  隐藏时 -106 / -104，组框 1058x114。

**3. 空转 11 % 一个核 → 2 %**（"处处卡"的底层原因；顺带把发热也压下去）
用 `profMark()` 插桩量出来的三段（临时代码已删，需要时照抄：每 10 s 打印 `us/tick`）：
| 段 | 之前 | 之后 | 原因 |
|---|---|---|---|
| `tray`（面板/托盘/悬停动画那一段） | ~550 µs/tick | ~30 µs | `FindOverflowFlyout()` **每 tick 两次 EnumWindows** |
| 总计（实测 CPU） | 11 % | 2 % | 加上下面两条 |
- `FindOverflowFlyout()` 加了 400 ms 缓存（句柄失效立即重扫）。它被 `OverflowFlyoutOnScreen()` 从
  两个地方每 tick 调用，是全程序最贵的一行。
- `bgMode`/`glassLayer`/`solidOpacity` 原来在**绘制路径和每 tick 路径**里 `GetPrivateProfileInt`
  （每窗口每帧三次）⇒ 改成 `Companion` 里的 `bgModeRaw/glassLayerRaw/solidAlphaRaw` 缓存，
  `-1` 仍然表示"继承条"（在访问器里回落到 `g_cfg`，所以条改风格时继承的窗口照样跟着变）。
  `PageSet` 写完 ini 会同步这三个缓存。
- 桌面带的窗口（`band==1`）玻璃背景重新抓图的下限抬到 **2 s**：它背后就是壁纸，不会变。
  实测那一个 318x183 的挂件原本 10.7 次/秒 × 16 ms ≈ 17 % 一个核，现在 0.5 次/秒。

**验证清单（这次用的，都能复跑）**
- `dev/t_float.ps1`：z 序 + topmost + 矩形（看 z# 是否回到 10 上下、`topmost=True`）。
- `dev/t_float_accept.ps1`：13/13 仍通过。
- CPU：`(Get-Process dock).CPU` 前后差 10 s。
- 日志关键字：`zwatch: yielding`（不该再出现）、`zwatch: session locked`（锁屏时出现一次）、
  `hide: group 1 glue`（attach 时的位移）、`bake[`（桌面窗口应从 ~11 次/10 s 降到 ~5 次/10 s 以内）。

### 3.38 贴边组里"拖成员"引发的相对位移（2026-11-24 22:0x）

用户原话：**"明明选中屏蔽位移，条和三图标窗口收起一会儿，去唤出它们会发现两个窗口互相位移了，一上一下"**，
以及 **"解开屏蔽位移时调整它们的相对位移很难受，其中一个窗口向上移动超过另一个窗口的上边界时，另一个窗口会往下移"**，
并且自己给出了方向：**"贴边的组调整内部窗口位置时，组的上边界应该固定"**。

**两个症状同一个根因**（都在 `HideEdgeTick` 那段"贴边吸附"里）：
1. **吸附在"有成员被拖/被按"时也照跑。** `HidePlaceAtGap()` 移动的是**整个组**。于是正在被拖的那块
   每 tick 被拉回（下一次鼠标移动又把它放回去），而**没人按着的那块**默默吃下吸附的位移、没有任何东西把它放回来
   ⇒ 松手后两者永久错开。日志证据：`glue ... move=0,-19` 之后组框从 115 高变成 264 高（成员差 149）。
   更阴的是**按下但还没到 4 px 拖拽阈值**的那一小段：`pressActive` 期间吸附也在跑，它把条先搬了 13 px。
2. **成员可以把"贴边"的那条边顶出去。** 上移某块 → 组的 bounds 上边界越过 15 px → 吸附把**整组**往下拉 →
   另一块跟着下来。这正是用户描述的现象。

**修法（两点，第 2 点按用户建议做）**
- 新增 `GroupMemberBusy(g)`：任一成员 `dragging || resizing || pressActive`，或条自己
  `g_dragging || g_pressActive || g_resizeEdge` ⇒ **吸附整个跳过**。
  （`StripPressBusy()` / `StripResizeBusy()` 两个小函数放在条自己的拖拽变量旁边，因为 `g_pressActive`
  和 `g_resizeEdge` 的定义点在 `GroupMemberBusy` 之后。）
- 新增 `GroupPinClamp(g, self, RECT* r)`：组处于贴边且醒着时，把被移动的成员**钳在贴边边界上**——
  先求"其它成员"的并集（组 1 里条也是成员，用 `GetWindowRect` 取实时位置），再和候选矩形求并，
  越过 pin 就整体偏移回来，并记一行
  `hide: group N pinned edge held - moved member clamped by dx,dy`（400 ms 节流）。
  在 `CompanionProc` 的成员拖拽分支里调用（`pressActive`→`dragging` 之后、`CompanionSetRect` 之前）。
- ⛔ **pin = `kHideGap + g.margin`，不是 `kHideGap`**。15 px 的间距是量到**组框**的，而
  `GroupBounds()` 会把成员并集按 margin 外扩 —— 第一版只钳到 15，成员就能比组的内边界高出一个 margin
  （这台机器 13 px），松手后吸附又把整组往下拉 13，**位移照旧**。这一点是靠日志里
  `glue bounds=440,2 ... move=0,13` 对上 `dbg` 的成员坐标才揪出来的。
- 故意**没有**给"条自己的拖动"和"成员缩放"加钳制：它们的位移是均匀的（要么整组动，要么只有自己变大），
  松手后吸附把整组重新贴边不会造成相对位移；加钳制反而会让"把 dock 从贴边拖开"变得不可能。

**验收（都能复跑，脚本是临时的一次性探针）**
- 三轮 hide/wake（`屏蔽位移` 开）：条/托盘的 y 偏移**恒为 3 px**（醒 28/31 → 藏 -107/-104）。
- 把托盘往上拖 50 px（`屏蔽位移` 关）：托盘停在 28（= 15+margin），**条一动不动**。
- `屏蔽位移` 开时拖成员：整组一起动，松手吸附均匀回位，偏移不变。
- `dev/t_float_accept.ps1` 13/13；空转 CPU 3.4 %（§3.37 之后）。

### 3.39 让位状态第二次卡死：这次是"钉在桌面上"的聊天窗（2026-11-24 23:26）

用户原话：**"鼠标放到顶上没有弹出组，应该是出来了，但是窗口优先级在下面"**。

- 取证：`DockStripWindow`/`DockTrayBarWindow` 又是 `topmost=False`（z#34/35），日志里
  `zwatch: something of ours re-asserted topmost during a capture - demoted again`，
  而"让位"开始于 **23:08:03**，一直没释放。
- 元凶：`Chrome_WidgetWin_1` pid 16340 = **QQ 的「钉在桌面上」小窗**（558x500、topmost、当时是前台）。
  §3.38 之前的**保持条件**只要求"该 pid 还有任意 topmost 可见窗口"（`ZPidTopmostVisible`）——
  那是为了覆盖"截完选区后剩下的那条小工具栏"，但一个**永远置顶的小聊天窗**完全满足，于是无限期卡住。
- 修法（只动"保持/释放"，不动"触发"）：
  - 抽出 `ZIsFullscreenTopmost(h)`（topmost + ≥90% 显示器），`ZIsCaptureWindow()` 和保持判定共用；
  - 保持条件改成：**该 pid 还有全屏 topmost 窗口**（选区框/全屏游戏/全屏视频），
    **或者**它还有个小 topmost 窗口且**仍是前台且 latch 不足 60 s**（截屏工具的工具栏阶段）；
  - 其余情况 900 ms 宽限后释放，并打一行
    `zwatch: pid=N still has a topmost window but nothing fullscreen and fg=... - releasing the latch`；
  - 前台是**我们自己的窗口**时不再当作 overlay（`fgPid != GetCurrentProcessId()`）。
- 断言：重启后 `dev/t_float.ps1` 里全是 `topmost=True`，条 z#15 **高于** QQ 置顶窗（z#32）；
  重启至今没有新的 zwatch 让位行；`dev/t_float_accept.ps1` 13/13。
- **教训（写在这儿免得第三次踩）**：这个 latch 的"触发"很便宜，"保持"必须苛刻。凡是"某进程还有
  topmost 窗口"这种判据，永远会有用户自己的置顶窗口来踩。以后给这类状态加条件时，先问一句
  "如果一个普通用户的置顶小窗正好满足它，会怎样"。

### 3.40 ⚠️ 未解决：点图标"有时没反应"（2026-11-24 23:42 用户报，留给下一次会话）

用户原话：**"刚刚两次点击图标成功了，但是再往前几次点击了但是没响应，为什么？日志能推断出不？"**

**已有的日志证据**（这次运行的 `dock.log`，条上每次点击都会留一行 `LBUTTONDOWN` + 一行 `click slot=`）：
```
22:24:16.403 LBUTTONDOWN at 719,46 slot=-1 of 9 (alpha=255 through=0)
22:24:16.533 drag start                       <- 空位点击被当成拖拽起手
22:24:19.577 LBUTTONDOWN at 716,51 slot=-1 of 9 ...   drag start
22:45:09.469 LBUTTONDOWN at 705,81 slot=-1 of 9        <- 之后没有任何 click 行
22:36:08.008 click slot=4 hwnd=0000000000000000 lnk=...\EchoMusic.lnk    <- 启动（lnk 路径）
23:41:43.942 click slot=8 hwnd=0000000000000000 lnk=     <- 8 = 箭头("^")，见下
23:41:43.943 tray: native flyout toggle (wasOpen=0 flyout=...020950)     <- 它其实开出了托盘面板
23:41:46.495 click slot=4 hwnd=0000000000010A26 lnk=     <- 用户说的"成功"两次是这种
```
`layout: cap=9 show=7 cells=9 scroll=0 items=8 win=45,10-112,77 chevron=629,10-696,77`
⇒ 9 个格子 = Windows 键 + 7 个图标 + 箭头，**条宽 741 但格子只占 45..696**，所以右侧
（约 696..741）和左侧（0..45）都是**空白尾巴**，点在 `slot=-1`。

**从日志能确定的两类"没反应"**
1. **点在空白处**：`slot=-1` ⇒ 走"空白双击闪避"分支，单次点击**什么都不做**，而且会把那次按下当成
   拖拽起手（`drag start`），条可能被挪几个像素——用户体感就是"点了没反应"。目前**分不清**是用户
   真的点在图标之间，还是**命中矩形和画出来的图标不一致**（例如 hover 放大后图标变宽、而
   `g_slots[i].rc` 还是基准尺寸 ⇒ 视觉上压在图标上、命中却在缝里）。**这是第一要查的。**
2. **点在图标上、`click slot=N hwnd=...` 有行但窗口没到前面**：`ActivateWindow()` **一行日志都不打**，
   所以日志只能证明"我们收到了点击"，证明不了"把窗口拉起来了"。可能被
   `g_friendPid`/`g_focusGraceUntil`、任务栏 deny/cloak、或前台锁挡掉。**第二要查的。**
   （第 3 类：箭头那次其实成功开出了原生托盘面板，只是 1.5 s 后又被关掉，别误判成 bug。）

**建议的下一次会话怎么做（先量，别猜）**
1. 在 `ActivateWindow()` 里加日志：目标 hwnd / 调用前后 `GetForegroundWindow()` / 是否成功，
   失败时打原因（`IsIconic`、`IsWindowVisible`、owner、UIPI 拒绝……）。
2. 在 `WM_LBUTTONUP` 的 `slot=-1` 分支里加一行：**打印当时的全部 `g_slots[].rc` 和点击点**，
   再顺带打印 `g_hover` 与 hover 放大的当前倍率——这样"视觉上在图标上、命中在缝里"立刻能看出来。
   对照 `SlotAt()`/`ComputeButtons()` 与绘制里的 zoom 计算（`Paint()` 的 `clipL/clipR`、
   `g_hover`、`g_iconPx` 那一段），确认命中用的是放大后的矩形还是基准矩形。
3. 复现脚本：`SetCursorPos` 到某个图标的**左/右边缘 ±2 px** 各点一次，看 `click slot=` 是几号；
   再用 `hoverat.ps1` 之类把光标停住再点（排除"移动中点击"的干扰）。
4. 顺带看一眼那两条 `slow: companion visibility tick 13.7 ms` / `state+visibility 21.7 ms`
   （每次淡入淡出/贴边动画期间都会出现）：20–40 ms 的 UI 线程停顿不会丢点击，但会让点击"迟到"，
   如果它出现在点击路径上，用户也会觉得"点了没反应"。量一下 `CompanionVisibilityTick` 里
   `GroupRecompute`/`TrayRepaint`/`SetWindowPos` 各自占多少（§3.37 的 `profMark` 手法可复用）。

**相关代码位置**：`WndProc` 的 `WM_LBUTTONUP`（`click slot=` 那一大段分支）、`g_pressSlot`/`g_pressHwnd`/
`g_pressLnk` 的赋值（`WM_LBUTTONDOWN`）、`SlotAt()`/`ComputeButtons()`、`ActivateWindow()`、
`kSlotWin=-3` / `kSlotChevron=-1`（注意 `kSlotChevron` 与"空白"的 `-1` **同值**，日志里
`click slot=-1` 是空白、`click slot=8` 才是箭头，别混）。

**日志能否推断的结论**：能推断到"这次点击落在了哪个格子/是不是空白"，**推不出**"点在了图标上但窗口没起来"——
后者需要先补 `ActivateWindow` 的日志，这也是下一次会话的第一件事。

### 3.41 ✅ 已解决：点图标"有时没反应"（2026-11-24 23:5x – 2026-11-25 00:15）

先把 §3.40 的结论收紧：**日志其实已经能定性那三次"没反应"**，只要把每条按下的落点算清楚。
把 `dock.log` + `dock.old.log` 里全部 190 次按下逐条配对（按下 → 之后是 `click` / `drag start` /
`resize start` / 什么都没有），失败的那几次**没有一次是落在格子上**的：

| 时间 | 落点(客户区) | 变成了什么 | 为什么会"没反应" |
|---|---|---|---|
| 22:24:16.403 | 719,46 slot=-1 | 130 ms 后 `drag start` | 空白尾巴按下 + 手抖 4 px ⇒ 变成**拖动条**，点击被丢掉 |
| 22:24:19.577 | 716,51 slot=-1 | 同上 | 同上 |
| 22:45:09.469 | 705,81 slot=-1 | `resize start edge=8` | 落点在下边 10 px **缩放带**里 ⇒ 变成**改高度**（741x88 → 97），点击被丢掉 |

（`19:35:37 / 00:36:04` 另有两次 `slot=-1`，也都是尾巴/条外。第三次 `23:41:46 minimize`
是另一回事，见下面第 4 条。）

所以"点了图标没反应"在日志里其实是**"点了图标旁边几像素"**——而 4 px 的拖拽阈值、
10 px 的缩放带、以及"空白处单次点击什么都不做"三条叠在一起，正好把这种 5–10 px 的偏差
全部变成静默操作。另外三条**真的会丢点击**的路径也一并挖出来了：

**1. 边框 10 px 缩放带会"吃掉"点击（22:45:09 的现场）**
`EdgeAt()` 的带子是画在**内边距上**的（无玻璃时还会特意压在格子的外沿，见 `IconBox()` 上面那段注释）。
按在带子上立刻进 `g_resizeEdge`，松手时走"保存尺寸"分支——**一行点击日志都没有**，用户看到的是
"条好像动了一下，图标没反应"。
修法：**armed, not started**。按下只记 `g_resizeEdge` + `g_resizeArmed=false`，
`WM_MOUSEMOVE` 里指针真移动 ≥3 px 才 `armed` 并开始改尺寸（日志 `resize: armed after dx,dy`）；
`WM_LBUTTONUP` 时若从未 armed，就打一行
`resize: press at the edge never moved - treated as a click`，把 `g_resizeEdge` 清掉、
**继续走点击分支**（所以按在自家图标下沿松手仍然是启动）。真拉伸的手感不变
（`dev/t_click_resize.ps1`：97 → 121 → 97）。

**2. 内边距/尾巴上的按下没有格子（22:24:16 的现场）**
整条 741 宽、格子只占 22..718，两侧各有 22 px 空白；上下各有 12/13 px 内边距。
这些区域**是画了背景图的**，看起来就是"条的一部分"，人当然会往那儿点。
修法：`PickSlot()` 返回"最近的格子 + 距离（切比雪夫）"，按下时**距离 ≤ `SlotReach()`（= pad，夹在 4..12）就认那个格子**，
并打一行 `press: slot=N was D px outside its cell - taken as that cell`。
`LBUTTONDOWN` 那行也多了 `miss=D`。命令：3 px 的缝、6 px 的尾巴外、9 px 的下内边距，现在都会启动那个格子。

**3. 按下被静默丢弃（`GetKeyState` 说"已经松了"）**
`WM_MOUSEMOVE` 里原来的 `stale press: drop it` 分支会**直接清掉按下状态、什么都不做**——
如果 `WM_LBUTTONUP` 被别的窗口抢了 capture 或迟到，这次点击就在这里蒸发。
修法：改成补完这次点击——打 `press: button already up in a mouse move (slot=N) - completing the click`
并 `PostMessageW(h, WM_LBUTTONUP, 0, 0)`；晚到的那条真 UP 看到 `g_pressActive` 已经清了就什么都不做，
不会重复触发。（这条在会话里被合成消息**真的踩到了**，见"验证"第 2 条。）

**4. `clickActiveMinimizes` 会把"抬起窗口"变成"看不见的最小化"（23:41:46 的现场）**
`ActivateWindow()` 原来用 `IsInFront()` 判断"再点一次就最小化"。`IsInFront()` 对
"本线程活动窗口"这类状态也会返回真——于是一个被别的窗口盖住的窗口被判成"在前台"，
点它的图标 = **最小化一个你看不见的窗口**，屏幕上什么都没发生（下一次点它才是还原，所以"两次里成功一次"）。
修法：新增 `IsFrontAndVisible()` = 真前台（`GetForegroundWindow()==h`，本机常为 NULL 时退回
`FrontmostAppWindow()`）**且** `IsTopAtCenter()`（中心点没有被任何东西盖住）。
只有这种窗口才会被"点一下就最小化"，被盖住的一律老老实实抬起来。

**日志契约（这一轮加的，以后"没反应"必须能一眼定性）**
一次按下到最后一定落在下面某一行里，不会再有静默分支：
```
LBUTTONDOWN at x,y slot=N of M (alpha=.. through=..) miss=D
press: slot=N was D px outside its cell - taken as that cell   （近失吸附）
press: button already up in a mouse move (slot=N) - completing the click
resize start edge=E (armed once the pointer travels)
resize: armed after dx,dy
resize: press at the edge never moved - treated as a click
click slot=N hwnd=.. lnk=..
click: blank at x,y (screen X,Y) hover=H slots= 0:item=.. l,t-r,b sz=.. zoom=.. 1:...   （真空白，附全部格子+当前放大倍数）
click: slot=N -> hwnd iconic=.. inFront=.. onTop=.. fg=..                                  （抬/最小化 之前的状态）
click: slot=N has neither a live window nor a shortcut - nothing to open
activate: plain ok / alt tap ok / SwitchToThisWindow ok / gave up ...                      （原有）
```
外加一条**按需转储**：`SendMessage(strip, WM_APP+9, 0, 0)` 会写一行
`slots:press=.. slot=.. drag=.. reorder=.. resize=.. armed=.. hover=.. alpha=.. through=..`
后面跟着每个格子的实时矩形和 zoom。探针脚本用它取几何，**不要**再从 `layout:` 那行去推——
那行只是"静止几何"，悬停放大时整排会横移 ±12 px（这也解释了为什么手写坐标的脚本时灵时不灵）。

**验证（都能复跑，脚本留在 `dev/`）**
1. `dev/t_click_hit.ps1` —— 全部走 `SendMessage(WM_LBUTTONDOWN/UP)`（不动真实光标，悬停放大不能干扰），
   每个用例先 `WM_APP+9` 取实时格子再算点。实测（741x97，格子 22..718）：
   ```
   T1 exact centre      at 292,48  down=3/0   click=3  open
   T2 3 px into gap     at 331,48  down=4/3   snap=4/3px  click=4  open
   T3 6 px past chevron at 724,48  down=8/7   snap=8/7px  click=8
   T4 bottom band       at 292,93  down=3/10  edge=click  click=3  open     ← 以前这里是 resize
   T5 corner 2,2        at   2,2   down=-1/20 edge=click  click=-1 blank    ← 转储全部格子
   ```
2. `dev/t_click_real.ps1` —— 真 `mouse_event` 的按下/抬起（带 capture、悬停、动画）：
   R1 格子中心 / R2 缝里 6 px / R3 下内边距 / R4 上内边距，**四次都** `click 3 | plain ok`。
3. `dev/t_click_resize.ps1` —— 真拉伸还在：`resize: armed after 0,24 travel`，97 → 121，反向回到 97
   （顺带证明"未 armed 的按下"不会改尺寸）。
4. `dev/t_float_accept.ps1`：**13/13**。

**这一轮学到的事（下次别再踩）**
- **静默分支就是 bug。** 点击决策的每个出口都必须写日志；"什么都不做"这个出口尤其。
  §3.40 之所以"推不出"，就是因为有三条路一行都不打。
- **边框带永远会压在能点的东西上**（这里是内边距、无玻璃时是格子外沿）。所以：**不要用"按下"触发手势，
  用"移动"触发**，按下只记状态。
- **"画出来的"就是"能点的"。** 内边距和尾巴被背景图涂满了，用户眼里它和格子一样是条的一部分。
  想让它不可点，就别画它；画了就得给一个最近的格子（`SlotReach()`）。
- **`IsInFront()` 不足以支撑"再点一次就最小化"。** 任何"切换"类操作都要先确认
  "用户真的在看这个窗口"（前台 + 中心点无遮挡）。
- 测试脚本的两个坑：①`dock.log` 每条目是 `文本\r\n` 而文件是文本模式，实际落盘 `\r\n\r\n`，
  **按行号偏移读会漂**，从尾部找；②贴边隐藏时条是完全透明的，`SendMessage` 还能进去、
  **真鼠标/`mouse_event` 会穿透**，自动化点击前必须先唤醒（本会话还遇到过一次
  `SetCursorPos` 直接失败——桌面输入被冻住约 10 分钟，与 dock 无关，别误判成 bug）。
- 一次真实点击从按下到 `ActivateWindow` 之间有 3 次 `DLog`（各约 10 ms 的 open/write/close），
  §3.40 提的"20–40 ms 的 visibility tick 让点击迟到"这一轮**没有**复现到点击路径上，
  失败全部发生在更早的环节，所以没动 `CompanionVisibilityTick`。

**还没做的（如果用户再报"没反应"）**
- 尾巴深处（离最后一个格子 >10 px，比如 741 宽的条上 x>728）按下**仍然是空操作**——这是设计
  （那是背景），但现在会留下 `click: blank at ... slots=...`。真要修，旋钮是 `SlotReach()` 或条的宽度
  （用户手动拉宽到 741，内容只有 696，两侧各 22 px 空白）。
- 右键（`WM_RBUTTONUP`）仍是严格命中，没加容差：右键空白弹的是条自己的菜单，属于有意行为。
- 5 秒内的两次"空白单击"仍会触发 `dodgeOnDoubleClick`（躲闪），这是用户要的功能，别当成 bug。

### 3.42 ✅ 已修（§3.41 第 4 条的过度修正）：再点图标不收回（2026-11-25 00:20，用户复测）

用户原话：**"现在点图标能正常弹出，但是 100% 出现再点图标不收回（我确认我点的图标正中央、没有手抖变成拖动）"**。

**证据（§3.41 加的日志正好抓住了它）**
```
00:18:14.796 click: slot=4 -> 3F0AE0 iconic=0 inFront=1 onTop=1 fg=0000000000000000
00:18:15.236 click: slot=4 -> 3F0AE0 iconic=0 inFront=1 onTop=1 fg=0000000000000000
            → 两次都是 activate: plain ok，从不 minimize
00:17:59.683 click: slot=3 -> 2AF0D96 iconic=0 inFront=1 onTop=1 fg=0000000000000000
            → minimize: iconicAfter=1        （只有这一个窗口能收回）
```

**根因**：`IsFrontAndVisible()` 在"没有前台窗口"时的回退判据用了
`FrontmostAppWindow() == h`。这台机器 `GetForegroundWindow()` **几乎恒为 NULL**（§3.19 就记过），
而 z 序第一名是 **QQ「钉在桌面上」那个 always-on-top 小窗** —— 于是除了它自己，
**任何窗口都不满足**，`clickActiveMinimizes` 等于被关掉：`inFront=1 onTop=1` 也只是"再抬起一次"。

**修法**（只改判据，不动"被盖住就别隐藏"那条）：
```cpp
static bool IsFrontAndVisible(HWND h) {
    if (!h || !IsWindow(h) || !IsWindowVisible(h) || IsIconic(h)) return false;
    HWND fg = GetForegroundWindow();
    if (fg && fg != h) return false;    // 有别人拿着焦点：抬起，不隐藏
    return IsTopAtCenter(h);            // 且中心点没被任何东西盖住
}
```
- **不能**再用 `FrontmostAppWindow()` 当"前台"的替身（见上面的根因）；
- **也不能**只看 `IsInFront()`：它对"本线程活动窗口"也会给真，被盖住的窗口就会被
  **看不见地最小化**（§3.40 第 4 条的原故障）；
- 于是判据拆成两半：**焦点**（有别人拿着焦点就别隐藏）+ **中心点可见性**（盖住了就别隐藏）。
- 顺手给 `click: slot=...` 加了 `toggle=0/1`：这一行现在**直接说明这次点击会不会收回窗口**。

**验证（`SendMessage` 合成按下，真窗口操作；三种状态都过）**
```
最小化中 → 点：click: slot=4 -> 3F0AE0 iconic=1 ... toggle=0 → activate: plain ok   （还原）
在后台但可见 → 点：click: slot=4 -> 3F0AE0 iconic=0 inFront=0 onTop=0 fg=160892 toggle=0 → alt tap ok（抬起）
已在前台   → 点：click: slot=4 -> 3F0AE0 iconic=0 inFront=1 onTop=1 fg=3F0AE0 toggle=1 → minimize: iconicAfter=1（收回）
再点一次   → click: slot=4 -> 3F0AE0 iconic=1 ... toggle=0 → activate: plain ok        （又还原）
```
文件资源管理器（`3F0AE0`）按"抬起 → 收回 → 还原"循环，和用户的预期一致；
被别的窗口盖住中心点时仍然只会抬起（不会"看不见地最小化"）。

**教训**：**这台机器必须假设 `GetForegroundWindow()` 是 NULL**（§3.19、§3.40 都踩过），
任何"是不是前台"的判断都不能拿 `FrontmostAppWindow()` 顶替 —— z 序第一名经常是
用户自己的置顶小窗，而不是用户正在看的窗口。判断"用户在看的窗口"只有两个可靠信号：
**焦点是谁**、**它的中心点有没有被遮挡**。

### 3.43 ✅ 贴边隐藏把成员拆开：把"停放位置"变成不变量（2026-11-25 00:31 用户第三次报）

用户原话：**"组收起一会之后弹出发现组内两个窗口相对移动了，而他们是屏蔽位移的，可能之前就没修好，也有可能之前修好了但是刚刚修坏了"**。
（§3.38 修的是"拖成员时的相对位移"，这次是**另一条路径**。）

**取证（实测坐标，`dev/t_drift.ps1`）**
```
隐藏静止： strip=452,-115   tray=1218,-258   box=439,-271 1074x266
           条 = 醒位 28 - 143，托盘 = 28 - 286 = 两倍 → 两者相差 143 px
唤醒后：   strip=452,171    tray=1218,28      ← 条被多推了 143，托盘回到正确位置
```
143 = `outDist`（`awake.bottom - mon.top + kHideExtra` = 138+5）。也就是说：**一个成员被单独移动了
一整个 hide shift**，然后整组的"昏迷几何"把这个错误"当成真的"吃下去了。

**为什么以前会自我固化（两个设计缺陷）**
1. `HideEdgeTick()` 每个 tick 用**当前成员**算 `outDist`：
   `awake = HideShiftRect(b, side, -hideShift)`、`outDist = awake.bottom - mon.top`。
   一个成员偏了 143 → `GroupBounds` 高 143 → `outDist` 变 286 → 唤醒时整组多推 143。
   更阴的是**它自洽**：组框 266 高、`outDist` 286，看着都"正常"，重启也照样错（因为 ini 只记条的
   x/y，两窗口的相对位置由这条公式现场推）。
2. 藏起来时只把**组框左上角**放回轨道，修不了"只有一个成员往下挂出去"——左上角仍然是对的（实测：
   条 -115、托盘 -258 时组框左上角就是 (439,-271)，与"正确"状态一致）。

**修法（两条不变量，都不依赖"猜测触发者"）**
- **基准框**：新增 `Group::awakeBox` / `awakeValid`。**只有醒着（`hideSlide >= 0.999`）的组**才更新它；
  藏起来时 `awake`、`outDist`、唤出区域全部用这份存下来的框。滑动因此可逆：唤醒精确抵消藏起。
- **停放对齐**：新增 `Companion::awakeOffX/awakeOffY`（醒着时相对条的偏移，只在醒着时采样）+
  `AlignParkedMembers()`。**藏起来/正在滑动时**每个成员按这份偏移单独放回原位；同时保留
  "组框左上角放回轨道"的检查。两处修复都会记日志：
  `hide: group N was off the slide track by dx,dy - put back` /
  `hide: companion N was dx,dy off its parked slot - put back`（500 ms 节流）。
- 守卫：只在 `hideSlide < 0.999` 且 `!g.drag.active && !g.scale.active && !g_dragging &&
  !g_dragMovePending && !GroupMemberBusy(g)` 时动手——指针占着任何成员时绝不抢。

**验证（`dev/t_hide_soak.ps1`，都可复跑）**
```
round 1..6: hidden strip=-115,tray=-115 (off 0)   awake strip=28,tray=28 (off 0)  PASS   ×6
```
其中第 3/6 轮在**藏起来时**发了一次配置重载（设置面板应用走的路，`WM_TIMER 2`），
第 2/4/6 轮在**隐形托盘**上按了一次边框（用户会话里出现过 4 次 `tray bar: resize start edge=9`）。
另外：人为把条或托盘搬 143 px（`dev/t_track.ps1`）→ 立刻打出上面那两行并复位，醒来两边仍是 28。
`t_float_accept.ps1` 13/13；空转 CPU 0.16 s / 10 s（1.6 %，与 §3.37 之后一致）。

**没查清的部分（下次如果还出现，日志会点名）**
这一轮**没能复现出确切的触发动作**：用户那段时间的日志里有 4 次设置面板开合
（`settings: obj=1 -> 1/2 page(s)`）、5 次改色调（`hue: dock = #BBDDE8`）、拖/缩 `float.3` 好几次、
以及 4 次隐形托盘边框按下。可能性最大的是"某个成员在藏起来期间被单独移动了一整个 shift"
（`CompanionFollowTo` 只跳过 `dragging/resizing` 的成员，其他单独移动成员的路径都会和整组移动叠加一次）。
现在**不管谁干的，停放位置每个 tick 都被重新推导**，所以症状不会再留下来；如果还能看到
`was off the slide track` 那行，**它的 dx/dy 和时刻就指向触发者**（±143 就是"一整个 shift"）。

**顺带记住的操作坑**：用 `Set-Content` / `-replace` 批量改 `dock.cpp` 会把这台机器（Windows
PowerShell 5.1）的源码从 UTF-8 写成 GBK，`cl /utf-8` 会报一串 `C4828` 并且中文注释全坏。
改源码只用 edit 工具；坏了就 `git checkout -- dock.cpp` 回滚。

### 3.44 ✅ 真因：贴边隐藏的"停放位置"被写进了 ini（2026-11-25 01:43 用户第四次报）

用户原话：**"刚刚我又点了几十次 edge，无法打开，前几分钟都是正常的。我确认没有点歪、没有拖动，完全正常的点击。"**

这一条**不是**点击判定，而是**条本身被推下去了一整个 hide shift**：`[traybar] y` 里存着贴边隐藏的
停放位置（-115），启动时托盘从 -115 起来 → 组框变成 266 高 → `glue` 把整组往下推 143 →
**条停在 y=171**，而用户一直往 y≈28..125（条原来的位置）点。

**证据链（都能复跑）**
```
01:42:34 之后：日志里再没有一条 LBUTTONDOWN，但 hover 一直在变（鼠标确实经过了条的区域）
                ⇒ 按压没有到达 dock（不是命中的问题，是窗口不在那儿）
现场坐标：     strip=452,171   tray=1218,28   group box=439,15 1074x266
                ⇒ 条比托盘低 143（= 一个 hide shift），组框被撑到 266 高
启动日志：     float: loaded id=0 [traybar] 1218,-115 282x95 (follow=1 enabled=1 group=1)
               group 1: frame 439,-128 1074x266
               hide: group 1 glue side=0 bounds=439,-128 1074x266 move=0,143
ini：          [traybar] y=-115        ← 停放位置被持久化了
```

**为什么会被写进去**：`CompanionSave()` / `SavePosition()` 直接存 `c.rc` / `g_cfg`。
贴边隐藏的滑动是**整体平移**，所以在"藏起来"期间任何一次保存（在隐形托盘/条上误按出的
缩放、设置面板应用、拖动结束……日志里能看到 4 次 `tray bar: resize start edge=9`）都会把
**平移后的坐标**写进 ini。下次启动两个窗口就差了 143 px，而且组框 266 高、自洽得看不出错。

**修法**
- 新增 `g_hidePersistX/Y`（由 `HideEdgeTick` 对组 1 维护 = 当前 hide shift 的带符号反向偏移），
  `SavePosition()` 和 `CompanionSave()` 写 ini 时**抵消它**：**停放位置永远不进 ini**，
  存的永远是"醒着"的几何（日志里 `float: saved ... (awake x,y)` 会把两者都打出来）。
- §3.43 的"轨道 + 成员偏移"不变量继续兜运行时的错位；这条补的是**ini 入口**，
  也就是 §3.43 没覆盖的那一半（它解释了 00:31 那次"两个窗口相对位移"的 266 高组框）。
- 就地修好了被写坏的 `[traybar] y=-115 → 28`。

**新诊断（以后"点了没反应"一眼定性）**
```
press: left 800,60 went to 0000000000010A3E pid=18300 cls=Chrome_RenderWidgetHostHWND
       - NOT ours (strip 452,-115-1193,-18 slide=0.00 hidden=1)
```
每次"落在条（或它醒着时的位置）附近、但不是本进程"的左键按下都会记一行：
**谁接走了、条当时在哪、组是醒着还是藏着**。三种情形从此可区分：
①`LBUTTONDOWN` 有 → 命中/激活问题；②这行有、`hidden=1` → 条根本没在屏幕上；③这行有、
`hidden=0` → 条被别的窗口盖住了。

**验证**
- 重启：`strip=452,28` / `tray=1218,28` / `group frame 439,15 1074x123`（不再是 266）。
- `dev/t_ini_awake.ps1`：醒 28/28 → 藏 -115/-115（**ini 仍是 28/28**）→ 在**隐形托盘**上按边框
  （就是当年写坏 ini 的那条路径）→ ini 仍 28 → 醒来 28/28。
- `dev/t_hide_soak.ps1 4`：4/4；`t_float_accept.ps1`：13/13。
- 点击实测：点"看得见的" Edge 图标（978,219）→ `click slot=6 → activate: plain ok`；
  点条原来的位置（987,80，当时条在 171）→ 上面那行 `press: ... NOT ours`。

**教训**：**"藏起来"是临时平移，绝不能持久化。** 任何"为了显示/隐藏而移动窗口"的状态，
在写配置前都必须先还原成逻辑位置；否则一次误触就会把一个临时偏移固化成"用户设置"。
（这也是 §3.43 与这一条的关系：前者管运行时不变量，后者管 ini 入口，两者缺一个都会复发。）






### 3.45 ✅ 唤出之后立刻收起：点击落在"条刚滑走"的那一瞬间（2026-11-25 01:54 用户第五次报）

用户原话：**"我刚刚进行了四次点击，是正常的，但是四次点击前有一次发生了错误，点击 deepseek harness 没有打开"**。

**日志说了什么（这一段是逐行读出来的）**
```
四次正常点击（全部有按下+激活）：
01:54:12.772 LBUTTONDOWN slot=1 → 010A26（DSH）→ minimize
01:54:13.400 LBUTTONDOWN slot=1 → 010A26（DSH）→ activate: plain ok
01:54:16.352 LBUTTONDOWN slot=2 → 160892（Echo）→ activate: plain ok
01:54:16.877 LBUTTONDOWN slot=2 → 160892（Echo）→ minimize
失败那一下之前：条在**反复收起/唤出**，而且每次"收起"都发生在指针离开条之后 **3 ms**：
01:54:03.511 wake
01:54:04.097/04.134/04.180/04.430  hover -> -1 / 5 / 4 / 3        （指针快速掠过图标）
01:54:04.810 hover -> -1
01:54:04.813 hide                       ← 离开条 3 ms 就收起，没有任何缓冲
01:54:05.490 wake → 01:54:08.711 hide → 01:54:11.835 wake
```
⇒ 那一下点击**根本没有到达 dock**（没有 `LBUTTONDOWN`，也没有 `press: ... NOT ours`）：
条在用户把指针从顶部唤出区移到 DSH 图标的那几百毫秒里已经滑走了，点击落到桌面上。

**根因**：`HideBegin(g, true)`（唤出）**不刷新 `g.hideArmAt`**，所以"刚被唤出来的组"没有任何缓冲——
指针一离开（哪怕是为了够到图标而短暂出界 20 px），下一 tick 就收。唤出的滑动本身要 160 ms，
用户还得瞄一下再按下，这个窗口根本不够。

**修法**：新增 `kHideWakeDwell = 1200`，`HideBegin(waking=true)` 里 `g.hideArmAt = now + kHideWakeDwell`。
实测：唤出 01:56:53.124 → 立刻把指针移走 → 收起 01:56:54.333（**1.209 s**，之前是 3 ms）。
正常收起不受影响（离开后仍然会收，只是晚 1.2 s）。

**验证**：`t_click_hit` T1/T2/T4/T5 照旧；`t_hide_soak.ps1 3`：3/3（过程中还能看到
`hide: companion 0 was 0,143 off its parked slot - put back` / `hide: group 1 was off the slide track
by 0,-143 - put back`——§3.43 的不变量在"隐形托盘上按边框"时确实救了场）；`t_float_accept.ps1`：13/13。

**教训**：**"出现"和"可用"之间要留缓冲。** 任何"会自动消失"的界面，出现的瞬间用户还没到位；
收起计时必须在"出现"之后重新武装，而且时长要覆盖"滑动 + 瞄准 + 按下"，不是覆盖"滑动"。
（§3.44 管的是"条压根不在该在的位置"，这条管的是"条在该在的位置，但只在了 3 ms"。）

### 3.46 ✅ 隐藏状态下点"图标的位置"现在会把条唤出来（2026-11-25 02:41，用户第六次报）

用户原话：**"倒数第二次点击前又出错了，我确保我没有任何点击错误，标准的点击了图标。"**

**日志说了什么（这两行是本次新增的诊断直接给出的）**
```
02:40:54.327 LBUTTONDOWN slot=3 → 010A7C（Edge）iconic=0 → toggle=1 → minimize
02:40:55.026 hide: group 1 hide                 ← 指针离开，条收起（正确）
02:41:04.743 press: left 559,116 went to 00000000002309EC pid=22604 cls=NetUIHWND
             - NOT ours (strip 452,-115-1193,-18 slide=0.00 hidden=1)
02:41:06.703 press: left 567,133 went to ... NetUIHWND ... hidden=1
02:41:32.157 hide: group 1 wake                 ← 37 s 之后才重新唤出
02:42:13.300 LBUTTONDOWN slot=3 → Edge → activate: plain ok    ← 之后两次都正常
02:42:13.843 LBUTTONDOWN slot=3 → Edge → minimize
```
`pid=22604` = **POWERPNT（PowerPoint）**：那两下"标准的点击图标"落在 PowerPoint 的窗口上，
因为**条当时是藏着的**（`strip 452,-115`、`hidden=1`）。点击根本没到 dock。
（§3.45 的 1.2 s 缓冲解决的是"刚唤出就收起"，这次是"已经收了 37 s，用户还在点它原来的位置"。）

**修法**：`PressWatchTick` 里已有"落在条附近但不是我们的窗口"的诊断，现在加一条动作：
**条处于隐藏状态时，如果按下的点落在某个图标格子上（用 `PickSlot` 严格命中，不是整条框），
就把组唤出来**，并记一行 `press: x,y is on cell N of the *hidden* bar - waking the group`。
- 只认"格子上"，不认整框：这条带子在最上面一条，整框都算唤出区的话，"点浏览器标签栏/PPT 功能区"
  也会把条弹出来，那是新的骚扰。
- **不替用户点那个图标**：按下去的那一下可能是别的窗口，替他启动程序风险太大。所以他现在的
  体验是"第一下把条唤出来（图标就在指针下并高亮），第二下打开"。
- 配合 §3.45 的 1200 ms 缓冲，唤出之后不会立刻收。

**验证**：`t_wakeclick.ps1`（藏起来 → 点图标位置）：
```
02:44:55.899 press: 800,60 is on cell 4 of the *hidden* bar - waking the group
02:44:55.900 hide: group 1 wake
02:44:55.911 press: left 800,60 went to ... NOT ours (hidden=1)
→ 条从 -115 回到 28，并且 hover -> 4（图标就在指针下）
```
`t_click_hit` T1–T4 正常；`t_hide_soak.ps1 3` 3/3；`t_float_accept.ps1` 13/13。

**给用户的两条建议（都是设置项，不动代码）**
1. `设置 → 组 → 唤出区域宽度`：现在是 **3 px**，所以条藏起来之后几乎看不见、也不好摸。
   调到 12–20 会让"藏起来"这个状态可见、好命中。
2. 如果这个条基本常驻使用，`隐藏方案` 可以改成 **从不**（`hideMode=2`）：那就不会再有
   "点了它却已经收起来"这一整类问题。

**还剩一个可选项（等用户决定）**：让隐藏时的那一下点击**直接作用到那个图标**
（"一下就把 Edge 打开"）。代价是：条藏起来时，在它原来的那条带状区域里点任何别的东西
（PPT 功能区、浏览器标签栏）都可能顺带启动一个程序。默认没开。
