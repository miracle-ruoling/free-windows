# Dock 项目交接文档（2026-11-10 深夜重写，2026-11-11 凌晨更新）

> 读者：接手的新会话 AI + 用户本人。
> **最重要的一条：语义模型在第 1 节，读之前先看它——之前十几轮反复改错，全部源于把"条"和"宫格"的职责搞混。**

---

## 0. 一句话现状

一个 C++ Windows 桌面图标条（`dock.exe`）+ 两个 Windhawk mod。
玻璃模糊、`^` 宫格、悬停放大、开机自启、**托盘原生右键菜单（四个 App 实测通）** 都已实现并验证。
**2026-11-11 凌晨这一轮把三个 P0 全修了，并顺带查出右键菜单"打不开"的真正根因（见 4.4）。**
只剩一件需要用户动手的事：**Windhawk 里重新编译 tray-icons-bridge**（见 9）。

---

## 1. 语义模型（先读这个！）

用户对标的对象非常明确：

| 我们的东西 | 对标 Windows 的 | 内容 | 不该出现的东西 |
|---|---|---|---|
| **图标条**（那一条 pill） | **任务栏**（taskbar） | 固定项 + 有任务栏按钮的窗口；超出宽度靠**滚轮**翻页 | 只有托盘图标、没有任务栏按钮的后台程序 |
| **宫格**（点 `^` 弹出） | **系统原生托盘**（notification area） | **只**放原生托盘里的图标（全集） | 图标条上的任何东西都**不该**排除在宫格之外；宫格不显示窗口项 |

**2026-11-10 的两条实证（本轮查清，务必按这个修）**

1. **图标条多出了 UU远程**：
   - 我们读的是 `%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\*.lnk` 这个**文件夹**；
   - 但真正的"任务栏固定项"列表在注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband` 的 **`Favorites`（REG_BINARY，UTF-16 里嵌着 .lnk 路径）**；
   - 实测：文件夹里有 `网易UU远程.lnk`（用户早就在任务栏取消了固定，lnk 残留），而 `Favorites` 里**没有** UU → 所以真实任务栏没有它，而我们的条有它。
   - **修法**：只认 `Favorites` 里出现过的 .lnk（二进制按 UTF-16 解码，搜 `xxx.lnk` 子串），不要直接用文件夹内容。
2. **宫格漏了 WorkBuddy / Clash / QQ 等**：
   - 原生托盘里**有**它们（有后台托盘图标），图标条里也有（有窗口）；
   - 我上一轮在 `BuildTrayFromBridge()` 里加了"exe 已在图标条上就跳过"的**去重**（`onStripSkip`），把它们滤掉了；
   - **修法**：删掉那段去重。宫格 = 原生托盘**全集**（两者重叠是正常的，Windows 本身就重叠）。

> 用户原话："图标条对标任务栏，托盘（宫格）对标系统原生托盘"。
> 上一个会话在这上面翻车两次：先做"全量合并"，又做"去重"，两个方向都错。
> 判断标准永远是：**任务栏有没有它** / **原生托盘有没有它**，而不是"两者会不会重复"。

### Windows 到底限制了什么（避免下次再甩锅）

| 想要的 | 可行性 | 说明 |
|---|---|---|
| 枚举任务栏按钮 | ❌ 无公开 API | Win11 是 XAML 任务栏，`Shell_TrayWnd` 下**没有** `ToolbarWindow32`/`MSTaskListWClass`；UIA 全桌面只返回浏览器的 21 个按钮。只能**按窗口启发式**近似（规则见下） |
| 枚举 / 点击托盘图标 | ✅ 已解决 | 靠 Windhawk mod hook `Shell_NotifyIconW`（见 4.3）。注意：这个函数**在 App 自己的进程里执行**，hook explorer 无效 |
| 固定项列表 | ✅ 有权威来源 | `Taskband\Favorites` 注册表 |

任务栏按钮的近似规则（照抄 shell 的判定，比现在的 `IsCandidate()` 更准）：
```
可见 && 未被 cloak &&
((WS_EX_APPWINDOW) || (!WS_EX_TOOLWINDOW && 无 owner))
```
当前 `IsCandidate()` 的偏差：**没有** `WS_EX_APPWINDOW` 覆盖（工具窗+APPWINDOW 会被错误排除）、**额外要求**有窗口标题、**无条件**排除有 owner 的窗口。改的时候按上面四条对照。

---

## 2. 路径与构建

| 项目 | 路径 |
|---|---|
| 源码 | `C:\Users\20979\RP_Projects\common_workspace\dock\dock.cpp`（单文件，约 4400 行） |
| 构建 | 同目录 `build.ps1`（cl.exe 直调 + 自动部署 + 哈希校验） |
| 安装 / 运行位置 | `C:\Users\20979\AppData\Local\Programs\Dock\dock.exe` |
| 运行配置 / 日志 | 同目录 `dock.ini` / `dock.log` |
| 开机自启 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Dock.lnk`（右键菜单"开机自启"可开关） |
| Windhawk mod 1 | `windhawk\taskbar-hidden-until-win.wh.cpp` → 任务栏只在按 Win 时出现 |
| Windhawk mod 2 | `windhawk\tray-icons-bridge.wh.cpp`（v3）→ 托盘桥，见 4.3 |
| mod 源码安装位（Windhawk 读这里） | `C:\ProgramData\Windhawk\ModsSource\local@<id>.wh.cpp` |
| mod 编译产物 | `C:\ProgramData\Windhawk\Engine\Mods\64\local@<id>_<ver>_<hash>.dll` |
| 调试脚本 | `dock\dev\*.ps1` / `dev\*.cpp`（见第 8 节） |
| 工具链 | MSVC `C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231`；SDK `D:\Windows Kits\10`（10.0.26100.0）；build.ps1 已写死 |

构建 / 部署流程（**顺序不能错**）：
```powershell
cd C:\Users\20979\RP_Projects\common_workspace\dock
Get-Process dock -ErrorAction SilentlyContinue | Stop-Process -Force   # 必须先杀
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
Start-Process "$env:LOCALAPPDATA\Programs\Dock\dock.exe"
```

mod 改动流程：改 `windhawk\tray-icons-bridge.wh.cpp`
→ 语法检查 `powershell -File windhawk\stub\check.ps1 -Src "..\tray-icons-bridge.wh.cpp"`
→ 复制到 `C:\ProgramData\Windhawk\ModsSource\local@tray-icons-bridge.wh.cpp`
→ **用户必须在 Windhawk 界面点"编译" + 启用**（本机没有 windhawk-cli，无法自动化）。

---

## 3. Bug 状态（2026-11-11 凌晨）

