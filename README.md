# FreeSwitch

一个**免费、开源**的 macOS 菜单栏工具，用系统原生 API 复刻 One Switch 的全部开关。
放在菜单栏，一键切换常用系统开关。献给大家 ❤️

> Free & open-source menu-bar toggles for macOS — a clean-room reimplementation of One Switch's feature set, built on public system APIs.

## 功能一览（24 个开关）

| 开关 | 说明 | 实现 |
|------|------|------|
| 黑暗模式 | 切换浅色 / 深色外观 | System Events（需“自动化”授权） |
| 夜览 | Night Shift 开关 | CoreBrightness（私有框架，运行时动态调用） |
| 原彩显示 | True Tone 开关 | CoreBrightness |
| 保持亮屏 | 阻止屏幕/系统休眠；可定时；可选「合盖也不休眠」(装包继续跑) | IOKit 电源断言 + `pmset disablesleep` |
| 低电量模式 | 开/关低电量模式 | `pmset -a lowpowermode`（切换时弹管理员密码） |
| 麦克风静音 | 静音默认输入设备（不支持 mute 的设备回退为输入音量置 0） | CoreAudio |
| 隐藏桌面 | 隐藏/显示桌面图标 | `defaults` + 重启 Finder |
| 显示隐藏文件 | 访达显示隐藏文件 | `defaults` + 重启 Finder |
| 自动隐藏程序坞 | 切换程序坞自动隐藏 | System Events（需“自动化”授权；不重启程序坞） |
| 隐藏所有窗口 | 一键隐藏所有 App 的窗口，再点一次恢复 | NSRunningApplication hide/unhide（无需任何授权） |
| 隐藏小组件 | 隐藏桌面与台前调度里的小组件 | `com.apple.WindowManager` 偏好（WindowManager 立即生效，无需重启） |
| 锁定键盘 | 屏蔽全部键盘输入 | CGEventTap（需“辅助功能”授权） |
| 屏幕清洁 | 锁定输入 + 每块屏纯黑遮罩，安心擦屏；只能点屏上按钮退出（擦键盘可能误触 Esc） | CGEventTap + 遮罩窗口 |
| 显示器休眠 | 立即黑屏 | `pmset displaysleepnow` |
| 锁定屏幕 | 立即锁屏 | login.framework `SACLockScreenImmediate` |
| 屏幕保护 | 启动屏保 | ScreenSaverEngine |
| 播放 / 暂停 | 媒体播放控制 | 系统多媒体键事件 |
| 耳机连接 | 一键连/断所选 AirPods/耳机，显示电量，连上自动切声音输出 | IOBluetooth + CoreAudio + system_profiler（设置里先选设备；可绑全局热键） |
| 清空废纸篓 | 清倒废纸篓 | Finder |
| 清空剪贴板 | 清空剪贴板 | NSPasteboard |
| 推出磁盘 | 推出所有外置/可推出卷 | NSWorkspace |
| 勿扰 / 专注 | 一键切换专注（需一次性设置快捷指令） | Shortcuts `shortcuts run` |
| Xcode 清理 | 删除 DerivedData | FileManager |
| 屏幕分辨率 | 切换分辨率，多显示器每块屏单独子菜单 | CoreGraphics |

## 可配置性

点面板右上角 ⚙️ 打开设置窗口：

- **显示哪些开关**：逐个勾选,只留常用的。
- **拖动排序**：把最常用的排前面。
- **全局快捷键**：给任意开关绑系统级热键(如 ⌥⌘L 锁屏),不打开菜单也能触发。基于 Carbon `RegisterEventHotKey`,无需辅助功能授权。
- **开机自动启动**：基于 `SMAppService`。

面板状态实时刷新(在别处切换深色模式会同步),磁贴带悬停反馈,菜单栏图标在有常驻开关(保持亮屏/锁键盘/静音等)激活时会变色提示。

## 环境要求

- macOS 14.6+
- Xcode 26+

## 构建安装

```bash
./scripts/install.sh
```

构建 Release、装进 `/Applications`、重新登记控制中心扩展、清控件快照缓存，一步到位。

## 彻底卸载

设置窗口里有「彻底卸载 FreeSwitch…」按钮；也可以在终端运行：

```bash
./scripts/uninstall.sh          # 会先确认
./scripts/uninstall.sh --list   # 只列出会删除的路径，不做任何改动
```

两个入口共用同一份实现 `FreeSwitch/Support/uninstall.sh`（随 App 打包）。把 App 拖进废纸篓是清不干净的——控制中心的扩展登记、控件快照缓存、特权助手与登录项、「合盖也不休眠」改过的电源设置都会留下来继续生效。

实现上有几处必须按顺序来，都是踩过的坑：

