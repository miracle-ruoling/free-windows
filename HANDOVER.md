# Dock 项目交接文档（2026-11-11 22:00 重写）

> ⚠️ **未解决的遗留问题请先看 `HANDOVER_TODO_GLASS_LAG.md`**（2026-11-14 02:15 留）：
> 玻璃模式下拖动时背景位移、完全透明却零延迟；用户认为必有 bug，要求"只记录、下一个对话解决"。

> 读者：接手的新会话 AI + 用户本人。
> **先读第 1 节的语义模型和第 5 节的坑清单**：这个项目 90% 的弯路来自两件事——把"条"和"宫格"的职责搞混，以及**以为拿到了托盘数据，其实拿到的是注册表历史**。
> 旧版（十几轮追加出来的流水账）留在 `HANDOVER_old_2142.md`，需要查历史可以看，但不要照它的结论做事。

---

## 0.0 2026-11-15 02:50 交接（**新对话先读 `HANDOVER_NEXT.md`**）

本轮把玻璃背景"位移/抖动"彻底收尾，并新增了图标拖动重排。**入口文档是
`HANDOVER_NEXT.md`**（含必读清单、现场、下一步、改代码前必须知道的 8 件事），
本文只保留长期有效的内容（语义模型 / 关键实现 / 坑 / 用户习惯）。

一句话结论：`UpdateLayeredWindow` 的"矩形"和"像素"没落在同一次合成里 →
在 ULW **之前** `DwmFlush()`（`presentSync=2`）是正确性修复，不是优化，别去掉。

---

## 0.0 2026-11-14 02:15 交接（本轮修的一串 + 一个遗留问题）

**现场**：构建 `2026-11-14 01:57:46`，`pid 32980`，**由 explorer 启动**（`parent=explorer.exe`），
`x=827 y=180 920x119`，设置 `material=1 / glassOpacity=0 / tintStrength=0 / blurRadius=0 / refreshHz=75 / captureHz=15`。

**本轮修掉的**
1. 拖动位移的三个来源：玻璃缓存没把"偏移"算进 key；"先挪窗口、下一帧才重画"（改成 `UpdateLayeredWindow(pptDst)` 一次提交）；**拖动期间仍在抓图**（每次 20–24ms，已改成拖动中 0 次）。
2. 关掉的 UWP 窗口透进玻璃：`WindowUnderUs()` 现在跳过 cloaked 窗口。
3. 帧时钟（高精度可等待定时器）：30→30.7 / 60→59.6 / 120→116 / 180→165 tick/s，刷新率终于是真的。
4. 每 tick 瘦身（光标/窗口没变就不调 `GetWindowRect`/`GetMonitorInfo`/`WindowFromPoint`）、不透明像素跳过 `SetPixelPremul` 的 3 次整数除法。
5. `noGlass` 快速路径（`glassOpacity==0 && tintStrength==0` → 不抓图、不合成）、抓图节流（≥2× 上次耗时）、截屏兜底缓存。
6. QPC 每帧计时（日志 `frame: paint=… (glass … + icons …) present=… bake=…`）与 `cadence: … repaints / … captures`。

**实测**（条 920×119）：玻璃每帧 **2.4ms**（合成 1.3 + 图标 0.9 + 提交 0.2），完全透明 **1.9ms**，抓图 **20–24ms/次**。渲染远不是瓶颈。

**遗留（未修，用户要求留给下一个对话）**：玻璃模式下拖动仍有可见的背景位移，完全透明则完全看不到 —— 详见 **`HANDOVER_TODO_GLASS_LAG.md`**（含假设、验证方法、脚本清单）。

## 0.0 2026-11-14 01:50 交接（玻璃里出现"关掉的窗口"：cloaked 窗口被当成背景）

**现象**：条放在桌面空白处，条里却透出"任务栏设置/系统设置"的页面内容（只有窗口上半截），而那个设置窗口根本没开。

**根因**：`WindowUnderUs()` 选"条下面的窗口"时只看 `IsWindowVisible`。UWP / 系统应用关闭后窗口通常仍是 `WS_VISIBLE`，只是被 DWM **cloaked**（`DWMWA_CLOAKED`），对它们 `PrintWindow` 仍然会画出**最后一帧**。于是那个 1920x1080、盖满全屏的"已关闭"设置页被当成背景拍了进去。

**修法**：挑背景窗口时跳过 cloaked（复用现成的 `IsCloaked()`）。

**验证**：修前日志 `under=0000000000170B52 cls=Windows.UI.Core.CoreWindow pw=1`，修后 `under=0000000000000000 grab=1`（没有窗口 → 走截屏），条里透出的是真实壁纸（截图 `dev/fixed_bg.png`）。

## 0.0 2026-11-14 01:30 交接（拖动时最后那点位移：先挪窗口、后重画）

**现象**：缓存 key 修好后偏移变小但没归零，用户明确指出"只要不是 0 就能看出来"。

**根因**：拖动分支在 `WM_MOUSEMOVE` 里立刻 `SetWindowPos` 挪窗口，而**重画要等下一个帧 tick**。两次之间窗口带着**旧像素**移动 → 内容相对桌面偏移 = 这段时间走过的距离（120Hz、1000px/s 时约 8px）。

**修法**：拖动时 `WM_MOUSEMOVE` 只记录目标位置（`g_dragMovePending`），由 `RenderTick()` **在同一个 tick 里先 SetWindowPos、再重画** —— 位置和像素永远同步提交。抬手/丢 capture 时也会 flush 这个待处理位移。

**验证**：
- 真实拖动（`dev/dragtest.ps1`，mouse_event 按下-移动-抬起）：`526,408 → 646,408`，正好 +120，没有丢帧/卡住。
- 拖动过程中截图（`dev/dragshot.ps1`，按钮还按着时抓图），把条内背景和同一块屏幕的真实背景做互相关：**最佳位移 = 0**（修前会有几个像素）。

**取舍**：拖动时条的跟随精度现在等于帧率（120Hz = 8ms 一次），换来"位置与内容永远一致"。

## 0.0 2026-11-14 01:15 交接（移动时背景"位移"：玻璃缓存少了偏移做 key）

**现象**：不透明度/色调/模糊任一非 0 时，条一移动，条内背景就和真实背景错位（静止时正常）。完全透明（opacity=0 且 tint=0）没有这个问题。

**根因**：`g_glassCache` 的命中条件只有「尺寸相同」，**没有把"当前窗口在烘焙图里的偏移"算进去**。移动后重绘时直接 `memcpy` 上一帧的玻璃层 → 背景跟着窗口粘着走（正好是当初加 padding 想解决的问题）。

**修法**：把 `ox/oy`（窗口相对 `g_bakeOrigin` 的偏移）算到 `Paint()` 开头并作为缓存 key（`g_glassCacheOx/Oy`），偏移一变就重画玻璃。重新抓图/改配置/圆角动画/尺寸变化本来就会让缓存失效。

**验证**：同一条移动 40px，取**同一块屏幕区域**的纯玻璃带比较，平均像素差 **2.6/255**（修前是几十）；也就是背景钉在桌面上。

**关于 `captureHz`**（用户问"设 15 为什么看着还是实时"）：
- `refreshHz` = 每秒**重绘**多少帧（位移/淡出/动画的顺滑度，现在由帧时钟驱动）；
- `captureHz` = 每秒**重新抓多少次背景快照**（画面内容的新鲜度）。实测 `captureHz=15` 时 10 秒 **129 次抓图 ≈ 12.9/s**；
- 移动时只要超出 64px 边距就会重裁剪（不重新 PrintWindow，但会重新合成），所以动起来看着跟手；背景本身变化慢时也看不出 13fps。

## 0.0 2026-11-14 01:00 交接（120Hz 卡死：抓图把线程吃满了）

**现象**：用户把刷新率调到 120Hz 后条"卡死"——不能拖、不能右键、宫格打不开，但透明度还跟光标变，其它程序正常，CPU/GPU 看着不高。

**根因**（两个叠加）：
1. `captureHz=65` —— 每秒 65 次 `PrintWindow`，每次实测 15–30ms，等于每秒要 1–2 秒的 CPU：UI 线程被吃满，输入全靠挤。
2. 条在淡出时会被设成 `WS_EX_TRANSPARENT`（点击穿透），一旦 alpha 停在 0，用户看到的"条"其实点不动 —— 所有点击都落到下面的窗口上了。

**修法**：
- 抓图节流：`capMs = max(1000/captureHz, g_lastCaptureMs * 2)`，抓图最多占循环时间的一半；`g_lastCaptureMs` 在 `CaptureBackdrop()` 末尾记录。
- **"无玻璃"快速路径**：`glassOpacity == 0 && tintStrength == 0` 时不抓图、不做逐像素合成（以前这一档照样全速抓图 + 全速合成，因为 `material` 还是 1）。
- 点击穿透守卫：`RenderTick()` 每帧检查真实 `GWL_EXSTYLE`，`g_alpha > 0` 却还带 `WS_EX_TRANSPARENT` 就强制清掉并记日志（`alpha: cleared a stuck WS_EX_TRANSPARENT`）。

**实测**：120Hz 真到 1156 ticks/10s；无玻璃 @120Hz 只吃 **0.5% 单核**；玻璃 @120Hz 且 `captureHz=65` 时 31.8% 单核、条仍可点击（tick 降到 ~80/s，被绘制成本限制）。

**启动方式**：dock 现在由 explorer 启动（日志 `parent=explorer.exe`）——用户实测"我自己启动就正常"，从 agent shell 启动的实例会让被启动的程序权限不对。

## 0.0 2026-11-14 00:45 交接（高精度帧时钟：刷新率终于是真的）

**运行状态**：`dock.exe` 在跑；`dock.ini` 恢复成 `material=1 / bgAlpha=60 / refreshHz=30`。

- **问题**：`WM_TIMER` 被系统 15.6ms 节拍量化 —— 实测 refreshHz 30→21 tick/s、32→31.7、64→62.7、128→63.0（到顶）。`timeBeginPeriod(1)` 在这个进程里没生效。所以"调到 180 还是像 30"不是显卡也不是渲染，是定时器。
- **做法**：`FrameClockThread()`（后台线程 + `CreateWaitableTimerExW(CREATE_WAITABLE_TIMER_HIGH_RESOLUTION)`）按 `g_tickPeriod100ns` 周期 `PostMessage(hwnd, WM_APP+1)`；`WM_APP+1` → `RenderTick()`（原来 `WM_TIMER wp==1` 的整段逻辑抽成了这个函数）。只保留一个待处理 tick（`g_tickPosted`），避免消息堆积。
- `WM_TIMER id=1` 保留兜底；帧时钟起来后降级成 1s 心跳。`ArmRepaintTimer()` 负责把 `refreshHz` 换算成周期。
- **实测 tick**：30→30.7/s、60→59.6/s、120→116/s、180→168/s（修前 21/39/63/63）。
- **实测成本（拖动中，16 核）**：玻璃 @120Hz ≈ 46 repaints/s、17.9% 单核；全透明 @180Hz ≈ 2.7% 单核；空闲 @180Hz 1.4% 单核。dock 进程自身 GPU 0.0%。

## 0.0 2026-11-12 20:50 交接（图标动画重做 + 一个"不是 dock 的 bug"）

**运行状态**：`dock.exe` 在跑，构建 20:45；`refreshHz=30 / captureHz=10 / hoverMs=160`（用户自己调的值）。

1. **图标放大/缩小重做**：`hoverHz`（步进频率）换成 `hoverMs`（**动画时长**，40..600ms），缓动改成 `smoothstep(t/duration)`；动画期间由 **timer 5（8ms）** 驱动，所以 160ms 的缩放能拿到 10~15 帧（实测日志 `hover zoom: 11 frames in 250 ms (duration 160 ms)`），而不是被 30ms 主定时器切成 3~5 帧。日志 `hover zoom: N frames in M ms`。
2. **玻璃体缓存**（`g_glassCache`）：图标动画时只有图标在变，玻璃本体没变 → 直接 `memcpy` 上一帧的玻璃层，只重画图标。悬停帧从 ~10ms 降到 ~3ms。烘焙/改设置/圆角动画/尺寸变化都会让它失效。
3. **1ms 定时器改成常开**：之前只在 >50Hz 时开，结果 `refreshHz=30` 被系统 15.6ms 节拍取整成 47ms（实测 21 tick/s 而不是 30）。
4. **"点 VS Code 打不开"不是 dock 的问题**（已验证）：
   - 日志有 `launch pin 6: CreateProcess ok pid=... target=D:\vscode\Microsoft VS Code\Code.exe`；
   - 但手动 `Start-Process` 同一个 exe 也立刻退出（exit 0），不留窗口；
   - 原因：`D:\vscode\Microsoft VS Code` 只剩 `Code.exe / bin / unins*`，**`resources\app\out\main.js` 不存在**（安装被卸载/更新搞坏了），开始菜单的快捷方式也指向同一个坏路径 → 任何启动器都打不开，需要重装 VS Code。
   - 新增看守日志：`launch: pid N exited X ms after starting (code N) - the app itself failed to start`，以后再遇到这种能一眼看出来。

## 0.0 2026-11-12 17:25 交接（拖动时背景"偏移"的根因修掉）

**运行状态**：`dock.exe` 在跑，构建 17:19；`dock.ini`：`refreshHz=60 / captureHz=5 / hoverHz=113 / blurRadius=0`（后两个是用户自己调的）。