### P0-1 图标条显示了任务栏没有的东西（UU远程）—— 已修
- 根因：`BuildItems()` 用**文件夹**（`User Pinned\TaskBar\*.lnk`）当固定项来源；`网易UU远程.lnk` 是用户早就在任务栏取消固定后留下的残留。
- 修法：新增 `PinnedLnkListed()`，读 `HKCU\...\Explorer\Taskband\Favorites`（REG_BINARY），只保留文件名出现在其中的 lnk。
- **坑**：这个 blob 里各条目的结构**不是 2 字节对齐的**。只按 UTF-16 从偏移 0 解码，能搜到 `Microsoft Edge / Visual Studio Code / QQ`；从偏移 1 解码才能搜到 `File Explorer / Clash Verge / EchoMusic`。所以必须两种对齐都解一遍再匹配（`views` 数组）。
- 实测日志：`pins: Taskband\Favorites = 2235 bytes, 2 decode views` / `pin skip (leftover, not in Taskband\Favorites): 网易UU远程.lnk` / `pins: 6 from the pinned folder, 1 skipped`。

### P0-2 宫格漏了原生托盘里有的图标（WorkBuddy / QQ / DeepSeek）—— 已修
- 根因：`BuildTrayFromBridge()` 里"已在条上就跳过"（`onStripSkip`）的去重。
- 修法：整段删掉。宫格 = 原生托盘全集，和条重叠是正常的。
- 实测：`tray: 9 icons from the bridge (live tray, full native set)`，`grid: ... 9 dock + 9 tray`，WorkBuddy Manager / QQ / DeepSeek 都在。
- 顺带修：桥表里同一个 App 可能出现**多条**（QQ 有两个进程各注册一次，其中一条 `cbMsg=0`）。旧代码"先出现者胜"，会选中没有回调的那条 → 右键没反应。现在合并重复项时优先保留**有 cbMsg 的那条**（日志 `tray: '%s' duplicate upgraded to ...`）。

### P0-3 图标条窗口项与真实任务栏不一致 —— 已改（当前集合行为等价，但覆盖两个以前漏掉的情况）
- `IsCandidate()` 现在就是 shell 规则：`visible && !cloaked && (WS_EX_APPWINDOW || (!WS_EX_TOOLWINDOW && 无 owner))`，**不再要求有标题**。
- 没有标题的窗口用 `WindowLabel()` 兜底显示 exe 名。
- 用 `dev/winstyle.exe`（合成两个窗口：`TOOLWINDOW|APPWINDOW` 有标题；无扩展风格且**无标题**）验证：旧规则两个都不显示，新规则两个都上条，无标题那个显示为 `winstyle.exe`（日志 `items=11`，关掉后回到 `items=9`）。
- 注意：本机当前窗口集合下新旧规则结果**完全相同**（5 个候选），所以这次改动是"更贴近 shell / 覆盖边角"，不是看得见的变化。

### P1 托盘右键菜单 —— 已修（真根因不是 cbMsg！）
- **真根因：只投递了 `WM_RBUTTONUP`。** QQ（Electron `Electron_NotifyIconHostWindow`）和网易UU（Qt `Qt51519QWindowPopupSaveBits`）都只在**按下+抬起**这一对消息下才弹菜单，只给抬起会被忽略。
  - 证据（`dev/qqmenu.ps1` 单变量矩阵，直接往 App 的托盘窗口投递）：
    - QQ：`UP → 0 个窗口`，`DOWN+UP → 1 个窗口`（183x620 游戏菜单）
    - UU：`UP → 0`，`DOWN+UP → 1 个 Qt 弹窗 158x190`
    - `CONTEXTMENU / LBUTTONUP / UP x2 / uid=1` 全部 0。
  - 修法：`GridProc` 右键分支改成 `PostMessage(WM_RBUTTONDOWN)` + `PostMessage(WM_RBUTTONUP)`。
- 菜单**识别**修了两处：
  1. 旧实现是"右键前后新增的可见窗口"。WPF（Legion Zone）的弹窗是**一个长期存在的 HWND**，显示/隐藏复用，于是永远不算"新窗口" → 误判"没有菜单"。现在额外接受"该 pid 的、盖住光标的、无标题栏的弹窗"（`MenuLikeWindow()`）。
  2. 找到菜单后**记住那个 HWND**（`g_menuHwnd`），不再每帧重新推导。否则光标一移到菜单上，条件变化就会误判成"菜单消失了"。
- 菜单**关闭**跟原生对齐（用户 2026-11-11 明确要求）：**点菜单外面才关，光移开不关**。
  - 光标离开条/宫格/菜单 0.6s → 只收宫格，菜留给 App；
  - `MenuWatchTick()` 检测真实按键（`GetAsyncKeyState` 低位，我们自己 Post 的消息不会触发），落点在菜单外 → `CloseMenuWindows()`（`WM_CANCELMODE` + `Esc` + **`WM_ACTIVATE(WA_INACTIVE)` + `WM_KILLFOCUS`**；Electron/Qt/WPF 弹窗都是非激活窗口，前三个对它无效，靠"失焦"才关）。
  - **不要**试"再投一次托盘消息"来关：对 Legion Zone 那种"再点一次图标就又摊开"的实现，只会把菜单重新弹出来（实测踩过）。
- 实测（全部用 `dev/gridrc.ps1` 走真实鼠标点击，截图对比）：

  | App | 打开 | 移开光标 | 点菜单外面 |
  |---|---|---|---|
  | QQ (Electron) | 原生菜单 | 留着（原生行为） | 关（App 自己响应，我们兜底） |
  | 网易UU远程 (Qt) | 原生菜单 | 留着 | 关（日志 `click outside the menu -> closing it`） |
  | DeskPad (Tk) | 原生菜单 | 留着 | 关 |
  | Legion Zone (LZTray / WPF，**提权**) | 原生菜单 | 留着 | **关不掉**（见下） |

- **第二轮修复（用户报"第一次正常、第二次失效"）**：
  - 现象：QQ 第二次右键 → 图标条 + 宫格瞬间消失、没有菜单；WorkBuddy 第二次右键 → 什么都不发生。
  - 根因：App 用 `NIM_MODIFY` 重注册时会传 `uCallbackMessage = 0`，**当前编译的 mod 还是旧 DLL**（源码里的保留逻辑没进二进制），于是桥表里那条记录变成 `cbMsg=0` → `hasBridge=false` → 右键走"没有回调"分支 → 旧代码直接 `GridHide()`（= 瞬间消失）。
  - 修法（客户端兜底，不依赖重编译）：`g_trayCbCache`（exe → 最后一次可用的 `{hwnd, uid, msg}`）。桥表给的回调为空时，若缓存的窗口还活着（`IsWindow`）就复用，并记日志 `came back without a callback - reusing the last good one`。
  - 另外：右键一个**确实没有回调**的托盘图标时不再收起宫格（真托盘也是"什么都不发生"），只记一条 `right click on '<tip>' ignored (no callback message)`。
  - 实测：连续 3 次右键 QQ，每次都能弹菜单（`loop3.png`）。