- **偏好设置要等 App 退出后再删**，并用 `defaults delete`。App 还活着时删文件没用，退出时会被写回来。
- **删扩展容器前，先注销扩展、结束其进程、重启 chronod**，否则控制中心会把扩展重新拉起，容器又被建出来。
- **由 App 发起的删除，对扩展的沙盒容器等会静默失败**（同一个容器，开发用的 shell 却能删）。删不掉的会清空其中数据并如实报出来，仍有残留则发通知并在访达里标出来，过程记录在 `/tmp/FreeSwitch-uninstall.log`。
- 后台项登记（`sfltool dumpbtm`）里的旧记录不做处理：注销后它们只是停用的记录，唯一的清除手段 `sfltool resetbtm` 会重置所有 App 的后台项授权。
- **沙盒容器的根目录由 App 自己删不掉**（同一个目录，终端却删得掉，差别在发起者的身份）。删不掉时会清空里面的数据，只留一个不含任何内容的空壳，并如实报出来。曾试过交给访达移废纸篓——访达同样没权限，还会留下一个一直转的进度窗，已经废弃。

## 系统控制中心

除了菜单栏面板，常用开关也可以直接加进 macOS 自带的控制中心（macOS 26+），执行仍然走本 App：

- **带状态的开关**：深色模式、夜览、保持亮屏、低电量、麦克风静音、锁定键盘、显示隐藏文件 —— 控制中心里直接显示开/关，和面板双向同步。
- **点按动作**：勿扰、锁定屏幕、屏幕清洁、清空废纸篓、Xcode 清理。

添加方式：控制中心 › 编辑控件 › 从控件库里找 FreeSwitch。

实现上，控件是一个沙盒 App Extension，和主 App 之间走两条独立的通道：

- **动作**：控件发 Darwin 通知 `MXHBUQH27V.group.com.freeswitch.FreeSwitch.trigger.<id>` / `.set.<id>.<1|0>`，主 App 监听并执行。
- **状态回读**：主 App 把真实状态写进**控件扩展自己的沙盒容器**（`~/Library/Containers/com.freeswitch.FreeSwitch.Controls/Data/Library/Application Support/FreeSwitch/states.json`），扩展读自己的容器即可。

状态这条**刻意不走 App Group 容器**：App Group 必须被沙盒真正授予（Team ID 前缀之外还要有相应的描述文件），本地签名下扩展往往拿不到，`containerURL(...)` 返回 nil，状态永远读成 `false`——症状是控制中心里开关能正常显示、一翻就弹回，像个只读的状态指示器。扩展读自己的容器不需要任何 entitlement，而主 App 本就非沙盒，可以直接往里写。

> **Fork 须知**：Darwin 通知名以 Team ID 开头，用你自己的证书编译时把 `MXHBUQH27V` 换成你的 Team ID，共四处：两个 `.entitlements`、`FreeSwitchTrigger.swift`、`FreeSwitchControls.swift`。

> **改控件时注意**：控制中心里**已经放置**的控件实例，绑定的是它被添加时的那个 intent。若之后改了该 kind 的模板类型（按钮 ↔ 开关）或换了 intent，旧实例会继续发送旧的通知——而那个名字通常已经没人监听了，于是**点击完全没反应，且不报任何错**。重装和重启控制中心都救不了，必须把控件**移除再重新添加**。所以同一个 kind 上不要反复换交互形态；开发期改了就记得重加一次再测。

动作类控件（勿扰、锁定屏幕、屏幕清洁、清空废纸篓、Xcode 清理）点一下即执行，并带执行阶段反馈：常态 →「处理中…」→「已完成」（绿色）→ 五秒后回到常态。阶段存在 `phases.json`（与 `states.json` 同目录，schema 不同故分开）。扩展在发通知**之前**先自己写入 `running`，反馈才能在点下的瞬间出现；同时它会丢弃处理中的重复点击——控制中心本身是允许连点的。

> **控制中心的刷新是每 5 秒一次的节流，别把它当 bug 修。** 实测（面板打开、日志时间戳）：刷新请求会被立即响应，但**最多每 5 秒一次**，冷却期内的请求顺延到冷却结束——三次实测分别在 `05.85`、`10.87`、`15.88` 落地，间隔 5.02s / 5.01s。连发多次 `reloadAllControls()` 不会更快。
>
> 由此推出两条：**每多一段状态，就要多花一个 5 秒周期**（所以「处理中 → 已完成 → 常态」从点击到复原约 10 秒，其中慢动作的「处理中」有最多 5 秒是过期的——早做完了还在转）；而**「已完成」的停留窗口必须长过一个刷新周期**，否则刷新落地时它已经回落，那一段就永远画不出来（窗口曾是 2 秒，症状正是慢动作只见「处理中」、从不见「已完成」）。
>
> 面板**关闭**时 `reloadAllControls()` 完全不会回查扩展——扩展进程都不会被唤醒。所以刷新延迟只有在面板打开时才测得到。
>
> 另：每次刷新会把**全部**控件都回查一遍。`reloadControls(ofKind:)` 可只刷新变化的那一个，省掉无谓的唤醒，但**救不了上面的延迟**，瓶颈是节流而非回查耗时。