- **根因**：烘焙图是**贴在窗口上**的。两次烘焙之间窗口移动了多少像素，玻璃里的背景就相对真实桌面偏多少像素 —— 跟刷新率无关，只跟"上次烘焙以来移动的距离"有关。所以调到 180Hz 也没用（拍数上去了，但每拍仍是一次新的烘焙/贴图）。
- **修法**：烘焙图多抓 64px 边距（`g_bakeMargin`），`Paint()` 按当前窗口位置算偏移去这张图里取样；移出边距才重新烘焙。于是 ±64px 内移动完全不重新烘焙，背景钉在桌面上。
- **验证**：噪声底 0.0；移动 40px 后 `A(x)` vs `B(x-40)` = **0.0**（锚定成功），vs `B(x)` = 74.4（旧行为）。
- **仍然存在的上限**：每帧 `Paint()` 要跑 16 万像素（SDF + lift + 混合），约 8-10ms，所以 60Hz 设置实测 ~40 tick/s、拖动 ~30 repaints/s。想再快只有两条路：① 把 `Paint()` 的热循环优化（内部像素是仿射变换，可以砍掉 sqrt/分支）；② 上 DWM 合成器的实时模糊（`SyncBackground()`，非公开 API），那样背景是"合成器每帧重算"，根本不存在偏移。
- `timeBeginPeriod(1)` 的阈值从 >62Hz 改成 >50Hz（60Hz 也会开）。

## 0.0 2026-11-12 17:10 交接（三个节奏做成设置项）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 17:01；设置面板多了三行：`背景刷新帧率 / 背景截取频率 / 图标动画帧率`。

- `refreshHz`（0..180）：主定时器周期，驱动淡出、吸附角动画、悬停动画、按需重绘；>62Hz 自动 `timeBeginPeriod(1)`（`build.ps1` 为此加了 `winmm.lib`）。
- `captureHz`（0..refreshHz）：背景快照重抓频率；**拖动/缩放期间跳过**，拖动只用上一张快照重新裁剪 → 拖动不再"3fps 幻灯片"。
- `hoverHz`（1..180）：图标放大/缩小动画步进频率，缓动改成按时间算（`1-exp(-dt/35)`），所以改频率只改顺滑度、不改动画时长。
- 面板行距从 66 改成 58，12 行能放进 1080p（面板高 868）。
- 日志：`cadence: refresh/capture/hover`（启动与改设置时）、`cadence: N ticks / M repaints in X ms`（每 10s）。
- 实测：空闲 0 repaints（看不见时不画）；拖动 ~29-30 repaints/s（每拍全流程 ~30ms）；60Hz 设置实际 ~40 tick/s，144Hz 设置 ~63 tick/s。用户当前 ini：`refreshHz=60 / captureHz=60 / hoverHz=113`（他自己拖的，`captureHz=60` 会很吃 CPU，已提醒）。

## 0.0 2026-11-12 16:40 交接（拖动刷新提速）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 16:34:45（PID 43876）；条在用户放的位置，玻璃参数用用户自己调的值（`glassOpacity=140 / tintStrength=146 / blurRadius=8`）。

- 拖动/缩放时烘焙间隔 **300ms → 25ms**（约 33fps，跟着 30ms 定时器走）；空闲保持 300ms。
- 新增**全窗口抓图缓存**（`g_underCache`）：`PrintWindow` 整个下窗口是烘焙最贵的一步，拖动时下窗口不变、只有裁剪偏移在变 → 命中缓存就只做裁剪。空闲 TTL 400ms、拖动 1500ms。日志加 `crop=`（1=命中）和 `took=`。
- 用户之前因为"闪烁"把节奏调慢的；这次提速后要他本人看是否复现闪烁（截图看不出闪烁）。如果复现，下一步把拖动路径单独降频/改成只挪窗口不重烘焙。

## 0.0 2026-11-12 16:30 交接（吸附透明度 + 红蓝通道两个 bug 修掉）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 16:18:19；条在 `(460,-17)`、尺寸 1335x117（用户当前的调试位），玻璃参数用用户自己调的值 `glassOpacity=181 / tintStrength=181 / blurRadius=28`。

- **修 A：吸附时上半条 50% 透明**（用户报的"吸顶能看见标题栏、往下挪一点就没事"）。逐角圆角的 SDF 在 `rr = 0` 时把整片区域算成 `cov = 0.5`，详见 §3.7-A。改用标准圆角矩形 SDF，`Paint()`/`FillRound4()`/`FillRound()` 三处同步。
- **修 B：红蓝通道写反**（用户报的"蓝色卡通人物变黄"）。`Paint()` 把蓝通道当红通道混色再写进红字节，灰色 tint 下看不出来，饱和色上就翻车，详见 §3.7-B。
- **修 C：`hasSize` 生效**，重启不再丢尺寸。
- 上一轮的"不透明合成"（`(1-a)` 用模糊图填）已经在跑：用户确认"现在不透过文字了，只有鼠标离远半透明时才会透过，符合预期"。

## 0.0 2026-11-12 13:20 交接（玻璃诊断 + 两个小修，参数未动）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 13:13（含下面的合成改动 + hasSize 修复）。玻璃参数保持用户原值 `glassOpacity=235 / tintStrength=143`，条在 `(650,0)`、尺寸 906x111。

1. **诊断"不像模糊"**：模糊没问题（bake 前后对比图糊成一片），透出来的是**实时桌面**——主要是淡出（`fadeStart=0/fadeEnd=150`，光标离开 80px 就只有 ~47% 不透明）以及玻璃体 44% 的背景亮度透射。证据、旋钮含义、为什么调 blurRadius 没用，全写在 **§3.6**。
2. **代码改动（小而独立）**
   - `Paint()`：`(1-a)` 那一层从"让 DWM 透出实时桌面"改成"用同一张模糊图填"（`gr = gr*a + br*(1-a)`），像素不透明度改为 `cov*255`。→ 全不透明时不再有清晰的鬼影；视觉几乎不变。
   - `main()`：`hasSize` 以前读了不用，**每次重启条都会变回默认宽度**（用户每次都得重新拖）；现在按 `w/h` 恢复。
3. **等用户拍板**（没动手）：要不要把 `SyncBackground()`（blur-behind）接上做真·磨砂；淡出区间要不要收窄；`tintStrength` 是否上调。

## 0.0 2026-11-12 12:50 交接（宫格定位 + 吸附）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 12:46（部署在 `%LOCALAPPDATA%\Programs\Dock`）。条在 `(139,63)`（用户自己拖的位置，`dock.ini` 与之一致）。

**本次交付**
1. **宫格贴着 `^` 弹，不再"竖向在条上方 / 横向在条中部"**（`GridPlacement()`，见 §3.2 与 §8.4）
   - 横向条：宫格**右边缘对齐 `^` 的右边缘**（下拉菜单的手感），优先弹在条**下方**；
   - 竖向条：宫格**下边缘对齐 `^` 的下边缘**（从按钮往上长），优先弹在条**右边**；
   - 短边方向"哪边有位置去哪边"，两边都有就按上面的默认；**整块留在工作区是硬要求**，与条不重叠只是尽力而为（条比空位还大时允许重叠）。
   - 实测：横向条 `(1208,182)`（条 139,63-1608,174，`^` 右边 1494）、条贴底时自动弹到上方 `(1208,651)`、竖向条 `(258,554)`（条右边 250，`^` 下边 850 → 宫格下边 850）、条比屏幕还大时 `(1295,784)` 仍全在屏内（此时允许压条）。四种情形见 §3.2。
2. **吸附（贴边去圆角）**（见 §8.4 待办 E）：逐角圆角 + 120ms 缓动；拖到边缘/越界即刻生效，拖回来恢复；吸附状态下双击照常闪避，落地后按新位置重新判定。
   - 实测：顶边 `TL=0 TR=0`、底边 `BL=0 BR=0`、离边全 1；像素对照见 §8.4。
3. **一个未解的崩溃**：12:42:12 `dock.exe` 崩过一次（`0xc0000005`，偏移 `0x11fe0`），当时条被测试脚本改成 111x800；之后用同样步骤复现 3 次都没再出现，记在 §10-8，留意是否复发。

## 0.0 2026-11-12 12:15 交接（快速闪避已落地）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 12:08:29（部署在 `%LOCALAPPDATA%\Programs\Dock`，源码与安装目录一致）。Windhawk 两个 mod 仍启用，桥表 15 条。

**本次只做了一件事：待办 D「快速闪避」**（规格见 §8.4，实现与证据也补在那一节）
- 双击**条的空白处**（内边距 / 图标之间的缝，**图标和 `^` 不算**）→ 条以 250ms 的 smoothstep 动画移到**沿工作区中心线对称的另一边**：宽>高上下镜像、高>宽左右镜像；**只 clamp 移动的那条轴**，所以横向条的 x 不变（本机条比屏幕宽、本来就越界，不能被顺手拖走）。
- 动画期间**不重绘**（分层窗口的 surface 跟着窗口走，只 `SetWindowPos`），落地后 `g_bakeDirty = true` 重抓一次玻璃；`UpdateAlpha()` 全程照旧跑，淡入淡出和原来一样。
- 落地写回 `dock.ini`（`SavePosition()`）。
- **实测**：`(451,290) → (451,679)`、`(451,679) → (451,290)`，x 不变，每次 21~23 帧 / 281~297ms，日志 `flip: landed ... after 281 ms in 23 frame(s)`。
- 双击识别没有加 `CS_DBLCLKS`（怕碰坏现有拖拽），改成 `WM_LBUTTONUP` 里判"同一空白处、`GetDoubleClickTime()` 内、位移 < 4px"；拖拽开始会清掉这个计数。点图标/`^` 会把计数清掉，因此**双击图标不会闪避**。
- 待办 E「吸附（贴边去圆角）」**未开工**，规格还在 §8.4。

**顺手留下的工具**：`dev/t_flip.ps1`（PostMessage 双击条的左内边距，打印落点 + 日志；带重试，因为真人正在动鼠标时注入的 DOWN 会被"陈旧按下"判据丢掉）。

## 0.0 2026-11-12 11:45 交接（本次会话收尾）

**运行状态**：`dock.exe` 在跑，构建 2026-11-12 11:14（部署在 `%LOCALAPPDATA%\Programs\Dock`，源码与安装目录一致）。Windhawk 两个 mod 都已启用（64 位 + **32 位**），桥表 15 条。

**本次会话交付**
1. **右键不再挪光标**：删除全部 `SetCursorPos`；菜单超屏改为平移**菜单窗口**（`FitMenuToWorkArea`），失败只记日志。
2. **三态交互状态机**（条 / 条+宫格 / 条+宫格+菜单）——完整语义见 `STATE_MACHINE.md`，实现见 §8.1。核心：低级鼠标钩子（`WH_MOUSE_LL`）判"按下落在哪"+ `FocusWatchTick` 判失焦；宫格常驻 topmost，改由 `RaiseMenuAbovePanel()` 把菜单提上去。
3. **宫格左键 = 纯转发** `WM_LBUTTONDOWN/UP` 给图标 owner（`ForwardTrayClick()`），修好"点 WorkBuddy 没反应、点 QQ 弹登录页"。
4. **条上图标右键菜单**（`ShowAppMenuForSlot()`）：`<App 名>` / App 的 tasks（解析 CustomDestinations）/ `关闭窗口`；去重、名字表、缩略图不再遮菜单。
5. **杂项修复**：僵尸图标（`File Explorer.lnk` 无 target → `LnkTargetFallback()`）、宫格被前台窗口盖住（不再降级 topmost）、托盘条目 30s 宽限期、"重新扫描托盘"菜单项、死进程条目过滤。

**已知未完成 / 待办**（按用户 2026-11-12 11:45 指定，详见 §8.4）
- **快速闪避**（✅ 2026-11-12 12:08 完成，见上面 12:15 交接与 §8.4）：双击条 → 沿屏幕中心线对称跳到另一边（宽>高上下、高>宽左右），过程里继续按光标距离调透明度。
- **吸附**：较长边贴近/越过屏幕边界时去掉该边圆角（不限制拖动），离开屏幕后恢复；尽量做得灵动；吸附状态下双击同样触发闪避。
- 可选：待办 C 的"最近文件"（AUMID 哈希没解出）、资源管理器"常用文件夹"、固定/取消固定（无 API）。
- 外部限制（非本代码问题）：NVIDIA 托盘图标整段消失且不理 `TaskbarCreated`（§5 坑 41）；联想电脑管家不被 Windhawk 注入（用户决定不管）；Wallpaper Engine 已在宫格里。

**接手须知**
- 先读 `STATE_MACHINE.md`（可见性规则）+ 本文件 §5（坑）、§8（状态机与待办）。
- 编译/部署：`build.ps1`（**先杀 dock 再编译**，否则 exe 被占用）；启动 `dev/run.ps1`。
- 截图不可靠时（显示器休眠）改用日志 + `wins2.ps1` 查窗口状态；条上有滚动时用 `t_slotpick.ps1` 按 `hover -> N` 闭环定位槽位。

## 0. 一句话现状

一个 C++ Windows 桌面图标条（`dock.exe`）+ 两个 Windhawk mod（托盘桥 / 任务栏隐藏）。