- **WorkBuddy 没有右键菜单**（2026-11-11 实测，与本项目无关）：`workbuddy.exe`（Electron，pid 10720）只认左键（会打开主窗口）；`UP / DOWN+UP / LBUTTONUP / CONTEXTMENU / NIN_SELECT / uid=1` 全都没有任何窗口出现。所以它在宫格里右键"没反应"是 App 本身如此，不是 dock 的 bug。
- **第三轮（2026-11-11 01:30 之后）**：
  - **长菜单跑出屏幕**：QQ 的菜单 183x620，我们的宫格不在底部时会向上弹出到屏幕外。现在 `MenuGeom` 按 exe 记住"菜单相对光标的偏移 + 尺寸"，右键前先用 `ClampMenuCursor()` 把光标挪到能让菜单落进工作区的位置（留 8px 边）；第一次不知道尺寸时，看到菜单若出界就关掉、挪光标、重新投递一次（日志 `menu %ldx%ld at .. is off screen -> reopening at ..`）。实测 QQ 菜单完整显示。
  - **DeepSeek Harness 的右键菜单其实是好的**（`DOWN+UP` 能出 `打开/退出 DeepSeek Harness`）；用户看到的"没菜单"是点到了别的格子（宫格列数会随图标数量变：9 个=3 列、10 个=4 列）。
  - **宫格少图标**（Radmin / Windhawk / Wallpaper Engine）：
    - 32 位进程根本没有 mod 可用：`C:\ProgramData\Windhawk\Engine\Mods\` 里**没有** tray-icons-bridge 的 DLL（源码 22:37 之后没编译过，Mods/64 的 DLL 还是 18:05）。`windhawk.exe`、Radmin VPN 都是 x86 → 必须重新编译一次（源码里 `@architecture x86,x86-64` 已经写好）。
    - `wallpaper64.exe`（x64）**没被注入**：`Engine\ModsWritable\mod-status` 里没有它的记录（其它 64 位 App 都有）。它是在 Windhawk 引擎就绪之前启动的 → **重启这个 App** 就会进表。验证方法：`ls Engine/ModsWritable/mod-status | grep _<pid>_`。
- **已知限制（Legion Zone）**：`LZTray.exe` 是**提权运行**的（`taskkill` 都被拒绝）。它的 WPF 弹窗把关闭类消息全过滤了（`WM_CLOSE` 直接返回 `False`+`err=5`），Esc / 失焦 / 点击都无效，所以我们的"关菜单"对它无能为力；菜单会留在屏幕上，只能由它自己/用户点某个条目结束。要彻底解决需要 dock 也提权（不建议：改变整个进程的安全上下文）。
- 用户明确否掉了"召唤任务栏 + 真实右键"的方案，别再提；若真要试，先问代价。

### 托盘右键"我点有、你点没有"：前台窗口为空（2026-11-11 深夜）
- 同一格子、同一 hwnd、同一消息，脚本注入点击出菜单，真实鼠标点击不出。逐条比对日志后唯一的差别：
  - 成功样本：`fg=…(Chrome_WidgetWin_1)`（有前台窗口）
  - 失败样本：`fg=0000000000000000()`（**当前没有前台窗口**）
- 解释：Electron 的托盘菜单在显示前会 `SetForegroundWindow` 自己的窗口；没有前台窗口时，非前台进程这个调用会被系统拒绝 → 菜单不出现（QQ 走的不是这条路径，所以一直正常）。
- 修法（三条，互不冲突）：
  1. 投递前 `AllowSetForegroundWindow(ASFW_ANY)`——把"设置前台"的许可让给下一个调用者（真实托盘点击时是 shell 持有前台，效果相同）；
  2. `GetForegroundWindow()==NULL` 时，先 `SetForegroundWindow` 该 App 的一个可见顶层窗口（日志 `tray: no foreground window - activated …`）；
  3. 300ms 内没检测到菜单就**自动重投一次**（日志 `forwarding the click once more`）。
- 另外两个会"吃了点击"的问题也修了：
  - 宫格打开后 400ms 的重读会重建并按 tip 重排序，图标在光标下跳位 → 现在**打开期间绝不重建**，新图标下次打开才出现；
  - 合成的 DOWN/UP 原来零间隔（等于"零时长点击"），现在 UP 延迟 70ms（日志 `right click up -> … after 78 ms`）。
- 诊断增强：每次右键都记 `cell N -> tray[N] 'tip' (exe) bridge= owner= cls= post=err= fg= cursor=`；"没菜单"时还会 dump 该进程所有可见窗口、光标下窗口、面板 topmost 状态。
- 注意：`tray[0..N]` 日志是**排序前**的顺序，格子是排序后的——对不上是正常的，别再看错（我自己错过一次）。

### 共享块 DACL：重启后"所有右键都没反应"的真凶（2026-11-11 晚）
- 现象：重启后宫格图标看着差不多，但**每个图标右键都没反应**；还会混进 `explorer.exe`、QQ 启动器之类的条目。
- 原因链：
  1. 共享块 `Local\DockTrayBridge_v1` 由**第一个加载 mod 的进程**创建，DACL 也由它决定。开机时第一个通常是**提权的联想组件**（`LZTray`/`SmartEngineTray` 那一批）→ 块带着高完整性 DACL；
  2. dock 是中等权限，`OpenFileMapping` 直接 `ERROR_ACCESS_DENIED(5)`（`bridgedump` 也能看到 `no mapping (err 5)`）；
  3. dock 于是**静默退回注册表历史**（`NotifyIconSettings`，63 条里 15 条"exe 在跑"），这些条目**没有回调消息** → 右键一律 `ignored (no callback message)`；而且注册表对同一 App 只有一条记录（QQ 两个进程共用 UID=3）→ 永远只有一个 QQ，且可能是启动器。
- 修法（两侧都要）：
  - **mod**：`BridgeSA()` 用 NULL DACL 创建 mapping 和 mutex —— 谁先创建都人人可读；
  - **dock**：启动时自己也创建（同样 NULL DACL）并**一直持有句柄**：即使 mod 版本旧、只要 dock 先创建就没问题；同时块不会再因为 Windhawk 重载 mod 而消失（连带解决"重编译就丢图标"）。
  - dock 打日志：`tray: bridge block available / NOT available (err=5)`、`bridge mapping exists but access was DENIED (error 5)`。

### 空表不再直接走兜底（顺序 bug）
- 旧代码 `if (count <= 0) return false;` 在"广播 TaskbarCreated"**之前**，所以表被重建为空时永远不会触发刷新，只能靠注册表兜底 → 表现为"重编译/重启后图标没了且点不动"。
- 现在先判断"要不要广播"（`count <= 2` 或比上次少，限流 5s），再决定是否兜底；广播后 400ms 一次性重读，如果宫格开着就直接重建并重绘（`tray: refreshed the open panel -> N icons`）。

### 表被重建后图标消失：改用磁盘快照，而不是轮询（2026-11-11）
- 现象：宫格里的图标"越用越少"（UU / WorkBuddy Manager / DeskPad / QQ助手 的进程都在跑，但不在表里）。
- 原因：共享表 `Local\DockTrayBridge_v1` 只要**还有一个进程持有映射**就存在；Windhawk 重新编译/重载 mod 会让所有实例卸载 → 表消失 → 再建是空的。已经在运行的 App 不会自己重报（只有响应 `TaskbarCreated` 的会），于是它们的图标就一直缺到 App 重启为止。
- 修法（无轮询）：
  - mod 在 `Wh_ModBeforeUninit()` 把整个表写到 `%LOCALAPPDATA%\DockTrayBridge.bin`；
  - 谁创建了新表（`first == true`）就在 `RestoreSnapshot()` 里把快照读回来，**顺手过滤**进程已死（`ProcessAlive`）和窗口已失效（`IsWindow`）的条目；
  - 每次创建表只会恢复一次，不是周期性行为。
- 代价：这次已经丢掉的 4 个图标，需要重启对应 App（或重启机器）才会回来；之后不论重编译多少次都不会再丢。
- dock 侧保持不变：只在打开宫格时读表，数量可疑才广播一次 + 400ms 后一次性重读。

### 托盘刷新：只在"打开宫格"时检查，不做周期轮询（2026-11-11 用户要求）
- mod 里原本每 2.5s 自愈的 `KeepAliveThread` 已**删除**（用户明确不要周期性检测）。
- dock 侧：`BuildTrayFromBridge()` 只在打开宫格时读表；如果读到的数量可疑（`count <= 2` 或比上次少）才广播 `TaskbarCreated`，并设置 `g_trayRetryAt = now + 400`；30ms 定时器里只做**一次**重读（`g_trayRetryAt` 清空后不再触发）。
- 日志：`tray: bridge has N icon(s) (last time M) - asking apps to re-register` / `tray: re-read after refresh -> N icons`。
- 效果：平时完全不碰托盘；打开宫格时如果表是空的/变短了，会自动补齐并当场刷新。

### Windhawk 只支持**单架构**（2026-11-11 踩）
- `@architecture x86,x86-64` 会编译失败：`Mod architecture must be one of x86, x86-64, amd64, arm64`。
- 现在 `tray-icons-bridge` 是 `x86-64`；另存了一份 `windhawk/tray-icons-bridge-x86.wh.cpp`（`@id tray-icons-bridge-x86`、`@architecture x86`），两者写同一块共享内存，可同时启用 —— 32 位 App（Windhawk 自己的 UI、Radmin VPN）需要它。
- 后果：注册表兜底路径（见下）在 mod 关掉时会被启用。

### 注册表兜底路径（桥不可用时的丑陋后备）
- 关掉 `tray-icons-bridge` 后宫格会"变多"：dock 改读 `HKCU\Control Panel\NotifyIconSettings`（本机 63 条历史记录），只保留 exe 正在运行的 → 15 条，于是 Edge / 文件资源管理器 / NVIDIA 这些**有进程没图标**的也被列出来（日志 `tray: the bridge table is EMPTY - is tray-icons-bridge disabled?` / `15 live of 63 recorded`）。
- 这个路径**没有回调消息**，右键一律 `right click on '<tip>' ignored (no callback message)`；而且 Windows 对同一个 App 只存**一条**记录（QQ 两个进程共用 UID=3），所以第二个 QQ **不可能**从注册表里补出来。
- 结论：宫格必须有桥。兜底只保证"桥没起来时不是空的"。

### 桥表合并键：从 (exe, tip) 改成 (exe, 窗口句柄, 图标ID)
- 原来两个 QQ 进程的图标会因为 tip 相同被合成一个。现在同一进程的同一图标才算重复；两个账号两个进程 → 两张图标。

### 32 位编译：`EnumWindows` 的 lambda 不行（2026-11-11）
- Windhawk 用 clang + i686：`EnumWindows([](HWND,LPARAM){...}, x)` 报 `no matching function for call to 'EnumWindows'`，因为 32 位下回调必须是 `__attribute__((stdcall))`，而 lambda 的 `operator()` 没法加这个属性。
- 修法：改成自由函数 `static BOOL CALLBACK PostTaskbarCreated(HWND, LPARAM)` 再 `EnumWindows(&PostTaskbarCreated, ...)`。MSVC 的 x64/x86 都能过（`windhawk/stub/check.ps1`、`stub/check86.ps1`）。

### mod 重载后图标消失：共享表被重建，App 不会自己重报
- 现象（用户报）：重新编译 mod 后，宫格只剩 NVIDIA + 一个 QQ。
- 原因：mod 重载时 `Local\DockTrayBridge_v1` 被销毁再建（空表）；已经在运行的 App 只有在 shell 广播 `TaskbarCreated` 时才会重新 `NIM_ADD`，很多 App 根本不响应。
- 两处自愈：
  1. **mod 内**：每个进程记住自己写过的条目（`g_mine`），`KeepAliveThread` 每 2.5s 检查表里还在不在，缺了就补回去（窗口还活着才补）。日志 `re-applied a tray entry after a table reset`。这让"重编译/重载"不再丢图标。
  2. **dock 内**：`BuildTrayFromBridge()` 发现表里 ≤2 条时限流 15s 广播一次 `TaskbarCreated`（`StartTrayWarmup(0)`），日志 `only N icon(s) in the bridge - asking the apps to re-register`。
- 注意：正在运行的进程加载的还是**旧 DLL**，所以新代码要等这些 App 重启（或重启系统）后才生效。

### 任务栏"按 Win 不出来"：可见性判断写错了
- 隐藏状态的任务栏 rect 是 `y=1077..1137`（屏幕 1080 高），旧判断 `rect.bottom >= monitor.bottom - 2` **永远为真**，于是 Win 键走到"已经在屏幕上 → 收起"的分支，任务栏不出现；只有把鼠标放到底边（悬停触发 Unhide，且 Win 键正按着）才会出现。
- 修法：改成算"与显示器矩形的重叠高度 > 8px"才算可见。

### 任务栏 mod（`taskbar-hidden-until-win`）—— 纯 Win 开关（无任何宽限）
- 旧行为：按 Win 后有 `winGraceMs`(2500ms) 宽限期，期间靠近屏幕底部会**再次呼出**任务栏（用户报的 bug）。
- 用户明确要求：**不要任何宽限**，就是"按 Win 出现 / 再按 Win 收起"。第一版我只加了 Win 切换、却把宽限留着 —— 已彻底删掉：
  - `winGraceMs` / `forceHideMs` 两个设置项已移除；
  - 唯一允许展开的条件：`g_allowOpen`（按 Win 时任务栏不在屏上才置位）或"Win 键物理按着"（Start 菜单的展开请求可能早于轮询线程看到按键）；
  - 任务栏一旦出现在屏幕上就立刻撤销 `g_allowOpen` → 之后悬停不会再唤出；
  - 再按一次 Win 且任务栏可见 → 立即置回隐藏，许可同时清掉；
  - 看门狗不再"到点按回去"（那会和"按 Win 才收起"打架）。
- `blockExpand` 默认改为 true，作为第二道防线（`ShouldTaskbarBeExpanded` 返回 false）。
- 源码已改并复制到 `C:\ProgramData\Windhawk\ModsSource\`，`windhawk/stub/check.ps1` 语法检查通过；需要在 Windhawk 里重新编译。

### 顺带修掉的两个小 bug
- `GridTick()` 以前在菜单打开时也会跑 500ms 的"光标离开就收起"判断，比 `TrayMenuTick` 的 600ms 更早，结果**宫格先收起、菜单永远关不掉**（菜单会一直留在屏幕上）。现在菜单打开时 `GridTick` 直接返回，关闭时机交给 `TrayMenuTick`。
- `GridHide()` 的日志把窄字符串喂给了 `%s`，一直打印成乱码 `grid: hide (from 片摩楈敤)`。现在带 reason 参数，日志可读（`toggle / menu closed / menu cursor left / cursor left grid / strip faded ...`）。

---

## 4. 已完成 / 关键实现

### 4.1 玻璃模糊（`CaptureBackdrop()`）
- 抓取策略：先 `PrintWindow(PW_RENDERFULLCONTENT)` 抓**底下那个窗口**；`got` 只看**真正拷到的像素**里非黑比例（>1%）。
- 抓不到 / 抓到黑帧 → `GrabScreenUnderUs()`：`SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` 后 `BitBlt` 屏幕（**不隐藏窗口**、无闪烁），拿到"我们下面真实的画面"（桌面、UWP、视频都对）。
- 降采样倍数跟半径走：`blurRadius=0 → 1:1`（像素级清晰）、`1..11 → 1/2`、`>=12 → 1/4`；半径 `ceil(blurRadius/step)`，`BoxBlur` 两次 + `r/3` 细节；双线性放大回全尺寸。
- 合成：`glass = blurred*(1-t) + tint*t`，`out.alpha = glassOpacity`；另有 16% 往中灰的 lift 和 2.5px 柔光边（**不要** 1px 硬白边，用户已否掉）。
- 每 300ms 重抓一次（`WM_TIMER` id=1）。
- 诊断日志：`bake: under=... got= pw= grab= cover= size= small= r=`、`bake: pre= post= detail a->b`、`paint: glass a= t= bakeC= -> outC=`；`dumpBake=1` 写 `dock_bake_pre/post.bmp`。

### 4.2 图标清晰度
- 条上图标：`HiResIconForPath()`（shell jumbo 256px 帧）→ `RasterIconPx()`（预乘 box 滤波，**放大时自动切双线性**）→ `NormalizeIconSquare()`（已改双线性）。
- 按 `icon*1.45` 缓存，绘制时 `BlendScaled()` 缩放（悬停放大用）。

### 4.3 托盘桥（Windhawk mod `tray-icons-bridge` v3）
- **`Shell_NotifyIcon` 在调用者进程里执行** → 必须 `@include *` 注入每个进程；v3 起 `@architecture x86,x86-64`（Radmin VPN、Windhawk 是 32 位）。
- 各进程把**自己的**图标写进共享内存 `Local\DockTrayBridge_v1`（命名互斥锁 + 每条带 pid，写时清理死进程）。
- 表结构（与 dock 的 `TrayBridgeShm` 必须逐字节一致）：
  ```
  magic('TRAY')/version/count/capacity/updatedMs
  entries[128]{ hwnd(u64), uid, cbMsg, isGuid, pid, GUID guid, tip[128], exe[260] }
  ```
- **预热**：向 `HWND_BROADCAST` 广播系统的 `TaskbarCreated`（explorer 重启后系统发的就是它），各 App 会重新注册。mod 里只在 explorer 发一次；dock 启动 1.5s 后也发一次（`StartTrayWarmup()`）。
- `cbMsg` 处理：**新值为 0 时保留旧值**（很多 App 的 `NIM_MODIFY` 只更新 tooltip，会传 0）。
- dock 侧：`BuildTrayFromBridge()` → `TrayIconFromPath()`（或复用条上同 exe 的图标）→ 宫格。

### 4.4 托盘右键菜单转发（2026-11-11 重写，四个 App 实测通）
```cpp
SetWindowPos(g_gridWnd, HWND_NOTOPMOST, ...);   // 宫格临时降级，菜单才能盖住它
SetCursorPos(格子中心);                          // App 用 GetCursorPos 决定菜单位置
g_menuPid = 拥有者窗口 pid;
g_menuBaseline = 该 pid 当前可见窗口列表;
PostMessage(owner, cbMsg, uid, WM_RBUTTONDOWN); // ← 成对！只发 UP 时 QQ / UU 不弹
PostMessage(owner, cbMsg, uid, WM_RBUTTONUP);   // ← 不要 SetForegroundWindow（会顶掉菜单）
```
- 菜单识别（`MenuWindows`）= 两条线索的并集：
  1. 右键前后该 pid **新增**的可见窗口（经典 `#32768`、Tk、Qt 都靠这条）；
  2. 该 pid **盖住光标、没有标题栏的 popup**（`MenuLikeWindow`）——WPF 弹窗是复用的，永远不"新增"。