> ⚠️ **必须装 Release 版。** Debug 构建会把扩展代码拆进单独的 `.debug.dylib`，主二进制只剩个桩，系统拉不起这样的沙盒扩展 —— 表现为控制中心里**带状态的开关显示成 `app.dashed` 占位图标**（按钮类不用跑代码所以看着正常，极易误判成图标名写错了）。
> 另外 `pluginkit` 按 bundle id 只认一份扩展，构建目录里残留的 Debug 包会把 `/Applications` 这份顶掉，重装多少次都没用。`scripts/install.sh` 会一并清理，别手动 `cp` 了事。

## 权限说明

首次使用部分功能时，系统会请求授权：

- **自动化 / Apple 事件**：黑暗模式、清空废纸篓等（“系统设置 › 隐私与安全性 › 自动化”）。
- **辅助功能**：锁定键盘、屏幕清洁（“系统设置 › 隐私与安全性 › 辅助功能”）。

App 未开启沙盒，因此不能上架 Mac App Store；自行签名分发即可。

## 公证与分发（可选）

自己编译的 App 没经过 Apple 公证，弹管理员/权限框时会带「Apple 无法验证是否含恶意软件」的吓人措辞。用你自己的付费 Apple 开发者账号公证一次即可去掉：

```bash
# 一次性存好凭据（app 专用密码在 appleid.apple.com 生成）
xcrun notarytool store-credentials freeswitch-notary \
  --apple-id "you@example.com" --team-id MXHBUQH27V --password "app-专用密码"

# 公证（构建 Release + 签名 + 提交 + 装订票据）
NOTARY_PROFILE=freeswitch-notary ./scripts/notarize.sh
```

脚本见 [scripts/notarize.sh](scripts/notarize.sh)。需要钥匙串里有「Developer ID Application」证书（Xcode ▸ 设置 ▸ Accounts ▸ Manage Certificates 里添加）。公证需要加固运行时，`FreeSwitch.entitlements` 已声明发送 Apple 事件的权限。

> 注意：公证只去掉「无法验证恶意软件」这句，**不会**减少管理员密码框的出现次数——那取决于是否装了下面的特权助手。

## 已知限制

- **夜览 / 原彩**依赖私有框架 `CoreBrightness`，仅在支持的机型上可用；不同 macOS 版本行为可能变化。
- **勿扰 / 专注**：现代 macOS 禁止第三方 App 直接切换「专注」（私有框架 `DoNotDisturb` 需 Apple 专属授权，实测第三方调用被 `donotdisturbd` 以 XPC 拒绝）。官方许可路径是「快捷指令」——在设置里新建名为 `FreeSwitch DND` 的快捷指令（动作：设定专注 → 勿扰 → 切换），即可一键触发。
- **耳机连接**用 IOBluetooth `openConnection/closeConnection`；需先在设置里选择目标设备，首次访问会请求蓝牙授权。
- **低电量模式**需要管理员权限，切换时会弹出系统密码框。
- **隐藏所有窗口**：**访达的窗口藏不掉**。其它 App 全部隐藏后，系统必须有一个「当前 App」，于是它激活访达，而激活会取消隐藏。单独隐藏访达是成功的，改用 `hideOtherApplications` 也一样——这是 macOS 的行为，不是调用方式的问题。实现上分三轮收，每轮之前先激活 FreeSwitch 自己占住「当前 App」，能从「剩两三个」收敛到「只剩访达」。另外 `NSRunningApplication.hide()` 的**返回值不可信**（实测返回 `false`，一秒后那个 App 却确实隐藏了），所以不按返回值记账，真实状态一律按 `isHidden` 回读。
- **彻底卸载会重置隐私授权**：重装之后「自动化」需要重新授权，否则黑暗模式、自动隐藏程序坞、清空废纸篓会**静默失效**。现在遇到这种情况会弹一次说明，并可直接跳到设置页。
- **免密授权（可选）**：默认切换「合盖不休眠 / 低电量模式」每次要输一次管理员密码。可在设置里安装一个内置的特权助手（`SMAppService` 后台守护进程，随 App 打包、非单独下载），**一次授权后即免密**；助手只接受签名匹配的 FreeSwitch 调用，随时可在设置里移除。安装前 App 会先弹一段说明再触发系统授权。
- **合盖也不休眠**用 `pmset -a disablesleep`（需管理员密码，每次开/关时弹一次；改定时不重复弹）。⚠️ 开启后合上盖子电脑**不会休眠**，装在包里会持续发热、耗电——**强烈建议配合定时**（到点自动关）。若 App 崩溃/强退时它还开着，下次启动会自动恢复系统设置。它做的是 Amphetamine「闭屏模式」那件事，但无需额外下载 Enhancer 之类的组件。

## 许可证

[MIT](LICENSE) — 免费使用、修改、分发。