- **能用的**：玻璃模糊、`^` 宫格（**贴着 `^` 弹、不压条、不出屏**）、悬停放大、滚轮翻页、开机自启、任务栏只在按 Win 时出现、完整交互状态机（`STATE_MACHINE.md`）、右键不动光标 + 菜单自动移进屏幕、托盘右键菜单转发、**宫格左键纯转发**、**条上图标右键菜单**（App 名 / App tasks / 关闭窗口）、**「重新扫描托盘」**自愈入口、贴边/越界不限制拖动、**双击条空白处快速闪避**、**贴边去圆角（逐角 120ms 缓动）**。
- **不稳的 / 外部限制**：托盘数据完整依赖"mod 是否注入那个进程"（32 位 App 需要 x86 mod，已装）；NVIDIA 的图标会整段消失且不理 `TaskbarCreated`（坑 41）；联想电脑管家不被 Windhawk 注入（用户决定不管）；提权 App（Legion Zone）的菜单关不掉（坑 18）。
- **当前机器状态**：dock build 2026-11-12 11:14 在跑；桥表 15 条；Windhawk 两个 mod（64 位 + 32 位）均已启用。

---

## 1. 语义模型（先读这个！）

| 我们的东西 | 对标 Windows 的 | 内容 | 不该出现的 |
|---|---|---|---|
| **图标条**（pill） | **任务栏** | 固定项（注册表 `Taskband\Favorites`）+ 有任务栏按钮的窗口；超宽靠滚轮翻页 | 只在托盘里、没有窗口的后台程序 |
| **宫格**（点 `^`） | **系统原生托盘** | **只**放原生托盘图标（全集，允许和条重叠） | 窗口项 |

判断标准永远是"任务栏有没有它 / 原生托盘有没有它"，而不是"两者会不会重复"。

---

## 2. 路径与构建

| 项目 | 路径 |
|---|---|
| 源码 | `C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp`（单文件 ~5000 行） |
| 构建 | 同目录 `build.ps1`（cl.exe 直调 + 部署到安装目录 + 哈希校验） |
| 安装 / 运行 | `%LOCALAPPDATA%\Programs\Dock\dock.exe`（配置 `dock.ini`，日志 `dock.log`） |
| 日志 | **跨重启追加**，超过 4MB 轮转为 `dock.old.log` |
| 开机自启 | `%APPDATA%\...\Startup\Dock.lnk`（右键菜单可开关） |
| mod 源码 | `common_workspace\windhawk\tray-icons-bridge.wh.cpp`、`taskbar-hidden-until-win.wh.cpp`（另有 `tray-icons-bridge-x86.wh.cpp`） |
| mod 安装位 | `C:\ProgramData\Windhawk\ModsSource\local@<id>.wh.cpp`（Windhawk 从这里编译） |
| mod 产物 | `C:\ProgramData\Windhawk\Engine\Mods\64\local@<id>_<ver>_<hash>.dll` |
| 工具链 | MSVC `...\VC\Tools\MSVC\14.51.36231`；SDK `D:\Windows Kits\10`（10.0.26100.0） |

**构建 / 部署顺序不能错**：
```powershell
cd C:\Users\20979\RP_Projects\common_workspace\dock
Get-Process dock -ErrorAction SilentlyContinue | Stop-Process -Force
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
Start-Process "$env:LOCALAPPDATA\Programs\Dock\dock.exe"
```

**mod 流程**：改 `windhawk\*.wh.cpp` → 语法检查 `powershell -File windhawk\stub\check.ps1 -Src ..\<file>.wh.cpp`（32 位版本用 `check86.ps1`）→ 复制到 `ModsSource\local@<id>.wh.cpp` → **用户在 Windhawk 界面点"编译"**（本机没有 windhawk-cli，无法自动化）。

---

## 3. 关键实现

### 3.1 图标条（对标任务栏）
- **固定项来源**：`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\Favorites`（REG_BINARY）。**不能**直接用 `User Pinned\TaskBar\*.lnk` 文件夹（里面留着用户早已取消固定的残留，例如 `网易UU远程.lnk`）。详见坑 8。
- **窗口项**：`IsCandidate()` 用 shell 规则 `visible && !cloaked && (WS_EX_APPWINDOW || (!WS_EX_TOOLWINDOW && 无 owner))`；无标题窗口用 `WindowLabel()` 取 exe 名。
- 布局 `ComputeButtons()`：`icon = min(H-2*pad, maxIcon)`，`cap = (W-2*pad+gap)/cell`，`^` 永远占最后一格，`show = cap-1`；滚轮改 `g_scroll`。

### 3.2 宫格（对标原生托盘）
- 数据来自 Windhawk 托盘桥（3.3），**全集**，不与条去重。
- 布局 `GridLayout()`：`cols = clamp(ceil(sqrt(n)), 3, 8)`，格子 60×60、间距 6、内边距 14、底部 10 的 `^` 条。
- 每格 `item = -2 - i` → `g_tray[i]`。
- **格子列数会随图标数量变**（3 列 / 4 列），测试脚本按窗口宽度算，别写死。
- **位置** `GridPlacement()`（2026-11-12 12:46）：锚在 `^` 按钮上，不是锚在条的中点——
  - 横向条：宫格 `right = ^.right`，优先在条下方 8px；竖向条：宫格 `bottom = ^.bottom`，优先在条右边 8px（从按钮往外长，视线不用跑远）。
  - 短边方向先看"这一边放不放得下"，放不下换另一边，两边都放不下时选空间大的一边。
  - **硬要求：整块在工作区内**（最后统一 clamp）；不与条重叠是尽力而为——条比空位还大时必然重叠，此时以屏幕内为准。
  - 日志 `grid: place strip=... chevron=... -> x,y (WxH) work=...` 把三个矩形都印出来，排查位置问题先看这条。
  - 实测四种：常规（条 139,63）→ `1208,182`（条下 8px、右边缘 1494 = `^` 右边）；条贴底 → 自动弹到上方 `1208,651`；竖向条（111x800）→ `258,554`（条右 250、下边缘 850 = `^` 下边）；**条比屏幕还大**（1900x1000）→ `1295,784`，**仍在工作区内**但必然压住条（用户规定的优先级：先屏幕、后不重叠）。

### 3.3 托盘桥（Windhawk mod `tray-icons-bridge`）
```
Local\DockTrayBridge_v1    共享内存（dock 与 mod 双方都必须可读写）
  magic 'TRAY' / version / count / capacity / updatedMs
  entries[128]{ hwnd(u64), uid, cbMsg, isGuid, pid, GUID guid, tip[128], exe[260] }
Local\DockTrayBridgeLock_v1  命名互斥体（mod 写时串行）
```
- `Shell_NotifyIcon` **在 App 自己的进程里执行**，所以 mod 必须 `@include *` 注入每个进程，各写各的。
- **单架构**：`@architecture` 只接受一个值（`x86-64`）；32 位 App 需要另建 `@id tray-icons-bridge-x86` + `@architecture x86` 的副本（同源码，已备好，可选）。
- **DACL**：mapping 与 mutex 都用 NULL DACL 创建（坑 2）。dock 启动时**自己也会创建并一直持有句柄**，这样 Windhawk 重载 mod 不会把表清空。
- `cbMsg` 可能被 App 用 `NIM_MODIFY(0)` 清零 → dock 侧 `g_trayCbCache`（exe → 最后一次可用 `{hwnd,uid,msg}`）兜底。
- 表为空/变短时 dock 广播 `TaskbarCreated` 让 App 重注册（**只在打开宫格时**，限流 5s），400ms 后重读，但**绝不在面板打开期间重建**（坑 12）。
- mod 卸载时把表存到 `%LOCALAPPDATA%\DockTrayBridge.bin`，重建时按"进程活着 + 窗口有效"过滤后恢复。

### 3.4 托盘右键菜单转发（最容易出问题的部分）
```cpp
SetWindowPos(g_gridWnd, HWND_NOTOPMOST, ...);      // 宫格降级，菜单才能盖住它
AllowSetForegroundWindow(ASFW_ANY);                // 坑 14
if (!GetForegroundWindow()) SetForegroundWindow(App 的可见窗口);   // fg 为空时先激活
PostMessage(owner, cbMsg, uid, WM_RBUTTONDOWN);
// 70ms 后在定时器里补发 UP（零时长点击会被忽略，坑 15）
PostMessage(owner, cbMsg, uid, WM_RBUTTONUP);
```
- 菜单识别（`MenuWindows()`）：① 该 pid **新出现**的可见窗口；② 该 pid **盖住光标、无标题栏的 popup**（WPF/Qt 复用同一个 HWND，永远不"新增"）。命中后记住 `g_menuHwnd`。
- 300ms 没见到菜单 → **自动重投一次**（日志 `forwarding the click once more`）。
- 关闭时机（2026-11-12 起，见 §8）：只有三种——① 用户点击落在 `条∪宫格∪菜单` 之外；② 前台换成第三方窗口（失焦）；③ 用户右键另一个图标（换菜单）。App 自己收菜单时我们**保持面板**（`tray: app menu is gone - panel stays`）。关闭动作本身仍是 `WM_CANCELMODE` + `Esc` + `WM_ACTIVATE(WA_INACTIVE)` + `WM_KILLFOCUS`（Electron/Qt/WPF 弹窗都是非激活窗口，靠这些才关）。
- **不要**给菜单再投一次托盘消息来"关"它：Legion Zone 那种实现"再点一下图标就重新摊开"。
- **光标一律不动**（2026-11-11 22:05 起）：右键时**没有** `SetCursorPos`，菜单以"用户真实按下的那一点"为基准弹出（和原生托盘一致）。
- 长菜单（QQ 183x620）会弹出屏幕 → `FitMenuToWorkArea()` 在菜单出现后的第一个 30ms 定时器里用 `SetWindowPos(SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOSENDCHANGING)` **平移菜单窗口本身**，`ok=1` 时把 y=-255 的 QQ 菜单挪到 y=8；移动失败（提权 App）只记日志，**不**回退去挪光标。实测 17ms 内完成，移动后 App 的命中测试仍正常（悬停高亮、点条目都对）。

### 3.5 玻璃 / 图标 / 其它
- `CaptureBackdrop()`：先 `PrintWindow(PW_RENDERFULLCONTENT)` 抓底下窗口；抓不到或黑帧 → `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` + `BitBlt` 屏幕（不隐藏窗口、无闪烁）。每 300ms 重抓（`WM_TIMER id=1`）。
- **拖动时的节奏**（2026-11-12 16:40）：`g_dragging || g_resizeEdge` 时改成 **25ms 一次**（跟着 30ms 定时器走，约 33fps），空闲仍是 300ms。以前是全程 300ms，拖动时玻璃像"3fps 幻灯片"。
- **烘焙图带 64px 边距（2026-11-12 17:20，修"拖动时背景跟着条跑"）**：`CaptureBackdrop()` 现在抓 `条矩形 ± 64px`（`g_bakeMargin`），`Paint()` 按 `wr.left/top - g_bakeOrigin` 的偏移去这张图里取样。于是条在 ±64px 内移动时**不需要重新烘焙**，只是换个偏移读同一张图 —— 背景牢牢钉在桌面上，而不是"贴在窗口上跟着滑"。这是那类"往右拖、玻璃里的背景比真实位置偏右"现象的根因：**图像是粘在窗口上的，两次烘焙之间窗口移动了多少，背景就偏多少**（跟帧率无关，只跟"上次烘焙以来移动的距离"有关）。
  - 验证（同一位置两次截图 vs 移动 40px 后截图，只取图标以下的纯玻璃带）：噪声底 `0.0`，`A(x)` 对 `B(x-40)` 的差 **0.0**，对 `B(x)`（旧的"粘住"行为）是 **74.4**。
  - 定时器里 `moved`（任何位置变化）只触发**重绘**，`!covered`（移出边距）/ `captureDue` / `g_bakeDirty` 才触发**重新烘焙** —— 所以拖动时每帧只是"读图+画"，不再 PrintWindow。
- **全窗口抓图缓存 `g_underCache`**：`PrintWindow` 整个下窗口（本机 1938x1098）是烘焙里最贵的一步；拖着条走的时候下窗口根本没变，变的只是裁剪偏移。现在把整张抓图缓存起来（空闲 400ms、拖动时 1500ms，按 hwnd+窗口矩形 校验），命中时只做裁剪 → 拖动时每帧都能重烘焙。日志 `crop=1` 表示命中，`took=` 是这次烘焙耗时（注意 `GetTickCount` 只有 15.6ms 粒度，只能看量级）。
- 降采样跟半径走：`blurRadius=0 → 1:1`；`1..11 → 1/2`；`>=12 → 1/4`；`BoxBlur` 两次 + `r/3` 细节；双线性放大回全尺寸。
- 合成：`glass = blurred*(1-t) + tint*t`，`out.alpha = glassOpacity`；16% 往中灰 lift + 2.5px 柔光边（**不要** 1px 硬白边）。
- 图标：`HiResIconForPath()`（jumbo 256 帧）→ `RasterIconPx()` → `NormalizeIconSquare()`；按 `icon*1.45` 缓存，绘制时 `BlendScaled()`。
- 悬停放大 1.34×、邻居让位、整行重算居中；缩放热区 24×24 角 + 贴合圆角的 10px 边带。
- 淡入淡出**只看光标到（条/宫格矩形）的距离**（`DistanceToWindow()`），没有 10 秒之类的定时器。
- 开机自启 `SetAutoStart()`；DWM 缩略图 `ThumbShow()`（独立 topmost 小窗）；设置面板自绘。

### 3.6 为什么"不像模糊"（2026-11-12 13:20 诊断结论）