- 命中后把 `g_menuHwnd` 记下来，后续只跟踪这一个窗口（不然光标一动就被误判成"菜单没了"）。
- 保持：菜单存在期间 `DistanceToWindow()` 返回 0（条不淡出），宫格不收起；菜单打开期间 `GridTick()` 直接 return。
- 关闭语义跟原生托盘对齐：**鼠标点菜单外面才关，光移开不关**。
  - 光标离开「条 / 宫格 / 菜单」0.6s → 只把宫格收起（`GridHide(L"menu cursor left")`），**不**去关应用的菜单。
  - `MenuWatchTick()`（同一个 30ms 定时器里跑）盯着 `g_menuWatch`：`GetAsyncKeyState` 检测到真实按键（我们自己 Post 的消息不产生按键状态），且落点在菜单矩形外 → `CloseMenuWindows()`（`WM_CANCELMODE` + `Esc` + 失焦）。最多试 3 次，之后记日志放弃（提权 App 关不掉就别刷屏）。
  - 程序的菜单自己响应外部点击时（QQ / UU / DeskPad 都是），它会先关掉，我们下一帧看到 `app menu is gone` 收尾。
- 实测：QQ / 网易UU / DeskPad 都"点外部就关"；**Legion Zone 能开但关不掉**（提权 App，见 3.P1）。

