# 下一轮从这里开始（2026-11-22 00:0x 交接）

> 这份文件是**新会话的入口**。历史细节在 `HANDOVER_NEXT.md`（§0–§3.28）与 `PLAN_COMPONENTS.md`；
> 本文只讲：**现在是什么状态、哪些地方不能碰、以及这一轮要做的 5 件事**。

## 0. 30 秒速览

- 项目：自绘 Win11 dock。主源码 `dock/dock.cpp`（单文件，约 12.9k 行），另加 `windhawk/` 里的 mod。
- 构建 → 部署到 `%LOCALAPPDATA%\Programs\Dock\`；**先杀进程再构建**（否则 exe 被占用）：
  ```powershell
  Stop-Process -Name dock -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 400
  powershell -NoProfile -ExecutionPolicy Bypass -File dock\build.ps1
  Start-Process explorer.exe "$env:LOCALAPPDATA\Programs\Dock\dock.exe"
  ```
- 当前 HEAD：**`5a54862`**（任务 1 已提交）；最新源码备份：**`dock.cpp.bak54_zwatch`**（同状态），
  任务 1 之前的原样在 `dock.cpp.bak53_zwatch`。
- 用户当前的 ini（读出来的真值，别乱覆盖）：
  ```
  [dock]    bgMode=1(图片) glassLayer=1 blurRadius=0 glassOpacity=255 tintStrength=33
            refreshHz=90 captureHz=15 dragNoCapture=0  image=<老照片修复_....jpg>
  [traybar] bgMode=0(透过) glassLayer=1 glassOpacity=255 tintStrength=89
  [group]   enabled=1 margin=13 lineAlpha=189 lineWidth=1 radius=22 blockResize=0 blockMove=0
  ```
- 已完成的大块：H1（开始菜单输入 / 托盘双击）、H2a/H2b（设置按组件分层、浮窗实心底）、
  **H3 全套**（共享抓图管道 `BakeGlass` + 每窗 `GlassTarget`、浮窗真有玻璃、拖动冻结整块工作区快照、
  图片背景 cover/短边对齐/羽化/主色渐变、逐窗口玻璃参数、逐窗口 `hue` 色调、组框四角抓取、拖动逐消息移动）。
- H3 之后用户明确说"**目前效果已经不错了**"，然后提了本轮这 5 件事。

## 1. ⛔ 不能碰 / 不能忘（每次都踩回去的那些）

1. **`HANDOVER_NEXT.md` §3.19 的稳定状态 + 5 条判据**：任务栏 deny/cloak、`OpenPowerUserMenu()` 的
   deny + `Sleep(40)`、render tick 里的 deny 生命周期、`NativeTrayPageKeyboard()`、`TrayJobProc()` 不退回自绘宫格、
   mod 的 `g_allowOpen` latch 与 `MouseAllowedToShow()` 顺序。**改任何 z 序/tick/托盘前先读那一节并跑判据。**
2. **`presentSync=2`（`UpdateLayeredWindow` 之前 `DwmFlush()`）是正确性修复**，不是优化（§4.1）。
3. **`dock.ini` 是 ANSI/GBK**：脚本改它必须 `[System.Text.Encoding]::GetEncoding(936)` 读写。
   用 UTF-8 会把中文值（图片路径）永久毁掉 —— 已经踩过一次，很贵。
4. **不要用 PowerShell 的 `WriteAllText` 改 `dock.cpp`**：参数为 null 时会把文件清成 0 字节（踩过）。
   改源码只用 read/edit 工具。
5. 探针脚本必须 **DPI-aware**（`SetProcessDpiAwarenessContext(-4)`），否则 `GetWindowRect` 给的是虚拟化坐标。
6. **分层窗口按 alpha 命中**：想让人点到的地方必须有 `alpha > 0` 的像素（组框角那 4 个 1.6% 方块就是为此画的）。
7. 打开**模态对话框**（文件选择 / 取色器）**不能在鼠标消息里**直接调用：要 `PostMessage` 排队 + `g_pickBusy` 防重入
   （踩过"对话框关不掉、一直自己重开"）。
8. 图片背景：解码缓存长边 ≤1024；合成按 (图片, 尺寸, `glassLayer`, `blurRadius`) 缓存；
   `dumpBake=1` 会把合成结果写成 `dock_img_<w>x<h>.bmp`（诊断利器）。
9. **手感和观感只能由用户确认**（拖动跟手、吸附、闪避、色调）。数字能证明的只有耗时/几何/z 序这类东西。

## 2. 代码地图（按你要改的东西找）

| 子系统 | 关键符号 |
|---|---|
| 抓图/烘焙 | `GlassTarget`、`BakeGlass()`、`GlassFrozen`/`FrozenBegin()/FrozenEnd()`、`GrabScreenExcluding()`、`CaptureBackdrop()`、`CompanionGlassTick()`、`BoxBlurFast()` |
| 图片背景 | `ImageSrc`(解码缓存)/`EnsureImageSrc()`、`ImageBg`/`LoadImageCover()`/`EnsureImage()`、`PaintImageBg()`、`GalleryDir()`/`SettingsPickNewImage()` |
| 设置面板 | `SPage`/`SRow`、`SettingsBuildPages()`、`SettingsPaint()`、`RowAt()`/`RowFromX()`、`PageVal()`/`PageSet()`、`SettingsRowVisible()`/`SettingsRowDisabled()`、`IsSharedGlassKey()`、`SettingsResizeForPage()` |
| 组 | `Group`、`GroupRecompute()`、`GroupPresent()`、`GroupPaint()`、`GroupEdgeAt()`、`GroupCornerSize()`、`GroupDragTo()`、`GroupScaleTo()` |
| 浮窗 | `Companion`、`TrayRepaint()`、`CompanionPaintGlass()`、`CompanionSetRect()`、`CompanionFollowTo()`、`CompanionLoad()` |
| 条 | `Paint()`、`Present()`、`UpdateSnap()`、`AnimateCorners()`、`UpdateAlpha()`、`ComputeButtons()` |
| 闪避 | `g_flip`、`FlipTick()`、`FlipEnd()`、`IsBlankDoubleClick()`（日志 `flip: double click on empty strip`） |
| ini 读写 | `GetInt()`/`GetStr()`、`ParseHexRgb()`、`LoadHues()`、`LoadGlassCfgs()`、`StripIniBom()` |
| 我们的窗口清单（抓图排除用） | `IsOurWindow()`、`CollectOurWindows()` |

**ini 键现状**（避免重复造）：
- `[dock]`：iconSize gap pad radius bg hover fadeStart fadeEnd vertical clickActiveMinimizes thumbWidth/Height/Delay
  minIcon maxIcon scrollStep allowResize upscaleSmallIcons x y w h hasPos hasSize bgMode glassLayer hue solidOpacity
  dragNoCapture blurRadius tintStrength glassOpacity refreshHz captureHz captureBudgetMs presentSync presentOrder
  order extraPins image dumpBake debugBeacon **zWatch** **dodgeOnDoubleClick** **snap**
  **（`lightMode` / `tint` / `color` 已废弃，仅作迁移回退，待清理）**
- `[traybar]`：enabled follow group x y w h hasPos pad gap radius **snap** bgMode glassLayer hue solidOpacity image
  blurRadius tintStrength glassOpacity（外观类 `-1` = 继承条）
- `[group]` / `[group.N]`：enabled margin lineAlpha lineWidth radius blockResize blockMove fadeStart fadeEnd
- `[tray]`：doubleClick autoDoubleClick native

---

## 3. 本轮 5 件事

### 任务 1 — 窗口 z 序"优先级"bug + 截图时挡选区 —— ✅ **已完成（2026-11-22 0x，见 HANDOVER_NEXT.md §3.29）**

> 现状：这一节下面的问题描述、怀疑顺序都还留着当背景，但**结论已经落地**：
> ① 看门狗（`ZWatchTick`，450 ms）在被非白名单 topmost 窗口压住、或自己丢了 topmost 时，
> 按 组框<浮窗<条<面板 的顺序重新断言；② 截图覆盖层（topmost + 占满显示器）压上来时把 dock 全部降成非 topmost、
> 锁住那个 pid，覆盖层走了再断言两遍恢复 —— **dock 仍然出现在截图/录屏里**，只是不抢选区。
> 新键 `[dock] zWatch=1`。验收脚本 `dev/t_zfix.ps1`（6/6 通过）、`dev/t_qqsnip.ps1 -Mode flow`
> （QQ 截图全程 tm=0，含把光标停在工具栏/浮窗/条上），§3.19 判据 1/2/4 复跑通过。
> QQ 截图那个"逛一下工具栏 dock 就上来"的真因是**我们自己浮窗淡入的显示路径**在断言 topmost，
> 已用 `ZBandInsert()` + 每 tick 兜底压回解决，细节见 §3.29.1。
> **只剩用户自己的两项手工验收**：复现时段里 10 分钟不被挡（跑 `dev\t_zwatch.ps1 -Seconds 600 -Tag bad`
> 留下证据），以及 Win+Shift+S 框选实际手感。

**用户描述（要点）**
- 我们的窗口有时会被**新召出的窗口**遮挡；**与时间有关**：某段时间突然开始发生，这段时间内稳定复现，
  过了这段时间，同样的应用、同样的位置和尺寸就都正常了。
- 遮挡与"对方是否最大化"无关；边界压在我们窗口上时是"挡一半、露一半"，
  而且**随距离的淡入淡出交互还在继续**（说明窗口没死，只是被压到下面）。
- 有时"把所有窗口最小化露出桌面再打开"就好，但**不保证**。
- 另一面：**截图/拖选区时**希望 dock 不在截取图层上，但现在它在，还会干扰框选。
  用户自己也不确定"解决优先级过高"会不会加剧"优先级过低"。

**先量再改（不要猜）**
1. 写探针，在看到问题时连续采样并落日志：
   - 我们三个窗口（`DockStripWindow`/`DockTrayBarWindow`/`DockGroupBoxWindow`）与"压在上面的窗口"的
     **z 序**（`EnumWindows` 顺序）、类名、进程、`GetWindowLong(GWL_EXSTYLE)` 是否还有 `WS_EX_TOPMOST`；
   - 前台窗口、`DwmGetWindowAttribute(DWMWA_CLOAKED)`、是否全屏独占/被 shell 标记；
   - 同一份采样在"正常时段"再跑一遍做对照。
2. 只在证据指向某条时才动手。怀疑顺序：
   - **我们在静止期间不会重新断言 topmost**：只有 `Present()`/`CompanionSetRect()`/`GroupPresent()`
     移动时才 `SetWindowPos(HWND_TOPMOST)`；后到的 topmost 窗口可以合法地压住我们。
     → 候选修复：z 序看门狗（前台变化 / 新窗口出现 / 低频轮询时 re-assert），**但**要避开截屏覆盖层。
   - **截屏覆盖层**：`SnippingTool`/`ScreenClipper`/`ScreenSketch`/`MsScreenClip` 之类也是 topmost，
     我们一 re-assert 就压到它上面 → 框选被干扰。→ 候选修复：检出该覆盖层为前台时**临时 `HWND_NOTOPMOST`**，
     覆盖层消失后恢复；或临时给我们的窗口加 `WDA_EXCLUDEFROMCAPTURE`（机制已存在，见 `GrabScreenExcluding`）。
   - 两个需求方向相反（一个要更高、一个要更低）→ 建议做成**一条明确的策略**：
     "默认 topmost；检测到截屏覆盖层在前台 → 降到非 topmost；覆盖层消失 → 恢复"，并把每次变更写日志。
3. **验收**：用户复现时段内连续 10 分钟不被挡；同时 Win+Shift+S 框选时 dock 不出现在截取画面里、
   不挡住框选。必须由用户亲手验。

**要先问清楚的**：遮挡发生时，对方窗口是不是 topmost（探针能看出来）？用户是否接受"看门狗"式的定时 re-assert
（会有极低概率和全屏应用抢，需要白名单/黑名单）？

### 任务 2 — 双击闪避做成开关 —— ✅ **已完成（2026-11-22 01:3x，见 HANDOVER_NEXT.md §3.30）**

> 现状：双击**条的空白处**会"闪避"到中心线另一侧（日志 `flip: double click on empty strip -> ...`；
> 入口 `StartFlip()`（置 `g_flip.active = true`）+ `IsBlankDoubleClick()` + `FlipTick()`）。
> 已加 `[dock] dodgeOnDoubleClick=1/0`（默认 1）+ 「图标条」页最后一行「双击空白处闪避（跳到另一侧）」。
> 关掉只断这一条分支，图标双击/托盘按钮双击不受影响。验收 `dev/t_dodge.ps1`（关：条不动、不产生 flip 日志；
> 开：跳到镜像位置并来回复原），4/4 通过。

**原需求（存档）**

- 要：`[dock] dodgeOnDoubleClick=1/0`（默认 1 = 保持现状），「浮窗」或「图标条」页加一行开关；
  关闭后这条路径直接不触发，**不要**影响其它双击语义（例如图标双击启动）。
- `g_flip.active` 期间窗口"不重绘只移动"，所以关掉不必动这些代码，只需不进入。

### 任务 3 — 每个浮窗 + 条 的"吸附"开关 —— ✅ **已完成（2026-11-22 01:5x，见 HANDOVER_NEXT.md §3.31）**

> 用户澄清："吸附"只有一件事 = **贴边把那条边的两个圆角变直角**（`UpdateSnap()` → 圆角因子动画）。
> 条本来就有，三图标浮窗没有。现在两边都有，各自可关：`[dock] snap` / `[traybar] snap`（`-1` = 继承条），
> 两个「浮窗」页各一行「贴边方角」。判据仍是**长边决定**（横的只方上下、竖的只方左右，用户选的），
> 组框不参与。验收 `dev/t_snap.ps1` 9/9，另有像素级证据（贴底边时左下角方块 463.8 → 关掉后 162.6，
> 同窗口中间对照组 485.3 → 485.3 完全不变）。

**原需求（存档）**

### 任务 4 — 组的"贴边隐藏"（最大的一块）

**用户要求（逐条，别走样）**
- 「组」页加开关；打开后该组**立即贴向最近边**（**不是完全贴死**：与屏幕边界留一个小间距）。
- 之后当**鼠标离开窗口**（判断"离开"时要**把那段小间距算在窗口内**）→ 自动向屏幕外滑出隐藏。
- 只有开启时才显示的子设置：
  - **a 唤出区域 x px**：隐藏前窗口在"它隐藏到的那个屏幕边界"上的**投影区域**，向**外**扩 x px；
    范围 **0–10 px**。**每次调节完，该区域用窗口色调闪烁两下。**
  - **b 区域可见性：可见 / 不可见**
    - 可见：该区域**常驻**渲染成色块（窗口色调）；窗口自动隐藏时**不闪烁**；窗口唤出时**不渲染**。
    - 不可见：只有"窗口自动隐藏"和"调完 x"这两件事会让它用窗口色调**闪烁两下**，其余时间不渲染。
  - **c 唤出方案：单击区域 / 进入区域**（单击才唤出 / 一进入就唤出）。
- 单窗口也能成组（`[group]` 只有一个成员也是合法组），所以单窗天然支持这套，不用额外逻辑。

**实现提示**
- 需要一个新的"唤出区域"窗口（独立 layered：颜色 = 该组色调 `g_hue`，低 alpha；"单击"方案要能收到点击，
  "进入"方案可以靠 `WH_MOUSE_LL` 或定时 `GetCursorPos` 判断）。
- 隐藏/滑出动画：组成员 + 组框**同帧一起平移**（沿用组拖动/缩放的纪律：不要一帧移窗口、下一帧重绘）。
  `presentSync=2` 的顺序不能破。
- 可复用：`SettingsRowVisible()`/`SettingsRowDisabled()`（条件显示 + 面板高度自适应）、`g_hue`、
  `GroupBounds()`/`GroupBoxRect()`/`GroupRecompute()`。
- **必须先问清楚**（不然一定做歪）：
  1. "小间距"具体几 px？固定还是可调？
  2. 滑出多少：**完全出屏**，还是留出那 x px 的唤出区域在屏幕内？
  3. "最近边"按什么算：组矩形中心点最近的边？还是每条边的距离最小值？
  4. 单击唤出后，鼠标还停在区域上，会不会**立刻又自动隐藏**（需要延迟/滞回吗）？
  5. "闪烁两下"的时长与间隔；闪烁期间是否响应输入。
  6. 贴边隐藏与"组缩放/组拖动"如何互斥（拖动时应该暂停自动隐藏吧）。

### 任务 5 — bottommost 窗口（桌面美化）

- 要：新增一类窗口，z 序固定在**最底**（`HWND_BOTTOM`、**非** topmost、`WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW`），
  用来贴桌面做美化；**复用现有的绘制/玻璃/图片逻辑**，"小修一下支持调整优先级"即可。
- 关键改动点：现在全文有 **26 处** `HWND_TOPMOST`。需要把"窗口的 z 序级别"变成属性
  （`topmost` / `bottommost`），`Present()`、`CompanionSetRect()`、`GroupPresent()` 里按属性决定 `hWndInsertAfter`，
  别到处硬编码。
- 还要考虑：`IsOurWindow()`/`CollectOurWindows()`（抓图排除）、`WDA_EXCLUDEFROMCAPTURE`、
  组的成员/吸附/贴边隐藏是否适用。
- **必须先问清楚**：
  1. 它可交互吗？（点击穿透 / 可拖 / 可右键？）
  2. 参与组、吸附、贴边隐藏、淡入淡出吗？
  3. 要不要被截图/被玻璃抓图排除？
  4. 和壁纸/桌面窗口（`Progman`/`WorkerW`）的层级关系：只需"在所有普通窗口之下、桌面之上"，
     还是要真的贴进桌面（`SetParent` 之类）？

---

## 4. 工具（都在 `dock/dev/`）

| 脚本 | 用途 |
|---|---|
| `build.ps1`（上一级） | 构建 + 部署（先杀 dock） |
| `t_dock_reload.ps1` | 让运行中的 dock 重载 ini（`WM_TIMER 2`）。**不改窗口尺寸**，尺寸改动要重启 |
| `hoverat.ps1 -X -Y -Out -Wait` | 移动光标 + 回读坐标确认 + 截全屏（`SetCursorPos` 会因 UIPI 静默失败，必须回读） |
| `t_groupbox.ps1 -Margin 13` | 组框几何 + 命中判据（`geometry matches ...` / `WindowFromPoint`） |
| `t_corner_grab.ps1` | 四角缩放是否真的能触发（逐角按下 + 拖 + 还原） |
| `t_winbtn_taskbar.ps1 -Mode cycle` | §3.19 的任务栏稳定判据（全程 `y=1078`） |
| `t_glassdrag.ps1` / `t_circledrag.ps1` | 拖动 / 快速画圈（后者自带 lag 统计） |
| `t_groupdrag.ps1 -Inset 6` | 真正拖动整组（会改尺寸并写 ini，用完记得复原） |
| `t_zwatch.ps1 -Seconds 600 -Tag bad` | **任务 1**：长时间采样 z 序（z#/topmost/压在上面的类名/前台），日志 `dev\zwatch_<tag>_*.log`；`-Once` 是一次完整 dump |
| `t_ztry.ps1` | **任务 1**：机制实验（新 topmost 窗口压上来 / 重新断言 / 降级后的行为），一次跑完自动收拾 |
| `t_zfix.ps1` | **任务 1 验收**：A 看门狗自己爬回去、B 外部降级后恢复、C 截图覆盖层让位与恢复，5 条判据 |
| `t_snipwatch.ps1` | 看 Win+Shift+S 覆盖层长什么样（类名/cloaked/z 位置） |
| `t_qqsnip.ps1 -Mode flow` | **任务 1**：真 QQ 截图（Ctrl+Alt+X）全流程 —— 在 dock 上拖选区、把光标停在工具栏/浮窗/条上，逐点采样我们的 tm；`-Mode probe` 只开框选不拖 |
| `t_dodge.ps1` | **任务 2 验收**：关掉 `dodgeOnDoubleClick` 后双击空白处条不动、无 flip 日志；打开后跳到镜像位置并来回复原（ini 用 `WritePrivateProfileStringW` 写，不碰编码） |
| `t_snap.ps1` | **任务 3 验收**：把浮窗贴到底边 / 把条贴到顶边，逐个切换 `snap` 与继承关系，读日志里的 `snap: ... corners TL=.. TR=.. BL=.. BR=..`；会重启 dock 并把 ini 原样还原 |

⚠️ **面板自动化很不稳**：右键菜单的弹出位置随布局变，我这一轮连续点歪好几次都没打开设置面板。
要么先 `rcshot.ps1` 截图定位再点，要么直接让用户自己点。

## 5. 存档点与回退

- HEAD `cd576ed`（= `dock.cpp.bak56_dodge`，任务 2）；上一个：`ed05131` 任务 1 修完
  （= `dock.cpp.bak55_qqsnip`），再往前 `78aecf2`（= `dock.cpp.bak52_sharedrows` / `bak53_zwatch`）。
- 近期 tag：`pre-glasscfg-2026-11-21`、`h3c-2026-11-20`、`h3a-2026-11-20`、
  `known-good-2026-11-17-1755 / 1720 / 1630`（最后一个 `1630` 是任务栏那套"用户确认完全符合预期"的状态）。
- 回退单个文件：`git checkout <commit> -- dock.cpp`（**不要**用脚本覆盖源码）。
- 这 5 件事建议**一件一提交**，每件都先 `Copy-Item dock.cpp dock.cpp.bakNN_xxx` + `git commit`，
  再动下一件；任务 1 和任务 4 各自都值得分「先量 → 再改」两次提交。