**模糊本身是好的**：`dumpBake=1` 抓出来的 `dock_bake_pre.bmp` / `dock_bake_post.bmp` 一比就看得出——原图里的聊天文字，blur 之后整张糊成一片渐变（日志 `detail 7 -> 0`）。所以"背后有字能看清"不是模糊半径的问题。

真正透出来的是**两层实时桌面**：

1. **全局淡出**（`Present()` 的 `bf.SourceConstantAlpha = g_alpha`）。`fadeStart=0 / fadeEnd=150` 时，光标离条 80px 条就只有 **~47% 不透明**，透出来的是 DWM 合成的**实时桌面（完全没模糊）**。实测对比（同一位置、只改光标）：
   - 光标在条上（alpha 255）：背后文字完全看不见；
   - 光标在条下 80px（alpha≈119）：背后那句"个后台任务运行中"**直接读得出来**。
   → 这是"能清晰看到字"的主因，也是淡出这个设计自带的：只要 alpha<255，透过去的就是没糊过的桌面。
2. **玻璃体的透射**。`tintStrength=143` 时，模糊背景的亮度有 **~44%** 进来（`blurred*(1-t) + tint*t`）；吸附到上边界时条正好压在窗口的深色标题栏上，于是顶部出现一条深灰带；往下挪 30px 就不在标题栏上了——所以"吸附才明显"。跟去圆角无关（同样位置不吸附也一样）。
3. 旧的 `(1-a)`（即 `glassOpacity` 那 8%）也是**实时**桌面。2026-11-12 13:13 改成用同一张模糊图填 `(1-a)` → 全不透明时不再有"清晰鬼影"，视觉几乎不变（a=0.92 时那层只占 8%）。

**旋钮的正确含义**（不然会像这次一样调一晚上调错）：
- `tintStrength` = 背后**能看见多少**（0 = 完全透出模糊背景，255 = 只有 tint 色）。
- `glassOpacity` = 玻璃体 vs "清透背景"的比例（`(1-a)` 那一层，现在也是模糊的）。
- `fadeStart/fadeEnd` = 光标离多远开始变透明。**半透明时透出来的是实时桌面**，这是"看得清字"的根源。
- `blurRadius` = 只作用于烘焙那张图，对上面两层实时透视毫无影响（所以调它没用）。

**要真·磨砂**，只有一条路：在条下面放一个 `SetWindowCompositionAttribute` 的 blur-behind 窗口（代码里 `SyncBackground()` 是现成的，但**没有任何调用点**，`g_bgWnd` 从未创建）。代价：非公开 API、要跟着条的位置/尺寸/透明度同步、z-order 和宫格/菜单可能打架，需要实测。

### 3.7 两个真 bug（2026-11-12 16:20 修）

**A. 吸附时上半条整块 50% 透明** —— "吸在顶边标题栏透得很重、往下挪一点就正常"的直接原因，跟模糊/淡出都无关。
- 逐角圆角那次把 SDF 写成了 `d = sqrt(max(qx,0)² + max(qy,0)²) - rr`。这个式子只在 `rr > 0` 时成立：`rr` 同时充当"内部距离"，内部像素 `d ≈ -rr`，覆盖率才会算成 1。
- 吸附后该边两角 `rr = 0`（直角）→ **那一半窗口的所有像素** `d = 0` → `cov = 0.5` → 整块 50% 透明，透出的是没模糊的实时桌面；正好压在标题栏上，就是一条深灰带。不吸附时 `rr = 42`，所以完全看不出来。
- 修法：标准圆角矩形 SDF `d = length(max(q,0)) + min(max(qx,qy),0) - r`（`Paint()` / `FillRound4()` / `FillRound()` 三处一起改）。`rr = 0` 时内部 `d = -min(hh,hw)`，覆盖率仍是 1。
- 验证：同一条（1335x117、y=-17）修前上半 50% 透明，修后整条均匀不透明。

**B. 红蓝通道写反** —— "原本蓝色的卡通人物变黄"的原因。
- `Paint()` 里 `v & 0xFF` 是**蓝**，却当成"红"去混 tint（`gr = 蓝*(1-t) + tint红*t`）再写回红字节；亮度权重也按红蓝反着算。
- 灰色 tint（`#A6101010` 或 lightMode 的纯白）下看不出来；一旦盖在饱和蓝上：蓝(0,0,255) → 输出 (255,181,181) 粉/肉色。
- 修法：拆成 `bl/gn/rd` 三个变量，各混各的 tint 通道，亮度用真正的权重。

**C. `hasSize` 从来没生效** —— `main()` 读了 `g_cfg.w/h` 却没用，每次重启条都回到"默认宽度"，用户每次都白拖一次。已改为按 ini 恢复。


---

## 4. 配置（`dock.ini`，用户实际值在安装目录）

```ini
material=1            ; 0=纯色 1=玻璃
lightMode=1           ; 1=浅色（tint 强制白）
glassOpacity=235      ; 图层 alpha
tintStrength=119      ; 0=纯磨砂
blurRadius=16         ; 全分辨率像素；0=像素级清晰
refreshHz=60          ; 面板重绘节奏（0..180）
captureHz=5           ; 背景快照重抓频率（0..refreshHz，0=冻结）
hoverMs=160           ; 图标放大/缩小动画的时长（ms，40..600）；步数由刷新率决定
radius=42
fadeStart=39 / fadeEnd=152
iconSize=91 / minIcon=18 / maxIcon=72 / gap=6 / pad=10
dumpBake=0
```

**三个节奏的关系**（2026-11-12 17:00 加，设置面板里可直接拖）：
- `refreshHz` = 主定时器周期（`1000/refreshHz` ms，**>62Hz 时自动 `timeBeginPeriod(1)`**），每一拍做：淡出、吸附角动画、悬停动画步进、按需重绘。
- `captureHz` = 多久重新 `PrintWindow` 抓一次背景快照。**拖动/缩放期间跳过**（抓一次 20~30ms，必然卡顿），拖动时只是把上一张快照按新偏移重新裁剪。
- `hoverMs` = 图标放大/缩小动画的**时长**（2026-11-12 20:50 由 `hoverHz` 改来）。**注意方向**：改时长不改顺滑度，顺滑度看的是「这段时间里插了多少帧」。动画跑起来时会单独开 8ms 定时器（timer 5）来采样，所以 160ms 的放大能拿到 10~15 帧，而不是跟着 30ms 主定时器只有 3~5 帧。
- `captureHz` 永远 ≤ `refreshHz`（`LoadConfig()` 夹紧并回写 ini）。
- 日志证据：`cadence: refresh=.. capture=.. hover=..` 启动/改设置时打一条；`cadence: N ticks / M repaints in X ms` 每 10s 一条（空闲应为 0 repaints）。
- 实测天花板：1335x117、blur=8 时拖动约 **29~30 repaints/s**（每拍全流程 ~30ms）；设置 60Hz 时实际 tick ~40/s，144Hz 时 ~63/s（`timeBeginPeriod(1)` 生效后）。再高的值只是"上限"，不会真的到 180。

反直觉点：`blurRadius` 越大，透出来的清晰桌面反而更"清楚"（玻璃层被抹平）；文字糊不掉只能靠 `glassOpacity`。

---

## 5. 坑（血泪清单，按踩到的次数排序）

1. **`Shell_NotifyIcon` 在 App 进程执行**——hook explorer 什么都拿不到，必须 `@include *` 注入每个进程。
2. **共享块 DACL 决定一切**：谁先 `CreateFileMapping` 谁决定 DACL。开机时提权组件（联想那批）先加载 mod → 中等权限的 dock 打开时 `ERROR_ACCESS_DENIED(5)` → dock **静默退回注册表历史** → 表现为"所有图标右键都没反应、只有一个 QQ、还混进 explorer.exe"。两侧都必须用 NULL DACL。
3. **Windhawk 重载 mod 会重建共享表**（所有实例卸载 → 最后 handle 关闭 → 表消失）。App 不重报就丢图标。对策：dock 持有 handle + mod 磁盘快照 + 打开宫格时广播 `TaskbarCreated`。
4. **`@architecture` 只能单值**（`x86` / `x86-64` / `amd64` / `arm64`）。写 `x86,x86-64` 直接编译失败。
5. **32 位源码里 `EnumWindows(lambda)` 编译不过**（clang/i686 要求 `__stdcall`）→ 写成 `static BOOL CALLBACK f(HWND, LPARAM)`。
6. **注册表兜底 = 历史记录**：`HKCU\Control Panel\NotifyIconSettings` 里 63 条、15 条"exe 正在跑"，它们**没有回调消息**（右键只会 `ignored (no callback message)`），而且**每个 App 一条**（QQ 两进程共用 UID=3）→ 永远只有一个 QQ，还可能是启动器。宫格必须依赖桥。
7. **同一个 App 可能注册多条**（QQ 两个进程各一条）。合并键必须是 **(exe, hwnd, uid)**；按 (exe, tip) 合并会吃掉第二个 QQ。
8. **`Favorites` blob 不是 2 字节对齐的**：UTF-16 从偏移 0 解出 Edge/VSCode/QQ，从偏移 1 才解出 文件资源管理器/Clash/EchoMusic。两种对齐都要解。
9. **`IsWindowVisible` 不能判断"菜单还在屏幕上"**：复用的弹窗一直 `WS_VISIBLE`；也不能用"采样点 `WindowFromPoint`"（菜单向上弹、一半在屏外）。判断"点没点外面"用 `GetAsyncKeyState` + 菜单矩形。
10. **同一时间只跟踪一个菜单**：连着右键两个图标，先来的会被遗忘在屏幕上 → 开新菜单前先关旧的。
11. ~~**`GridTick` 与 `TrayMenuTick` 抢关闭时机**（500ms vs 600ms）~~ —— 2026-11-12 起 `GridTick` 已删除，收起统一由 `PressWatchTick`/`FocusWatchTick` 决定，不存在抢时机。
12. **绝不要在宫格打开期间重建列表**：`g_tray` 按 tip 排序，重建会让图标在光标底下跳位，点击就打到邻居/空格。新图标下次打开再显示。
13. **日志里 `tray[i]` 是排序前的顺序**，格子是排序后的——对不上是正常的（我自己看错过一次）。
14. **Electron 的托盘菜单需要前台窗口**：`GetForegroundWindow()==NULL` 时它的 `SetForegroundWindow` 被系统拒绝 → 菜单不出现（QQ 不走这条路，所以一直正常）。对策：`AllowSetForegroundWindow(ASFW_ANY)` + fg 为空时先激活该 App 一个可见窗口 + 300ms 后重投一次。
15. **零时长点击会被忽略**：DOWN/UP 连着 `PostMessage`，有的 App 当抖动丢弃。UP 要延后 ~70ms（用定时器，别 Sleep）。
16. **不要在菜单显示期间 `SetForegroundWindow` 该 App**（会把菜单顶掉）；也不要给菜单重投托盘消息来"关"它。
17. **`FindWindow("#32768")` 找不到 WPF/Tk/Qt 的托盘菜单**，用"新窗口 + 盖住光标的无边框 popup"。
18. **提权 App（`LZTray.exe` = Legion Zone）只能开不能关**：`WM_CLOSE` 返回 `False`+`err=5`，`SetWindowPos`/`ShowWindow`/`taskkill` 全部拒绝访问；但 `WM_RBUTTONDOWN/UP` 它自己放行。它的菜单会留在屏幕上。
19. **任务栏"隐藏"时 rect 在屏幕下方**（1080p 上 `y=1077..1137`）：`rect.bottom >= 屏幕底` 恒真。要用"与显示器矩形的重叠高度 > 8px"判断可见。
20. **任务栏 mod 的"宽限"是 bug 制造机**：用户要求"按 Win 出现 / 再按 Win 收起"，任何 grace 都会让鼠标悬停再次唤出。只允许"Win 按下"这一瞬间的展开请求，任务栏一出现立刻撤销许可。
21. **Win11 没有 `ToolbarWindow32`**；`Shell_NotifyIconGetRect` 对 GUID 图标全失败；任务栏被移到屏幕外时 UIA 也拿不到托盘按钮。
22. **本机任务栏在屏幕外**（物理 y≈1077），"对照真实任务栏"不可行，只能按规则推定。
23. **低级完整性**：从 workspace 启动的 exe 是 Low IL（`integrity=4096`），**不能创建子进程**。必须从安装目录启动（8192）。
24. **ini 带 UTF-8 BOM 会让所有配置失效**（`StripIniBom()` 必须保留）。
25. **GDI 画到 32bpp DIB 会把 alpha 写 0**：自绘必须走 `SetPixelPremul()` / `BlendPremul()` / `BlendScaled()` / `DrawTextAlpha()`。
26. `small` 是 Windows 头文件的 typedef，不能当变量名。
27. **ops_bash 是 bash**：`$`、`|`、`>` 会被吃掉 → 带变量的 PowerShell 一律写成 `.ps1` 再 `-File` 跑。
28. **PowerShell 保留变量**：`$pid`、`$Host` 只读；`LP` 是 `Out-Printer` 的别名（函数别叫 LP）。
29. **坐标有两套**：`probe.ps1` 设了 DPI 感知（物理像素），`winstate.ps1` 没设（虚拟化 1/1.25）。混淆会得出荒谬结论。
30. **不要给用户开全屏高对比测试图**（曾吓到他）；测玻璃时把窗口限制在 dock 附近。
31. **mod 注入时机**：启用前就在运行的进程不会被注入；重编译 mod 后已运行的进程仍挂旧 DLL（要么重启 App，要么重启系统）。
32. **点击分类必须看"按下落在哪个窗口"**：`GetAsyncKeyState` 低比特只告诉你"用户按下了"，`WindowFromPoint` 才告诉你在点谁。落在自己窗口/正在跟踪的菜单上的按下**不能**当成"点外面"，否则二次右键永远弹不出新菜单（用户 2026-11-11 报的那个 bug）。
33. **"失焦"要区分"我们自己造成的"**：点图标会 `SetForegroundWindow` 目标 App，右键托盘图标也可能让 App 抢前台。必须把这些窗口记成"自己人"（`g_fgAtGridOpen` / `g_friendPid` / `g_focusGraceUntil`），否则刚点完图标面板就自己收起来。
34. **`GetForegroundWindow()` 可能是 NULL**（本机常见）：失焦判据遇到 NULL 要直接放过，否则会疯狂收起。
35. **从沙盒里驱动测试**：`SetCursorPos` 可能返回 err=5（权限不足），`mouse_event` 绝对移动可用但坐标要用 `GetSystemMetrics` 自己换算；`FindWindow("DockStripWindow")` 会 err=5，改用 `EnumWindows` 按类名找（`dev/wins2.ps1`）。
36. **"宫格消失了"未必是被隐藏**：先看日志有没有 `grid: hide`。没有的话就是 z-order——宫格被提过顶层的窗口盖住了。判据：宫格中心点 `WindowFromPoint` 返回别人的窗口（日志 `grid visible but covered ...`）。**topmost 带是唯一稳的位置**，别为了给菜单让位把它降级。
37. **焦点比较要用 pid**：App 弹托盘菜单时经常把焦点移到自己的另一个窗口（Electron 的菜单宿主），只比 `GetForegroundWindow()` 的 HWND 会把同一进程内的切换当成"第三方抢焦点"。
38. **不是所有固定项都有 exe 目标**：`File Explorer.lnk` 这类是 shell 命名空间项，`IShellLink::GetPath()` 返回空。没有 exe 的 pin 永远匹配不到窗口 → 条上会出现"僵尸图标"（旧 pin 按钮 + 窗口按钮两份）。兜底顺序：`GetIDList`+`SHGetPathFromIDListW` → 快捷方式图标位置里的 `.exe`。