### 4.5 其它
- `^` 宫格：托盘专属面板；悬停显示 30px 白字气泡；点外部 500ms 自动关（宫格 rect 与条 rect 都 inflate 16px 再判距离，走过去不会中途消失）。
- 悬停放大：30ms 定时器指数缓动，最大 1.34×，邻居让位、整行重新居中。
- 缩放热区：24×24 窗口角 + 贴合圆角轮廓的 10px 边带（`radius=100` 也能斜拖）。
- 淡入淡出：**只看光标到窗口（条/宫格）的距离**，`glassOpacity` 是图层 alpha。
  - 2026-11-11 删掉了 `g_pinUntil`（右键后强制显示 10 秒）和 `DistanceToWindow()` 里 `g_menuOpen` 直接返回 0 的特例 —— 那两个是旧设计的补丁，会让鼠标离开后图标条还赖 10 秒才消失。
- 开机自启：启动文件夹快捷方式 + 右键菜单开关（`SetAutoStart()`），日志 `autostart -> 1 (ok=1)`。

---

## 5. 配置（`dock.ini`，用户实际值在安装目录）

```ini
material=1            ; 0=纯色 1=玻璃
lightMode=1           ; 1=浅色（tint 会被强制成白色）
glassOpacity=235      ; 图层 alpha；<200 时清晰桌面会透出来，"看着不糊"
tintStrength=119      ; 0=纯磨砂
blurRadius=16         ; 全分辨率像素；0=像素级清晰，>32 基本糊成一块
tint=#A6101010
radius=42             ; 圆角百分比
fadeStart=39 / fadeEnd=152
iconSize=91 / minIcon=18 / maxIcon=72 / gap=6 / pad=10
dumpBake=0
```

**两个反直觉点（别再解释错）**：
- `blurRadius` 越大，透出来的清晰桌面看起来反而更"清楚"——因为玻璃层被抹平、对比度相对变大。**文字糊不掉**只能靠 `glassOpacity`（255 才完全不透）。
- `blurRadius=0` 现在是"清晰玻璃"（1:1 拷贝），不是模糊。

---

## 6. 代码地图（`dock.cpp`）

| 区块 | 说明 |
|---|---|
| `LoadConfig()` / `StripIniBom()` | ini 读取（BOM 必须剥） |
| `BuildItems()` / `PinnedLnkListed()` / `IsCandidate()` / `WindowLabel()` | 固定项来源（注册表 `Favorites`）+ shell 窗口规则 |
| `BuildTrayFromBridge()` | 桥表 → 宫格条目（全集，不做与条的去重；重复条目保留有回调的那条）|
| `MenuWindows()` / `MenuLikeWindow()` / `TrayMenuTick()` / `CloseMenuWindows()` | 托盘菜单识别 + 失焦关闭 |
| `ComputeButtons()` | 布局、每槽放大尺寸、滚轮翻页 |
| `Paint(w,h)` | 背景（玻璃/纯色）→ 图标 → 悬停高亮 → `^` |
| `Present()` | `UpdateLayeredWindow`（`g_alpha` 是整体淡出） |
| `CaptureBackdrop()` / `GrabScreenUnderUs()` / `WindowUnderUs()` | 背景抓取与模糊 |
| `BuildTray()` / `BuildTrayFromBridge()` / `TrayBridgeOpen()` | 托盘数据（桥 → 回退注册表） |
| `RasterIconPx()` / `TrayIconFromPath()` / `NormalizeIconSquare()` | 图标渲染 |
| `GridShow/GridPaint/GridProc/GridClick/GridTick/TrayMenuTick/CloseMenuWindows` | 宫格 + 托盘菜单 |
| `EdgeAt()` | 缩放热区（圆角感知） |
| `AutoStartPath/Enabled/SetAutoStart()` | 开机自启 |
| `ThumbShow()` / `ThumbProc` | DWM 悬停缩略图 |
| `SettingsPaint()` / `SettingsWndProc` | 自绘设置面板 |

---

## 7. 坑（血泪清单）