---

40. **不要用 `Get-Process x.Modules` 判断 SYSTEM 进程有没有被注入**：对 SYSTEM/提权进程从普通权限读模块列表会**返回空表而不报错**（`tasklist /M` 显示"N/A"），会被误判成"没注入"。要判断注入与否，看 `%ProgramData%\Windhawk\Engine\ModsWritable\mod-status\` 里有没有 `<enginePid>_<ts>_<targetPid>_local@<mod>`（这些文件是 SYSTEM 权限，读内容会 AccessDenied，但**文件名就能用**）。
41. **NVIDIA 的托盘图标会整段消失（几分钟），不是闪一下**：`NVDisplay.Container.exe`（服务 `NVDisplay.ContainerLocalSystem`）只在少数时机重新注册图标，且**不响应**我们广播的 `TaskbarCreated`；2026-11-12 实测采样 8×2s，桥表 version 完全不变（没有任何写入），说明不是竞争/覆盖，是它自己不注册。想要它回来只能重启这个服务（需管理员）或重启系统——新进程启动时 mod 已就绪，注册就能被捕获。
39. **Windhawk 的注入闸门**：引擎默认注入所有进程，排除"预定义列表"（关键系统进程 + 已知不兼容进程）。`HKLM\SOFTWARE\Windhawk\Engine\Settings` 里 `InjectIntoGames` / `InjectIntoIncompatiblePrograms` / `InjectIntoCriticalProcesses`（本机全 0）是**整批**放开某类黑名单，`Include` / `Exclude` 才是**按进程**的"包含/排除列表"（对应 Windhawk 设置里的 Process inclusion/exclusion list）——**要只放行某一个程序（如 wallpaper64.exe），用 Include 列表，不要开全局开关**。mod 自己的 `@include`/`@exclude` 是再往下一道过滤。判断是否真被注入：`%ProgramData%\Windhawk\Engine\ModsWritable\mod-status\<enginePid>_<ts>_<targetPid>_local@<mod>` 有记录才算，没记录 = 引擎根本没尝试。来源：Windhawk wiki "Injection targets and critical system processes"。

42. **`GetAsyncKeyState` 轮询会漏按**：App 自己的菜单刚收起的那一瞬间（Electron/WinForms 还没释放鼠标 capture），低比特有时读不到，于是"点外面"不生效、面板要靠 1s 后的失焦才收——用户看到的就是"闪一下、停一秒才消失"。解法：**低级鼠标钩子 `WH_MOUSE_LL`**（`LowLevelMouseProc`）报按下，`GetAsyncKeyState` 只做兜底。
43. **悬停缩略图是 topmost 窗口，会盖住菜单**：右键条上图标时先 `KillTimer(h,3)` + `ThumbHide()`，并且 `g_popupOpen` 为真时定时器不再显示预览。
44. **dot-source 的脚本带 `param()` 会污染调用者变量**（`dev/statelib.ps1` 曾经因此把测试脚本的 `$Out` 改成默认值）。公共库不要写 `param()`。
45. **PowerShell 5.1 读 UTF-8 无 BOM 的中文脚本会解析失败**（报"字符串缺少终止符"）。含中文的 `.ps1` 必须带 BOM。
46. **python 直接往 Windows 控制台打中文会 GBK 报错**：写成 UTF-8 文件，再用 `ops_read_files` 读；`ops_bash` 的 `tail`/`grep` 也不认 UTF-16。
47. **`FindWindow("#32768")` 不一定有**：菜单关掉后就没有这个窗口，测试脚本别假设它一直在；而且用户/App 的菜单也可能同类名（先看它是不是我们进程的）。
48. **条上 `g_scroll` 会滚动**：图标多于容量时按"左+pad+i*cell"算出来的是可见位置，不是 item 序号；要么读 `hover -> N` 闭环，要么先读日志里的 `items=` 与滚动状态。

## 6. 代码地图（`dock.cpp`）

| 区块 | 说明 |
|---|---|
| `LoadConfig()` / `StripIniBom()` | ini 读取 |
| `BuildItems()` / `PinnedLnkListed()` / `IsCandidate()` / `WindowLabel()` | 条的内容：固定项（注册表）+ 窗口 |
| `BuildTray()` / `BuildTrayFromBridge()` / `TrayBridgeOpen()` / `TrayBridgeEnsureExists()` | 托盘数据（桥 → 兜底） |
| `ComputeButtons()` / `ComputeLayout()` | 条布局、翻页 |
| `Paint()` / `Present()` / `RenderIconCache()` | 绘制、图层输出 |
| `CaptureBackdrop()` / `GrabScreenUnderUs()` / `WindowUnderUs()` | 玻璃背景 |
| `GridShow` / `GridLayout` / `GridPaint` / `GridProc` / `GridClick` | 宫格（`GridTick` 已删除，收起由 `PressWatchTick`/`FocusWatchTick` 决定） |
| `MenuWindows()` / `MenuLikeWindow()` / `TrayMenuTick()` / `CloseMenuNow()` / `CloseMenuWindows()` / `FitMenuToWorkArea()` | 托盘菜单转发 |
| `PressWatchTick()` / `FocusWatchTick()` / `IsOwnWindow()` / `IsMenuWindow()` | 交互状态机的"点外面"和"失焦"判据 |
| `JumpTasksEnsure()` / `ParseCustomDestination()` / `JumpTasksForExe()` / `RunJumpTask()` / `ShowAppMenuForSlot()` | 条上图标右键菜单（解析 CustomDestinations 里的 App tasks） |
| `DistanceToWindow()` / `UpdateAlpha()` | 淡入淡出（宫格/菜单在时强制 255） |
| `EdgeAt()` | 缩放热区 |
| `AutoStartPath/Enabled/SetAutoStart()` | 开机自启 |
| `ThumbShow()` / `ThumbProc` | DWM 悬停缩略图 |
| `SettingsPaint()` / `SettingsWndProc` | 设置面板 |

---

## 7. `dock/dev/` 脚本

**日常验证**

| 脚本 | 用途 |
|---|---|
| `run.ps1` | 杀旧 dock → 安装目录启动 → 打印进程/日志头 |
| `gridrc.ps1 -Cell N -Out x.png` | **最稳的宫格测试**：没开就先开（从右往左扫 `^`），再对第 N 格真实右键并截图；`-Cell -2` = 只打开不点。注意 `tray[i]` 是排序前的顺序 |
| `repeat.ps1 -Row R -Col C -Times N` | 连做 N 轮"右键 + 点外部关闭" |
| `rc_at.ps1 -X -Y` / `rc_slow.ps1` / `rc_moveaway.ps1` | 指定点右键 / 慢按 / 点完立刻移开 |
| `clean.ps1 x.png` / `hover_shot.ps1` | 移开光标后截图 / 悬停 `^` 截图 |
| `cropzoom.py in out "l,t,r,b" [scale]` | 裁剪放大 |
| `bridgedump.exe [-b]` | 打印桥表（`-b` 先广播 TaskbarCreated） |
| `qqmenu.ps1 -Proc <名> -Hwnd 0x.. -Uid N -Msg 0x..` | 托盘消息矩阵（UP / DOWN+UP / CONTEXTMENU / LBUTTONUP / uid=1 / UP×2） |
| `elevated.ps1` | 列出所有提权进程 |
| `whatwindow.ps1 -X -Y` / `onscreen.ps1` / `resp.ps1` | 某点窗口 / 窗口是否真在屏上 / 进程是否卡死 |
| `favorites*.ps1` / `cands.ps1` / `winstyle.exe` | 固定项 blob 解析 / 窗口规则对照 / 合成测试窗口 |
| `probe.ps1` / `winstate.ps1` / `fullshot.ps1` / `log.ps1` | 条矩形 / 窗口状态 / 截图 / 过滤日志 |
| `statelib.ps1` | 状态机测试的公共库（**dot-source 使用**，故意没有 `param()`：dot-source 的参数会污染调用者的 `$Out`）：`Open-Grid` / `Show-State` / `Shot` / `MoveTo` / `LeftClick` / `RightClick` / `Wait-Idle` / `Get-TrayCellMap` |
| `traytest.ps1` | **合成托盘图标**（PowerShell `NotifyIcon` + `ContextMenuStrip`，菜单项"测试项 1/2、退出"，点了会写 `traymark.txt`）。安全地验"点菜单项"这类操作，别去点真 App 的菜单。启动要 `Start-Process`（脱离），脚本文件必须带 BOM（含中文） |
| `t_clickprobe.ps1 [-WithMenu]` | 点外面 → 面板多久收（打印 `hidden after N ms` + 关键日志） |
| `t_hidespeed.ps1` / `t_itempick.ps1 -Exe <名字>` / `t_menublank.ps1` | 同上 / 右键某 exe 的格子并点菜单项 / 点菜单空白处 |
| `t_leftclick.ps1 -Exe <名字>` | **左键**点某 exe 的格子，打印面板是否保持 + 关键日志（验待办 A） |
| `jumplist.exe [-exe <路径>] [-file <文件>]` | 直接 dump 跳转列表文件里能读到的 shell link（title/target/args），调研用 |
| `t_stripmenu.ps1 -Exe <名字>` / `t_menupick.ps1 -Exe <名字> [-ItemY N] [-NoClick]` | 右键条上某按钮并截图 / 点菜单第 N 项（`-ItemY` 是相对菜单顶部的像素） |
| `t_blankmenu.ps1 [-ClickY N]` | 右键条的空白处（打开 dock 自己的菜单）并截图；`-ClickY` 点第 N 像素处的菜单项 |
| `nvmon2.ps1 -Seconds N` / `bridgedump.exe` | 轮询桥表，观察条目增删（诊断"图标自己消失"用） |
| `iswindow.ps1 -Hex 0x..` / `readstatus.py` / `modstatus.py` | 查某 hwnd 是否还活着 / 读 Windhawk mod-status（文件名即可判断注入） |
| `t_slotpick.ps1 -Exe <名字> [-ItemY N]` | **按日志里的 `hover -> N` 闭环定位**条上按钮再右键/点击（条上有滚动时按几何算会错） |
| `aumid.exe [-hash <字符串>]` | 列出各窗口的 exe + `PKEY_AppUserModel_ID`；`-hash` 给出 6 种跳转列表文件名哈希候选 |
| `pintest.ps1 [-Unpin]` | 试 `taskbarpin` / `taskbarunpin` 隐藏 verb 是否还有效（本机 Win11：无效） |
| `jumplistfiles.ps1` / `pins.ps1` / `pidwins.ps1` / `listwin.ps1` | 跳转列表文件清单 / 固定项快捷方式解析 / 某 pid 的窗口+样式 / 全部可见窗口 |
| `t_state2a.ps1` / `t_clickout.ps1` | 2a（光标移远不收）/ 2b-i（点外面立刻收） |
| `t_focus.ps1` | Alt+Tab 失焦应收起（日志 `focus left us`） |
| `t_iconclick.ps1 -Cell N` | 点宫格第 N 格（验 2b-iii：窗口起来但面板保持） |
| `t_menu2.ps1` | 3c-iii（右键换图标换菜单）/ 3b-ii（点面板空白关菜单）/ 3b-i（点外面全收）三连 |
| `t_statefull.ps1` | 上面几条串起来的一遍过版本 |
| `t_flip.ps1` | **快速闪避**：PostMessage 双击条的左内边距（不搬真人光标）→ 打印落点 / 期望镜像点 / 日志。带重试：真人正在动鼠标时，注入的 DOWN 会被 `WM_MOUSEMOVE` 的"陈旧按下"判据清掉（真实双击不受影响） |
| `t_gridplace.ps1 [-Tmp "x,y,w,h"]` | **宫格定位**：先把光标停到 (8,8)（避免悬停放大改变槽位），按 `ComputeButtons` 的容量公式算出 `^` 的位置并 PostMessage 点它，打印宫格/条/工作区矩形，判定"是否全在屏内 / 是否压条"。`-Tmp` 可临时把条摆成贴底或竖向（结束时复原） |
| `t_snap.ps1` | **吸附**：把条摆到自由位置 / 顶边 / 底边，光标停在条上让它不透明，然后读四个角的屏幕像素（直角=玻璃色、圆角=背景透出来）+ 抓 `snap: corners` 日志 |
| `t_snapflip.ps1` | 吸附 + 闪避联动：条停顶边 → 双击 → 落到下边且下两角变直角；结束会复原条位置并改写 `dock.ini` 的 x/y |
| `t_resize.ps1` / `t_clicksize.ps1` | 临时改条尺寸 / 改尺寸后再注入点击的复现脚本（查 12:42 那次崩溃用，暂留） |
| `wins2.ps1` | 枚举全部可见窗口 + 类名（`FindWindow("DockStripWindow")` 在本机沙盒里会返回 err=5，改用 EnumWindows 按类名找） |
| `logtail.ps1` | dock 在跑时日志被独占，`Get-Content` 会失败；这个脚本用共享读拿到尾部 |
| `menutest.ps1 -Cell N [-Dx -Dy]` | 右键第 N 格 → 抓新出现的弹窗窗口 → 打印菜单 rect / 光标前后位置 → 可选自己再 `SetWindowPos` 平移它 → 截图 |
| `clickat.ps1 -X -Y [-Button right]` | 真实鼠标点击（`SetCursorPos` + `mouse_event`，沙盒限制下的唯一办法） |
| `hoverat.ps1 -X -Y -Out x.png` | 把光标移到某点并截图（测"移动后的菜单还有没有命中测试"） |
| `setcfg.ps1` / `one.ps1` / `sweep.ps1` / `autostart.ps1` | 改配置 / 单次渲染 / 扫半径 / 自启 |

---

## 8. 交互状态机 + 待办队列

### 8.0 状态机（用户 2026-11-11 23:40 完整定义，2026-11-12 00:05 实现）

三种状态：**1 = 只有条**；**2 = 条 + 宫格**；**3 = 条 + 宫格 + App 右键菜单**。
`条∪宫格` 指两者的矩形并集；"没点中图标"= 落在矩形内但不在任何格子上（宫格内边距、条上的空白、`^` 以外）。

**状态 1**：条只按"光标到条的矩形距离"淡入淡出（fadeStart/fadeEnd），失焦不影响它。✅ 保持原样

**状态 2**：
| 事件 | 结果 |
|---|---|
| a 鼠标移动（去哪都行，失不失焦） | 条、宫格**都保持**（条强制 alpha=255，宫格不收） |
| b-i 左键点 `条∪宫格` 外 | 宫格**瞬间消失**；条回到按距离淡出 |
| b-ii 左键点内、没点中图标 | **无事发生**（保持） |
| b-iii 左键点中图标 | 打开对应窗口；条、宫格**保持** |

**状态 3**：
| 事件 | 结果 |
|---|---|
| a 鼠标移动 | 三者**都保持** |
| b-i 左键点三者外 | 菜单 + 宫格消失；条按距离淡出 |
| b-ii 左键点 `条∪宫格` 内、没中图标 | **菜单消失**，条 + 宫格保持 |
| b-iii 左键点中图标 | 打开窗口，菜单消失，条 + 宫格保持 |
| b-iv 左键点菜单项 | App 自己执行并收菜单；**宫格也跟着消失，条回到按距离淡出**（用户 2026-11-12 00:22 修正；判断依据：我们看见按下落在菜单上 = 用户选了东西） |
| c-i 右键点三者外 | 菜单 + 宫格消失；条按距离淡出 |
| c-ii 右键点 `条∪宫格` 内、没中图标 | 条 + 宫格保持，**菜单消失** |
| c-iii 右键点中图标（含同一图标） | 关旧菜单、开新菜单（同一图标 = 刷新位置，走同一条路径） |
| c-iv 右键点菜单本身 | 什么都不做，App 自己决定 |

**失焦**（用户 2026-11-11 23:5x 拍板）：前台变成"既不是 dock 自己、也不是**打开宫格那一刻的前台窗口**、也不是**我们刚激活/正在弹菜单的那个 App**"时，收起宫格 + 菜单。只有条时（状态 1）不看失焦。

### 8.1 实现（`dock.cpp`，2026-11-12 00:39 构建）
- `PressWatchTick()`：**低级鼠标钩子 `WH_MOUSE_LL`（`LowLevelMouseProc`）报按下 + `WindowFromPoint` 分类**——落在 `IsOwnWindow()` / `IsMenuWindow()` 上就交给窗口过程，否则算"点外面" → `CloseMenuNow()` + `GridHide()`。**这条替换了旧的 `MenuWatchTick`**，顺手治好了"二次右键"：现在右键落在宫格里先关旧菜单，再由 `GridProc` 开新的。
  - 为什么必须用钩子：只靠 `GetAsyncKeyState` 低比特时，**App 自己的菜单刚收起的瞬间（Electron/WinForms 释放 capture 之前）那一下按下会漏掉**，于是面板不立即消失、要等 1.2s 后失焦判据才收——正是用户看到的"闪一下、停留 1s 才消失"。钩子模式下连续 3 次实测 122~125ms 内收干净。
  - 钩子装不上（返回 NULL）时自动退回原来的轮询；日志 `mouse hook = <h> (err=..)`。
- `FocusWatchTick()`：上面那套"自己人"判据；`g_fgAtGridOpen` + **`g_fgPidAtGridOpen`**（pid！App 弹菜单时会把焦点挪到自己的另一个窗口，只比 HWND 会误判成"被第三方抢走"）在 `GridShow()` 里记，`g_friendPid` 在 `ActivateWindow()` / 点条上图标 / 菜单自己消失时记，外加 `g_focusGraceUntil` 宽限 300ms（启动 App 时 2s）。
- **宫格不再降级**（2026-11-12 01:00）：以前右键时 `SetWindowPos(g_gridWnd, HWND_NOTOPMOST, ...)` 让菜单盖住宫格，但宫格一旦不在 topmost 带，**任何被激活的窗口都会跑到它上面**——前台 App 弹自己的菜单时把自己抬起来，宫格就被"盖没了"，而日志里连一条 `grid: hide` 都没有（看着像消失，其实是被盖住）。现在改成：宫格一直 topmost，检测到菜单后 `RaiseMenuAbovePanel()` 把**菜单**提进 topmost 带（`ok=1` 常见）；提不动（提权 App）才回退去降级宫格。
- 诊断：宫格可见时每 1s 检查"宫格中心点被谁盖住"，日志 `grid visible but covered at its centre by ...`；开宫格时记 `grid: focus at open = <hwnd> pid=<pid>`。
- `GridTick()` 整个删掉（不再"光标离开 500ms 收起"）；`TrayMenuTick()` 里的"光标离开 600ms 收宫格"也删掉。
- 菜单消失分两种（`g_menuItemPressAt` 记"按下落在菜单上"）：**用户点了菜单项** → 收面板（`grid: hide (from menu item picked)`）；**App 自己收的** → 面板保持（`tray: app menu is gone - panel stays`）。
- `GridHide()`：**先 `ShowWindow(SW_HIDE)` 再 `CloseMenuNow()`**——`CloseMenuNow` 会把面板重新提回 topmost 带，之前顺序反了会让"正在收起的宫格"闪一下再消失（用户报的"闪烁"）。
- `UpdateAlpha()`：`g_setWnd || g_gridVisible || g_menuOpen` 时强制 255。
- `GridClick()`：不再 `GridHide`，改为关菜单 + 记 friendly + 激活/启动。
- `GridProc`：左键点面板空白只关菜单不收面板；右键点面板空白也只关菜单、**面板保持**（2c-ii，2026-11-12 修）；右键先 `CloseMenuNow()` 再按格子开新菜单。
- `条` 的右键菜单：先关掉挡路的托盘菜单，再弹 dock 自己的菜单（用户确认"空白处=dock 菜单"）。
- 托盘条目**宽限期**（2026-11-12 11:14）：`BuildTrayFromBridge()` 记住上一轮完整集合，若某条目的 owner 窗口还活着且消失 < 30s，就继续显示这一格（日志 `keeping its cell (owner window alive)`；超过 30s 丢弃 `has been gone for N ms - dropping it`）。治"App 用 NIM_DELETE+NIM_ADD 刷新图标"造成的闪断。
- 条上空白处菜单新增 **「重新扫描托盘」**（2026-11-12 10:52）：广播 `TaskbarCreated` → 600ms 后读桥表并把条目数写日志（`tray: rescan done - the bridge now holds N icon(s); they show the next time the panel opens`）。Windhawk 重载 mod 后丢图标的自愈入口。`^` 保留"宫格开关"语义（用户 2026-11-12 00:22 同意）。

### 8.2 已验证（日志 + 截图 / 截图在 `dock/dev/`）
- 2026-11-11 23:56 ~ 00:03：2a、2b-i、2b-iii、3a、3b-i、3c-iii、失焦（Alt+Tab → `focus left us`）、菜单平移。
- 2026-11-12 00:30：**2c-ii** 右键点面板空白 → `tray: right click on empty panel space - panel stays`。
- 2026-11-12 00:34：**3b-iv** 用合成托盘图标（`dev/traytest.ps1`，PowerShell NotifyIcon + ContextMenuStrip）验证：`press: left on the app menu ... - the app decides` → `app menu is gone after a click on it - closing the panel` → `grid: hide (from menu item picked)`，同时 mark 文件记录 `item1 clicked`（证明菜单项真的执行了）。
- 2026-11-12 00:38：**3c-i/3b-i 时延**三次实测 `panel invisible after 122/122/123 ms`（含点击自身 70ms 的 DOWN-UP），日志 `left click outside ... grid: hide (from click outside)` 同毫秒。
- 2026-11-12 00:58~00:59：**前台 App + 右键其图标**（用户 00:51 报的现象）——`BringWindowToTop` 把 DeepSeek 抬到前台后再右键，宫格保持可见、`tray: lifting menu ... ok=1`、截图里菜单画在宫格之上；QQ 的 183x620 长菜单同样如此（`dev/t_qqtop_1after.png`）。
- 仍未由人手复核：连续真鼠标操作的手感（"闪烁"是否消失）+ 用户报的"前台 App 首次右键宫格消失"是否真的没了。

### 8.3 待办队列（按用户指定的优先级/顺序）

**待办 A：宫格托盘图标左键改成"纯转发"** —— ✅ 已完成（2026-11-12 01:08 构建，已验证）
- 实现：`ForwardTrayClick(e, WM_LBUTTONDOWN, WM_LBUTTONUP, L"left")` —— 和右键同一套：`AllowSetForegroundWindow(ASFW_ANY)` + 投 DOWN + 70ms 后由 30ms 定时器投 UP（`g_upPendingButton` 决定投左还是右），并把该 App 记成 `g_friendPid`（否则新失焦规则会立刻收面板）。**不猜** ：不再"找该 exe 的窗口"、也不再自己启动它。
- 只有拿不到回调消息的条目（注册表兜底 / 图标已死）才退回 `TrayActivate()`，日志会写 `left click on '<tip>' has no callback message - falling back to activate`。
- 验证（2026-11-12 01:07）：
  - 合成托盘图标（`dev/traytest.ps1`）：`tray: left click -> 0000000000CB0AB4 msg=0x800 uid=1 'TrayTest' post=1 err=0` + `left click up ... (after 78 ms)`，mark 文件记到 `mouse Left`（App 真的收到了），面板保持。
  - WorkBuddy：点击后前台变成 pid=16024（workbuddy.exe）——原来"点了没反应"的问题没了。
  - QQ：点击后前台变成 QQ 主窗口（984x652，已登录界面，聊天列表正常），不再是"新增登录账号"页。
  - 右键路径回归：`right click up ... (after 78 ms)`，合成图标记到 `mouse Right`，菜单正常弹出并被提进 topmost。

**待办 B：条上固定项左键启动失败**（VSCode / EchoMusic 转圈后没反应）—— ✅ 已自行消失（用户 2026-11-12 01:41："可能是与某个地方关联了，那个地方改好了这里也跟着好了"）。**不再追**，没有单独改代码。

**僵尸图标（条上同一个 App 出现两个按钮，旧的那个没有缩略图、点击会另开窗口）** —— ✅ 已修（2026-11-12 01:45 构建）
- 现象（用户 01:41 描述）：固定在条上的图标点开窗口后会**多出一个相同的新图标**，旧图标（"僵尸"）不对应新窗口、悬浮无缩略图；再点旧图标还能继续叠新窗口。QQ / VSCode 在这几轮修复后已经正常，只剩**文件资源管理器**。
- 根因：`BuildItems()` 用 **`pin.exePath == 窗口 exe`** 把窗口挂到固定项下。而 `File Explorer.lnk` 是 **shell 命名空间项**，`IShellLink::GetPath()` 返回空 → 这个 pin 的 `exePath` 永远是空 → 永远匹配不到任何窗口 → 既保留一个"启动快捷方式"按钮（僵尸），又额外列出窗口按钮。
  点僵尸 = 运行那个 lnk（= 启动 explorer.exe），于是"新窗口有没有被操作过"由 **资源管理器自己**决定：没动过就复用/唤起，动过就再开一个 —— 用户看到的"叠窗口"就是这么来的，不是我们的逻辑。
- 修法：`AddPin()` 里 `LnkTarget()` 为空时走 `LnkTargetFallback()`：先 `IShellLink::GetIDList` + `SHGetPathFromIDListW`（只接受存在的 `.exe`），再退到**快捷方式的图标位置**（`GetIconLocation` → 展开环境变量 → 去掉 `,index`，同样只接受存在的 `.exe`）。File Explorer 的图标是 `%windir%\explorer.exe,0` → 解析成 `c:\windows\explorer.exe` → pin 立刻能挂窗口。
- 验证（01:43~01:45）：日志 `pin 'File Explorer' has no target path - using c:\windows\explorer.exe for window matching`；条目从 14 → 13，`[2] hwnd=00000000004F0DA4 pin=0 exe=c:\windows\explorer.exe`（窗口挂到 pin 的位置，不再有独立的僵尸 pin）；悬停 `thumb: register slot=2 item=2 hwnd=...` 有缩略图；点击 `click slot=2 ... activate: plain ok` 前台变成已有的资源管理器窗口（**没有新开窗口**）。

**待办 C：条上图标右键 = 接近原生任务栏的菜单** —— ✅ v1 已完成（2026-11-12 02:10 构建）

**API 调研结论（先说清楚"官方能不能做"）**
- **没有**任何公开 API 能"弹出某个 App 的任务栏右键菜单"。Win11 那个菜单是 explorer 内部的 XAML 弹窗；jump list 的公开 API（`ICustomDestinationList` / `IApplicationDestinations` / `IApplicationDocumentLists`）只允许 App **定义自己**的跳转列表，没有"显示别人的"入口。`Windows.UI.Shell.TaskbarManager` 只针对当前 App 且要求打包身份。
- **固定/取消固定也没有**公开 API（微软文档明确说应用不应以编程方式固定）。老办法是 `ShellExecuteEx` 的隐藏 verb `taskbarpin` / `taskbarunpin`；**2026-11-12 在本机实测无效**（命令执行了、固定文件夹无任何变化，`dev/pintest.ps1` 可复现）。所以菜单里**不做**固定项。
- Windhawk 侧：mod 是注入目标进程 hook 函数。理论上可以 hook explorer 里"显示任务栏按钮菜单"的内部函数再配 IPC 让外部触发，但那是深度逆向且要跟着版本走，**没有现成的公开 mod**。

**实现（`dock.cpp`）**
- 数据源：`%APPDATA%\Microsoft\Windows\Recent\CustomDestinations\*.customDestinations-ms` —— **不是 OLE 复合文档**，是"小头 + 一串 shell link"的扁平结构。扫描 link 头魔数 `4C 00 00 00 01 14 02 00 00 00 00 00 C0 00 00 00 00 00 00 46`，每命中一处就用 `SHCreateMemStream` + `IPersistStream::Load` 当 shell link 解析，取 `GetPath` / `GetArguments` / `PKEY_Title`。
- 缓存：`JumpTasksEnsure()` 按"目录里文件数 + 最新修改时间"做签名，最多 1s 检查一次；实测全量 354 条任务、151 个文件，首次约 100ms，之后免费。
- 菜单（`ShowAppMenuForSlot()`，系统 `TrackPopupMenu`，原生外观/键盘/点外面自动关）：
  `<App 名>` / 分隔线 / App 的 tasks（最多 12 条，按目标 exe 过滤）/ 分隔线 / `关闭窗口`（有 hwnd 才显示）。
  - 名字规则（用户 2026-11-12 02:24 要求）：**不带"打开"前缀**，而且**不随是否有窗口而变** —— 优先用 pin 的名字（`g_pinInfo` 表，`AddPin()` 时登记，即使 pin 已被窗口按钮取代也保留），其次 `SHGetFileInfo(SHGFI_DISPLAYNAME)`。所以文件资源管理器永远是 "File Explorer"，不会变成 "explorer.exe"。
  - **去重**：Edge/Chrome 会为每个 profile/自动化运行留一个 destination 文件（本机有一堆带 `--user-data-dir=%TEMP%...` 的残留），按目标 exe 过滤会把同一批任务列 6 遍。现在先按文件修改时间从新到旧，再**按标题去重** —— 原生菜单也是每个任务只出现一次。
- 任务执行：`ShellExecuteW(open, target, args)`。
- **名字项的点击行为**：改成"**运行 pin 的快捷方式，让 App 自己决定**"（`LaunchShortcut(pin->lnk)`）。这正是任务栏的做法：单实例 App（QQ）会把自己的窗口调到前面，多实例 App（Edge / 资源管理器）会新开一个。没有 pin 的窗口项才走"激活那个窗口"。
  - 实测：点 File Explorer 名字 → `launch pin 2: no resolved target (...File Explorer.lnk), using the shell` + `ShellExecute -> 42` → 多出一个 `主文件夹 - 文件资源管理器` 窗口（和原生一样新开）。
  - **注意**：以前这里是 `ActivateWindow()`，配合 `clickActiveMinimizes` 会把已经在最前面的窗口最小化 —— 现在名字项不再走那条路。
- 悬停缩略图是 topmost 窗口，会盖住菜单：`WM_RBUTTONUP` 里先 `KillTimer(h,3)` + `ThumbHide()`，并且 `g_popupOpen` 期间定时器不再显示预览。
- 条上**空白处**右键仍是 dock 自己的菜单（设置/退出/开机自启…）。

**验证（02:08~02:10）**
- VSCode pin 右键：菜单列出 `打开 Visual Studio Code / 新窗口 / Agents Window / exp2 / common_workspace / ... / SRTP__`（截图 `dev/t_menu_code_menu.png`），与原生任务栏菜单一致。
- 点"打开" → `menu: ... cmd=1` + `launch pin 6: CreateProcess ok pid=15624`。
- 点"新窗口" → `menu: running task '新窗口' -> code.exe -n`。
- 资源管理器窗口项右键 → `打开 Windows Explorer` + `关闭窗口`（241x69，短标签生效）。

**没做的（后续可选）**
- "最近文件"：在 `AutomaticDestinations\*.automaticDestinations-ms`（这个才是 OLE 复合文档），但文件名是 **AUMID 的 CRC64 哈希**，要先取窗口的 AppUserModelID 再算哈希，标题还要解析 `DestList` 流。
- 资源管理器的"常用文件夹"：不是静态文件，是 shell 动态生成（Quick Access），要 `IShellFolder` 枚举。
- **AUMID → 文件名哈希没解出来**（2026-11-12 02:26 试过）：`dev/aumid.exe -hash <字符串>` 算了 6 种候选（CRC64 poly `0x04C11DB7` 正/反、`0x42F0E1EBA9EA3693`、`0xC96C5795D7870F42`，UTF-16LE/ANSI × 原样/小写），都对不上已知的 `1ced32d74a95c7bc`（VSCode）；而且本机大多数窗口 `PKEY_AppUserModel_ID` 是空的。所以现在用"按标题去重 + 最新文件优先"的启发式，不依赖哈希。

**待办 D**：宫格悬停显示**原生**提示（当前是自绘气泡 + 软件名）——原"待办 3"，内容不变：
1. 文本优先级：桥表 `szTip`（App 每次 `NIM_MODIFY` 都会更新，QQ 的状态文本就是这么来的）→ 拥有者窗口标题 `GetWindowText(ownerHwnd)` → 文件版本信息 `FileDescription` → exe 名；
2. 若要"原生外观"，用 `TOOLTIPS_CLASS`（`CreateWindowEx(TOOLTIPS_CLASS)` + `TTM_ADDTOOL` + `TTM_TRACKACTIVATE`）而不是自绘；
3. 桥表 `szTip` 可能含 `\r\n`（QQ 是四行），tooltip 多行同样可以；
4. 若某 App 的 tip 一直是空，先在 `bridgedump` 里确认它是否真的发过带 `NIF_TIP` 的 `NIM_MODIFY`，不要用 exe 名冒充。

**说明（用户 2026-11-11 23:40）**：原生托盘里有的图标右键后"鼠标移开菜单也不消失"、有的一移开就收（WorkBuddy vs QQ），这是 App 自己的实现差异，**不要**去对齐；我们只要保证"我们不主动收"。`^` 按钮目前仍是宫格开关（宫格开着时点它 = 收起宫格 + 关菜单），这是保留的既有行为，用户若要求改语义再说。

---

### 8.4 下一步（用户 2026-11-12 11:45 指定，按顺序做）

> 这两条都还没实现。实现前先把 §9 的偏好读一遍：**方向不明确先问**，改动小而可验证，一次只动一件事。

### 待办 D：快速闪避（双击条 → 对称跳到另一边）—— ✅ 2026-11-12 12:08 完成

**语义（用户原话整理）**
- 双击条（条本体，不是宫格）：条动画过渡到**沿屏幕中心线对称的另一边**。
  - 条"宽 > 高"（横向）→ 上下对称：`y' = wa.top + (wa.bottom - wa.top) - (y - wa.top) - h`，也就是 `y' = wa.top + wa.bottom - y - h`，x 不变；
  - 条"高 > 宽"（纵向）→ 左右对称：`x' = wa.left + wa.right - x - w`，y 不变；
  - 用**工作区**（`mi.rcWork`）而不是整块屏幕，并 clamp 在 `rcWork` 内（任务栏/dock 自身位置可能占掉边缘）。