1. **低完整性**：从 workspace 启动的 exe 是 Low IL（`integrity=4096`），**无法创建子进程**（点图标启动程序会静默失败）。必须从安装目录、由 explorer / shell 启动（8192）。
2. **ini 带 UTF-8 BOM 会让所有配置失效**；`dev/setcfg.ps1` 用 `UTF8Encoding($false)` 写。
3. **GDI 画到 32bpp DIB 会把 alpha 写 0**（内容直接看不见）。所有自绘必须走 `SetPixelPremul()` / `BlendPremul()` / `BlendScaled()` / `DrawTextAlpha()`。
4. `small` 是 Windows 头文件的 typedef，不能当变量名。
5. **`Shell_NotifyIcon` 在 App 进程执行**——hook explorer 没用（踩过，表永远 0 条）。
6. **Windhawk 本地模组源码在 `C:\ProgramData\Windhawk\ModsSource\local@<id>.wh.cpp`**；编译只能通过 UI。
7. **mod 注入时机**：启用前就在运行的进程不会被注入；测托盘桥要重启对应 App 或整机重启。
8. **Win11 没有 `ToolbarWindow32`**，`Shell_NotifyIconGetRect` 对注册表里的 GUID 也全失败。
9. **不要给用户开全屏高对比测试图**（`dev/bgtest.ps1`）：2026-11-10 吓到过用户一次（以为电脑崩了），并且他会顺手点鼠标 → 日志里出现"假点击"、dock 被拖着跑。测玻璃时把窗口限制在 dock 附近，用完立刻关。
10. **投递托盘消息前不要 `SetForegroundWindow`**：会把刚弹出的菜单顶掉（表现为"菜单闪一下就没了"）。
11. **不要用 `FindWindow("#32768")` 找菜单**：WPF/Tk 的托盘菜单不是这个类名。也别只信"右键前后新增窗口"——WPF 弹窗是一个复用的 HWND，永远不会"新增"；要配合"该 pid 盖住光标的无标题 popup"。
12. 本机 `Shell_TrayWnd` 被 Windhawk 移到屏幕外（物理 y≈1077），所以任何依赖"托盘图标在屏上"的方案都不可行。
13. ops_bash 是 bash：`$`、`|`、`>` 会被吃掉 → 带变量的 PowerShell 一律写成 `.ps1` 再 `-File` 跑。
14. **坐标有两套**：`probe.ps1` 设了 DPI 感知（物理像素），`winstate.ps1` 没设（虚拟化 1/1.25）。混淆会得出错误结论——本轮就因此一度以为"另一个窗口抢了点击"。
15. **托盘菜单是"按下+抬起"成对才弹的**（QQ / UU 实测）：只投递 `WM_RBUTTONUP` 会静默无效，日志里看上去"发出去了"，其实 App 直接忽略。
16. **`SendMessage`/`PostMessage` 的返回值要检查**：对某些 App 的窗口（例如 Legion Zone 的 WPF 弹窗）会返回 `False` + `err=5`，而同一个进程的托盘窗口却是正常接受的。别假设"发了就等于生效"。
17. **别用 `GridTick` 和 `TrayMenuTick` 抢同一个关闭判断**：500ms vs 600ms 的先后顺序会让菜单永远关不掉。
18. `LP` 是 PowerShell 的 `Out-Printer` 别名，函数别起名叫 `LP`。
19. PowerShell 里 `$pid` 是只读自动变量，别当自己的变量名用。
20. **提权 App 的托盘图标只能"开"不能"关"**：Legion Zone（`LZTray.exe`）是 elevated，`PostMessage(WM_CLOSE)` 返回 `False`+`err=5`、`SetWindowPos`/`ShowWindow` 也被拒、`taskkill` 拒绝访问；但 `WM_RBUTTONDOWN/UP` 却能进去（App 自己放行的）。所以"给菜单发关闭消息"对它是死路。
    - 本机（2026-11-11 实测）**提权进程清单**：`LZTray`、`LegionZone`(多个)、`LZDubing`、`LenovoTray`、`LenovoInternetSoftwareFramework`、`Lsf`、`ResScheduler`、`WSPluginHost`、`SmartEngineHostN64`×2、`SmartEngineTray`、`FnHotkeyCapsLKNumLK`、`unsecapp`、若干 `crashpad_handler`。
    - 也就是说：宫格里**只有 Legion Zone 这一个**是提权的；QQ / 网易UU / DeskPad / WorkBuddy / DeepSeek / Windows 安全中心 / QQ助手 都是普通权限，菜单开关都正常。
    - 排查脚本：`dev/elevated.ps1`（列出所有提权进程）。
21. **托盘菜单窗口会短暂算成"任务栏窗口"**：QQ 的菜单是 `Chrome_WidgetWin_1`、`ex=[]`、无 owner，按 shell 规则它就是个可上条的窗口——所以打开 QQ 菜单的瞬间条上会多出一个 `QQ` 按钮（`items=9 → 10`），菜单关掉就恢复。**这是按规则该出现的结果**，不是回归。
22. **`IsWindowVisible` 不能用来判断"菜单还在屏幕上"**：WPF/Electron 的复用弹窗会一直保持 `WS_VISIBLE`。反过来，也不能用"采样点 `WindowFromPoint`"判定它在不在（菜单向上弹出时矩形有一半在屏幕外，采样点会全部落空 → 误判成"没了"）。判断"用户点没点外面"用 `GetAsyncKeyState` + 菜单矩形，判断"菜单关没关"只看 `IsWindowVisible`。
23. **同一时间只跟踪一个菜单**：用户连续右键两个图标时，先来的那个会被"遗忘"在屏幕上。现在开新菜单前会先把上一个关掉（日志 `closing the previous menu ... before opening another`）。
24. **托盘图标可能根本没有右键菜单**：`workbuddy.exe` 就是（只认左键）。别把"点了没反应"一律当成 dock 的 bug，先用 `dev/qqmenu.ps1` 跑矩阵。

---

## 8. `dock/dev/` 脚本

**日常验证（按顺序用）**

| 脚本 | 用途 |
|---|---|
| `run.ps1` | 杀掉旧 dock → 从安装目录启动 → 打印进程和日志头（保证 8192 完整性） |
| `gridrc.ps1 -Row R -Col C -Out x.png` | **最稳的宫格测试**：宫格没开就先开（`^` 不在固定位置——条宽度随布局变，脚本从右边往左扫，点右侧内边距是安全的），再对第 R 行第 C 列**真实右键**，等一会儿截全屏。格子 row 0..2 / col 0..2 |
| `repeat.ps1 -Row R -Col C -Times N` | 连续 N 轮"右键该格 + 点外部关闭"（复现"第二次失效"这类问题） |
| `clean.ps1 x.png` | 光标移到 (200,900)、等 0.9s 再截全屏（看"移开后是否都收起了"） |
| `hover_shot.ps1 -Out x.png [-X -Y]` | 光标停在 `^` 上截全屏（条不透明，方便看图标） |
| `cropzoom.py in.png out.png "l,t,r,b" [scale]` | 裁 + 放大看细节 |
| `favorites*.ps1` | dump `Taskband\Favorites` blob 的两种 UTF-16 对齐解码 + 和固定项文件夹对比 |
| `cands.ps1` | 按"旧规则 / shell 规则"分别枚举候选窗口，列出差异 |
| `winstyle.exe [秒]` | 合成两个测试窗口（`TOOLAPP`=TOOLWINDOW+APPWINDOW；无标题的普通窗口），验证 `IsCandidate` |
| `qqmenu.ps1 -Proc <名> -Hwnd <0x..> -Uid N -Msg 0x..` | 托盘消息矩阵：`UP / DOWN+UP / CONTEXTMENU / LBUTTONUP / uid=1 / UP x2`，逐条列出该进程可见窗口 |
| `whatwindow.ps1 -X -Y` | 打印屏幕某点上的窗口（pid / class / rect），排查"点击穿透到谁" |
| `elevated.ps1` | 列出所有**提权**进程（判断某个托盘 App 的菜单能不能被我们关掉） |
| `onscreen.ps1 -ProcId N` | 对某进程每个可见窗口做"9 点 `WindowFromPoint` 采样"（注意：菜单可能一半在屏外，这个测试不适合判"菜单在不在"） |
| `blur.ps1 -Proc <名>` | 对某进程所有可见窗口发 `WM_CANCELMODE`+`WM_ACTIVATE(WA_INACTIVE)`+`WM_KILLFOCUS`（清掉卡住的弹窗） |
| `resp.ps1 -ProcId N` | 该进程每个窗口的 `WM_NULL` ping 耗时 / `IsHungAppWindow`（判断是不是卡死） |