- **动画**：一段短过渡（建议 220~280ms，`easeOutCubic` 或 `easeInOutQuad`），逐帧 `SetWindowPos`；不要瞬间跳。
- **过渡期间不透明度仍然跟光标距离走**：`UpdateAlpha()` 正常跑，不要在动画里锁 alpha、也不要因为"窗口在动"而改变淡入淡出逻辑。

**实现落点（`dock.cpp`）**
- **已确认（用户 2026-11-12 11:55）**：① 双击**图标不算**，只认条空白处的双击；② 闪避后**要把新位置写回** `dock.ini`（`SavePosition()`）。
- 双击识别：`DockStripWindow` 的 `WNDCLASSEXW` **没有 `CS_DBLCLKS`**，收不到 `WM_LBUTTONDBLCLK`。要么给类加 `wc.style = CS_DBLCLKS`（但要确认不影响现有的 `WM_LBUTTONDOWN/UP` 拖拽逻辑），要么自己在 `WM_LBUTTONUP` 里判：`now - g_lastClickAt <= GetDoubleClickTime()` 且位移 < 4px。**只认空白处**（用户已确认）：命中 `g_slots[i]` 的点击不参与双击判定。
- 动画：新增 `g_flip{active, t0, dur, from{RECT}, to{POINT}}`，用现有 30ms 定时器（`WM_TIMER` id=1）驱动即可（30ms 一步对 250ms 的动画够用；要更顺就单独开一个 `SetTimer(..., 8, ...)`）。
- **玻璃重抓**：`Present()` 用的是 `CaptureBackdrop()` 的 bake（每 300ms 或 `g_bakeDirty` 时重抓，见 §3.5）。动画期间**不要每帧重抓**（`PrintWindow` 太贵），做法：动画中只 `SetWindowPos` + 用上一帧 bake 画（会略有错位，可接受），**动画结束时** `g_bakeDirty = true` 重抓一次。
- 位置持久化：闪避后**写回** `dock.ini`（用户 2026-11-12 11:55 确认），调用现成的 `SavePosition()`。