**原有**

| 脚本 | 用途 |
|---|---|
| `probe.ps1` | 打印 `DockStripWindow` 矩形 + 光标位置（物理像素） |
| `winstate.ps1` | 打印 grid / strip / menu / 前台窗口（注意坐标是虚拟化的） |
| `hover.ps1` / `moveto.ps1` / `shot.ps1` / `fullshot.ps1` | 移光标 / 截图 |
| `grid.ps1 -DxFromRight N` | 从窗口右边 N 像素处点一下并截全屏（**位置不固定**，见 `gridrc.ps1`） |
| `rightclick.ps1 -X -Y -CX -CY ...` | 在屏幕坐标右键并截图 |
| `clickpt.ps1 -X -Y` | 用 SendMessage 在客户区坐标点一下（测缩放热区） |
| `realclick.ps1` | 真实鼠标点击（验证 layered 窗口 hit-test） |
| `bridgedump.exe [-b]` | 打印托盘桥表（`-b` 先广播 TaskbarCreated）；源码 `bridgedump.cpp`，`buildtoy.ps1` 编译 |
| `traypost.exe <hwnd> <msg> <uid> <lparam> [x y]` | 手工向某 App 投递托盘消息（试它认哪条） |
| `taskprobe.ps1` | dump 进程窗口 vis/iconic/owner/exstyle（诊断"为什么条上没有它"） |
| `bitness.ps1` / `bitness2.ps1` / `injectcheck.ps1` / `bridgecheck.ps1` | 位宽、注入、共享内存探活 |
| `log.ps1 -Tail N -Pattern '...'` | 过滤 `dock.log` |
| `setcfg.ps1 -Set "k=v;k=v"` / `one.ps1` / `sweep.ps1` | 改配置 / 单次渲染 / 批量扫半径 |
| `crop.py` / `zoom.py` / `stat.py` / `px.py` / `stack.py` | 拼图、放大、像素统计（判断"糊没糊"） |
| `esc.ps1` / `closemenu.ps1 -Proc xxx` | 发 Esc / 对某进程窗口发 `WM_CANCELMODE` + Esc |
| `autostart.ps1 [-Remove]` | 建 / 删开机自启快捷方式 |

> `closepopup/clickout/closewpf/popupclick/windowsoff/wmclose/closenow/posttest/pidcheck/lzdiag/qqwins/lzwins/wbwins/wbprobe/traystage/trayone/qqtray` 是排查过程留下的单点工具，不必再用。

---

## 9. 下一步（建议顺序）

1. **用户动手**：Windhawk 界面把 `tray-icons-bridge` 重新"编译" + 确认启用。
   - `C:\ProgramData\Windhawk\ModsSource\local@tray-icons-bridge.wh.cpp`（22:37）比已编译 DLL（18:05）新；源码里"`NIM_MODIFY` 传 0 时保留旧 `cbMsg`""`NIM_DELETE` 删除条目"都还没进二进制。
   - 现在的症状：桥表里 QQ 那条 `cbMsg=0`（靠客户端缓存兜底）、Windows 安全中心 `cbMsg=0`。
   - 编译后重启对应 App（或整机）才会重新注册出正确值。
2. 观察真实使用：宫格右键 QQ / 网易UU / Legion Zone / DeskPad 各自开菜单、点条目、点别处关闭。
3. 若还有 App 右键没反应：先 `dev/qqmenu.ps1` 跑消息矩阵，再 `dev/elevated.ps1` 看是不是提权，别猜。
4. 真机任务栏对照（P0-3）只能"按规则推定"——任务栏被 mod 移到屏幕外（见坑 12）。
5. 更新本文件。

---

## 9.5 本轮（2026-11-11 凌晨）改动清单

`dock.cpp`（第一轮）
- 新增 `PinnedLnkListed()`（两种 UTF-16 对齐解析 `Taskband\Favorites`），`BuildItems()` 用它过滤固定项。
- 删除 `BuildTrayFromBridge()` 的 `onStripSkip`；重复条目改为"优先保留带回调的那条"。
- `IsCandidate()` 改成 shell 规则；新增 `WindowLabel()`（无标题窗口用 exe 名）。
- 托盘右键：投递 `WM_RBUTTONDOWN` + `WM_RBUTTONUP`。
- 新增 `MenuLikeWindow()` + "盖住光标的无边框 popup"线索 + `g_menuHwnd` 跟踪。
- `GridTick()` 在菜单打开时直接返回；`GridHide()` 带 reason；`CloseMenuWindows()` 增加失焦。

`dock.cpp`（第二轮，用户报"右键第二次失效 / 10s 才消失"）
- `g_trayCbCache`：记住每个 exe 最后一次可用的 `{hwnd,uid,msg}`，桥表回调被清零时复用（日志 `came back without a callback - reusing the last good one`）。
- 右键**没有回调**的托盘图标不再收起宫格（只记日志）。
- 删掉 `g_pinUntil`（10s 强制显示）和 `DistanceToWindow()` 里 `g_menuOpen` 返回 0 的特例：淡入淡出只看距离。
- `MenuWatchTick` 存活判定改为只看 `IsWindowVisible`。
- 开新菜单前先关掉上一个（避免孤儿菜单）。
- 实测：QQ 连点 3 次都正常（`dev/loop3.png`）；`workbuddy.exe` 确认**没有**右键菜单。

验证物证（截图都在 `dock/dev/`）：`final_strip3_zoom.png`（条上 6 个固定项、无 UU）、`final_grid3_zoom.png`（宫格 9 个）、`loop3.png`（QQ 连续三次菜单）、`qq_pair.png` / `uu_pair.png`（菜单开 + 点外部关）、`wb_keep_zoom.png`（没有菜单的图标右键后宫格不消失）。

---

## 10. 用户偏好（很重要）

- 不要自作主张扩大范围；**方向不确定、目标不现实、描述不清楚时先问**（用户明确要求过）。
- 不要用"看着还行"当结论，要给日志 / 截图证据。
- 改动小而可验证；一次只动一件事，改完立刻让他看效果。
- 他反感"别扭的绕路方案"（例如为了给菜单让位而收起宫格、或者让任务栏闪一下）——必须绕路时先说清代价再问。
- **不要让他做我能自己验证的事**：能编译/运行/截图验证的，自己验证完再汇报。