**验收**
- 横向条：双击后落到 `wa.top + wa.bottom - y - h`，x 不变；再双击回到原位（对称两次 = 原位）。
- 纵向条：同理左右。
- 动画 250ms 左右、可见过渡；期间把光标移远/移近，透明度和原来一样变化。
- 双击图标**不**闪避。

**实际实现（2026-11-12 12:08 构建，`dock.cpp` 的 `// ---- dodge` 段）**
- 状态：`g_lastBlankClickAt / g_lastBlankClickPos`（双击判据）+ `g_flip{active,t0,dur=250,frames,fromX,fromY,toX,toY}`。
- `FlipTarget()`：`MonitorFromWindow` + `mi.rcWork`，宽>高镜像 y、高>宽镜像 x；**只 clamp 移动轴**。最初两轴都 clamp，结果把本机这条"比屏幕还宽"的条从左 535 拽到 451——横向闪避不该动 x，已改成单轴 clamp。
- `StartFlip()`：`SetTimer(g_hwnd, 4, 8, …)`；`FlipTick()` 用 `smoothstep`（`t²(3-2t)`）算位置，**只 `SetWindowPos`、不重绘**（分层窗口 surface 随窗口走；每帧重绘还要 `PrintWindow` 重抓玻璃，实测会把 250ms 拖成 313ms 且掉帧）。`WM_TIMER` 里 `wp==4` 和 `wp==1` 都调 `FlipTick()`（纯时间函数，重复调用无副作用；`wp==4` 分支一开始漏了，导致只有 30ms 定时器驱动、8 帧/297ms）。
- `FlipEnd()`：落到目标 → `g_cfg.x/y` 更新 → `SavePosition()` → `g_bakeDirty = true` → `PaintAndPresent()`；日志 `flip: landed (x,y) -> (x,y) after N ms in K frame(s)`。
- 动画期间 300ms 的实时玻璃重抓用 `!g_flip.active` 跳过；`UpdateAlpha()` 完全没改。
- 双击判据：`WM_LBUTTONUP` 里 `g_pressSlot < 0 && !g_pressHwnd && lnk.empty()`（空白）才算；`IsBlankDoubleClick()` 比对 `GetDoubleClickTime()` 与 4px 位移；点图标 / `^` / 开始拖拽都会把时间戳清零。**没有**加 `CS_DBLCLKS`（不想动现有 `WM_LBUTTONDOWN/UP` 拖拽语义）。
- 动画中按下左键 → `FlipEnd(L"grabbed mid-flight", false)`，停在原地并保存，不会和拖拽抢窗口。

**实测（`dev/t_flip.ps1`，PostMessage 双击左内边距）**
- `flip: double click on empty strip -> (451,290) to (451,679) over 250 ms` → `flip: landed (451,290) -> (451,679) after 297 ms in 23 frame(s)`；
- 再双击一次：`(451,679) -> (451,290) after 281 ms in 23 frame(s)`（对称两次回原位，x 全程 451 不变）；
- 内边距点 40,56 被识别成 `LBUTTONDOWN ... slot=-1`（空白），不会命中图标。
- **未由人手复核**：手感（250ms 的滑动看起来是否顺）、双屏、纵向条（本机配置是横向，没有改配置去测）。
- 注意：脚本用 `PostMessage` 注入时，如果真人正在动鼠标，`WM_MOUSEMOVE` 的"陈旧按下"判据会把第一次按下清掉（真实双击没这问题，物理按键位是按下状态），所以脚本带重试。

### 待办 E：吸附（贴边去圆角）—— ✅ 2026-11-12 12:46 完成

**语义（用户原话整理）**
- 条**较长的那条边**里，"更靠近屏幕的那一边"与屏幕边界相接（**包括超出边界**）时，**去掉该边的圆角**；另一边不受影响（两个角变直角）。
- **不限制用户拖动**：贴边/越界照样能拖走；一旦那条边重新进入屏幕（严格在边界内），圆角恢复。
- 尽量做得**灵动**（建议把圆角半径做 120ms 的缓动，而不是瞬间 0/满）。
- 吸附状态下双击 → 与待办 D 完全一致的闪避。

**实现落点**
- 现在的圆角是**单一半径**：`RadiusFor(w,h)` → 用在 `FillRound()`（玻璃本体，~L1482）、`EdgeAt()`（缩放热区，~L1413）、`g_bgWnd` 的 `CreateRoundRectRgn`（~L4169）。
- 要按角区分，需要把"半径"变成**四角数组**（`int r[4]`：左上/右上/左下/右下），并：
  1. `FillRound()` 改成按角绘制（可以用 4 个圆角矩形拼，或者逐像素用"角半径"算 alpha）；
  2. `g_bgWnd` 的 `CreateRoundRectRgn` 换成 `CreateRoundRectRgn` 不行（只支持统一半径）→ 用 `ExtCreateRegion` 或者干脆用两个矩形 + 两个圆角矩形 `CombineRgn`；
  3. `EdgeAt()` 的圆角轮廓判定同步用新半径（否则贴边后缩放热区对不上）。
- 判定：横向条看 `y <= wa.top`（上边贴/越界）→ 上两角 0；`y + h >= wa.bottom` → 下两角 0。纵向条看左/右。**用 `rcWork`**，且要注意 §5 坑 19（任务栏隐藏时 rect 在屏幕外，别拿任务栏矩形当边界）。
- 灵动：动画量 `g_cornerAnim[4]`（0~1）× `RadiusFor()`，在定时器里缓动到目标值，`Paint` 时用插值后的半径。
- 拖动路径：`WM_LBUTTONDOWN` 的拖拽分支里已经在 `WM_MOUSEMOVE` 移动窗口；在那里顺带更新吸附状态即可（不要另起逻辑）。

**验收**
- 把条拖到工作区上边缘（包括越出）→ 上面两角变直角、下面两角仍是圆的；拖回来 → 恢复；
- 拖到屏幕外再拖回来，全程不被"卡住"；
- 贴边状态下双击 → 正常闪避到另一边，落地后圆角按新的贴边情况重新判定。

**实际实现（2026-11-12 12:46 构建）**
- 圆角从"单一半径"改成**四角系数**：`g_cornerAnim[4] / g_cornerTarget[4]`（TL, TR, BL, BR，1 = 配置半径、0 = 直角），`CornerIndex()` 按像素落在哪个象限选角，`CornerRadiusAt()` 给出该像素的半径。
- 生效位置：
  1. `Paint()` 的玻璃本体：逐像素 `rr = radius * g_cornerAnim[corner]`（原来一个 `rr` 算到底）；子像素覆盖率/边缘高光不变，所以贴边后那条边是干净的直角而不是硬切。
  2. `EdgeAt()`（缩放热区）：用**该点所在角**的半径，贴着圆角轮廓判定，贴边后热区跟着变成直角。
  3. 纯色材质（`material=0`）走新加的 `FillRound4()`（逐角半径版 `FillRound`）。
  4. `SyncBackground()`（`g_bgWnd` 的 `CreateRoundRectRgn`）**是死代码**：全文件没人调用它，`g_bgWnd` 从来没被创建，所以没改；真要启用它得先把区域改成按角构造。
- 判定 `UpdateSnap()`：宽>高看上下边、高>宽看左右边，`wr.top <= wa.top` / `wr.bottom >= wa.bottom`（越界也算）→ 对应两角目标 0，否则 1；用 `rcWork`（不是整块屏幕），和坑 19 一致。
- 触发：30ms 定时器里每拍 `UpdateSnap()` + `AnimateCorners()`（指数缓动，约 120ms 收敛，`1-exp(-dt/45)`）；拖动分支 `WM_MOUSEMOVE` 里移动窗口后立刻 `UpdateSnap()`，缩放分支同理——不另起一套逻辑。
- 动画期间只有角系数变了才重绘（`if (AnimateCorners() && !g_flip.active) PaintAndPresent()`），飞行中不重绘（闪避那边有同样的理由）。
- 拖动**不做任何限制**：没有任何 clamp，贴边/越界照样拖走。
- 日志：`snap: corners TL=.. TR=.. BL=.. BR=.. rect=.. work=..`，只在目标变化时打一条。

**证据（`dev/t_snap.ps1` / `dev/t_snapflip.ps1`，2026-11-12 12:47）**
- 目标切换：`TL=0 TR=0`（rect=40,0-1509,111）、`BL=0 BR=0`（rect=40,969-1509,1080）、离边恢复 `TL=1 TR=1 BL=1 BR=1`。
- 屏幕像素对照（条宽 1469、半径 77）：顶边时 `TL=6b6b6b`（玻璃）、`BL=1b1b1c`（背景透出来）；底边时反过来 `BL=6c6d6f`、`TL=20242e`；完全离边时四角都是背景色 → 直角/圆角的可见差异成立。
- 吸附 + 闪避：条停在顶边（`TL=0 TR=0`）→ 双击空白 → 飞行中角恢复全 1 → 落地 `(40,969)` 且 `BL=0 BR=0`（`flip: landed (40,0) -> (40,969) after 297 ms in 22 frame(s)`）。
- 未由人手复核：缓动手感（120ms 是否"灵动"）、拖拽时角跟着手指走的感觉。

## 9. 用户的工作习惯（很重要，按这些来配合他）

### 9.1 怎么跟他沟通
- **有歧义先问，别猜。** 他的提示词经常一句里有多个语义（例如"托盘"有时指条、有时指宫格；"点外面"可能指"弹起菜单前的前台"）。把不确定的点列成选择题问，他答得很快，也明确表示过"不要自己猜，很容易偏离目标"。
- **要结论也要证据。** 不接受"看起来好了"：给日志行、截图、或实测数字（如"122/123/125 ms"）。他会被"看起来修好了其实没修"折磨，所以每次改完都要自己先验证。
- **先给可行性与代价，再动手。** 涉及外部依赖（Windows API 有没有、Windhawk 能不能做）时，先做侦察/实测，把"能做/不能做/代价"讲清楚，再让他拍板。
- **绕路必须先讲代价。** 他反感别扭的变通（为了给菜单让位而收起宫格、让任务栏闪一下、假装成功之类）。宁可承认做不到。
- **风险决定留给他。** 例如"要不要全局打开 Windhawk 的注入游戏/不兼容程序"——我的职责是说清副作用（反作弊风险、可能崩），由他决定；他这次选了"保持现状"。
- **他说"回答即可/记录即可"时不要动手改代码**（例如 2026-11-12 11:55：两个答案只是记录，留给下一个会话做）。
- 他会在结尾说"今天先停工/继续"——**按他的节奏收尾**，收尾时把状态写进本文档。

### 9.2 怎么干活
- **一次只动一件事，改动小而可验证。** 大改先拆步骤，每步都能编译+验证。
- **能自己验证的绝不推给他**：编译、启动、截图、读日志、跑脚本都自己做。只有需要**重启系统 / 在 Windhawk UI 点按钮 / 需要管理员 / 需要他肉身操作**时才交给他，并且把操作写成一步一条。
- **不要为了展示能力做无谓改动**；界面/行为要"像原生"（例如条上菜单的标题、圆角、缩略图层次）。
- **测试要闭环**：条上有滚动时按几何算槽位会错，改用 `hover -> N` 日志闭环（`t_slotpick.ps1`）；注入鼠标前先 `Wait-Idle` 等他手离开鼠标。
- **绝对别乱点**：他机器上的 Legion Zone 菜单关不掉、某些 App 会被误启动。要测"点菜单项"这类操作，用合成托盘图标（`traytest.ps1`），别碰真 App。

### 9.3 他的环境与约束
- 他会**同时使用电脑**（写 PPT、聊天），注入鼠标会和他的手抢；测试要么等他空闲，要么接受结果被污染并靠日志甄别。
- 显示器休眠/输出暂停时 `CopyFromScreen` 会返回**旧帧**，截图不能当证据；改用窗口状态（`wins2.ps1`）+ 日志。
- 沙盒历史上禁过 `SetCursorPos`（err=5）；现在 `danger-full-access` 可用，但脚本仍要能降级到 `mouse_event` 绝对坐标。
- 他的 PowerShell 5.1 **读 UTF-8 无 BOM 的中文脚本会解析失败**；给脚本写中文一定带 BOM（`python` 写文件时前置 `﻿`）。

## 10. 未验证 / 已知未完成（交接时务必核对）

1. **`AllowSetForegroundWindow(ASFW_ANY)` + "fg 为空先激活 App 窗口" + 300ms 重投** —— ✅ 用户 2026-11-11 22:00 前确认。
2. **托盘表现在 15 条**（PowerToys / 安全中心 / WorkBuddy Manager / 网易UU远程 / DeskPad / QQ助手 / DeepSeek / Radmin LAN / Windhawk / QQ×2 / Legion Zone / UU加速器 / Steam / Wallpaper Engine）。会随 App 启停小幅波动，属正常；「重新扫描托盘」可让仍持有 mod 的进程重注册。
3. **32 位 mod 已安装并启用**（2026-11-12 10:35）：Radmin、Windhawk 的图标已回来。**启用或重编译任何 mod 都会让 Windhawk 卸载已注入进程里的模块（不会重注入）** → 表现为"某些图标突然消失"，广播 `TaskbarCreated` 能救回仍持有模块的，否则要重启那个 App/系统。
4. **任务栏 mod**：源码已改成"纯 Win 开关、无任何宽限"并部署到 `ModsSource`，用户是否编译这一版**未确认**。验证：按 Win 弹出 → 再按 Win 收起 → 立刻把鼠标贴到屏幕底边，任务栏不应出现。
5. **Legion Zone 的菜单关不掉**（提权），测试时尽量别右键它的格子。
6. **本次会话的自动测试覆盖**：状态机 2a/2b-i/2b-iii/3a/3b-i/3c-iii/失焦、宫格左键转发（合成托盘图标 + WorkBuddy + QQ）、条上菜单（VSCode tasks / Explorer 名字项 / 关窗口项）、托盘宽限期、重新扫描托盘。**手感类**（动画、闪烁、连续操作）历来只能由用户确认。
7. **待办 D（快速闪避）✅ 2026-11-12 12:08 已完成**（证据见 §8.4）；**待办 E（吸附 / 贴边去圆角）✅ 2026-11-12 12:46 已完成**（证据同样在 §8.4）。
8. **一次未复现的崩溃**（2026-11-12 12:42:12）：`dock.exe` 0xc0000005，故障偏移 `0x11fe0`（WER 有 APPCRASH 记录）。当时测试脚本刚把条从 1469x111 改成 111x800，命中时日志停在一条 `paint: glass ...` 之后。之后按"改尺寸 → 等 → 复原"和"改尺寸 → 注入点击 → 复原"各跑 3 次都没再崩，`grid`/`snap`/`flip` 三条新路径也都没再触发。**留意是否复发**；若复发，先把 `build.ps1` 加 `/Zi`（生成 pdb）再抓 WER dump。
