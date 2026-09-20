# FreeSwitch

一个**免费、开源**的 macOS 菜单栏工具，用系统原生 API 复刻 One Switch 的全部开关。
放在菜单栏，一键切换常用系统开关。献给大家 ❤️

> Free & open-source menu-bar toggles for macOS — a clean-room reimplementation of One Switch's feature set, built on public system APIs.

## 功能一览（22 个开关）

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
| 清空废纸篓 | 清倒废纸篓 | Finder |
| 清空剪贴板 | 清空剪贴板 | NSPasteboard |
| 推出磁盘 | 推出所有外置/可推出卷 | NSWorkspace |
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

## 性能

空转时 CPU **0.02%**（60 秒只用掉 0.01 秒）。这个数字来之不易，改坏很容易，所以记一笔：

**写 `@Published` 之前一定要先比较值有没有变。** `SwitchStore.items` 是 `@Published`，
每赋值一次就发一次 `objectWillChange`，SwiftUI 会把所有观察这个 store 的视图整棵作废重建——
**包括关着的那个面板**：`MenuBarExtra(.window)` 的内容视图一直活着，不是关了就不算。
`reconcile()` 每 5 秒调十来个 setter，无条件赋值就等于每 5 秒十几次全量重建，
二十多个磁贴连玻璃材质一起重算。

实测（同一台机器，同样测法：取 `ps -o time=` 的差值）：

| | 空转 CPU | `sample` 里的面板视图求值 |
|---|---|---|
| setter 无条件赋值 | 0.73 % | `MenuContentView.grid`、`sectionView`、`SwitchTileView`、`layoutSubtreeIfNeeded` 都在 |
| setter 加了值比较 | 0.02 % | 一处都没有 |

主线程空等占比也从 16627/16807 变成 17038/17045。

顺带说明：`reconcile()` 本身是廉价的，只做进程内读取（CFPreferences、CoreBrightness、
CoreAudio），不 fork 子进程；`publish()` 早就有「内容没变就不写盘」的判断。
贵的从来不是读，是读完无条件写回 `@Published`。

## 设置窗口的「家族语言」

`FreeSwitch/Views/SettingsChrome.swift` 是和 **Dam**（同作者的另一个 App）共用的一层外壳：
玻璃背景 + 浮在上面的侧边栏 + 压住侧边栏右缘的内容卡片。类型名、度量、材质参数都对齐 Dam 的
`SettingsWindowChrome.swift` / `SettingsView.swift`，**整个文件可以在两个项目之间直接搬**。
改动请两边同步，否则家族语言就散了。

里面的数字不是随手挑的：

| 常量 | 值 | 为什么 |
|---|---|---|
| `sidebarWidth` / `sidebarContentWidth` | 286 / 224 | Dam 的原值。不要因为「这个 App 内容少」去缩，缩了就不是同一套语言 |
| `contentOverlap` | 34 | 卡片往左压住侧边栏。齐边会显得是两块拼版，压上去才有前后层次 |
| `titlebarClearance` | 70 | 给手动摆到 (16, 14) 的红绿灯按钮让位 |
| `outerWindowCornerRadiusEstimate` | 28 | NSWindow 的系统圆角没有稳定公开接口，这是校准值，用它反推卡片圆角让内外曲率同心 |

几个必须照做的点：

- **不能用系统标题栏。** 左边是一条浮在玻璃上的侧边栏，标题栏那条不透明横条会把玻璃从顶上切断，
  侧边栏就变成「悬在一块白板上」。用 `fullSizeContentView` + 透明标题栏，红绿灯手动摆位。
- **材质要用 `NSVisualEffectView(.underWindowBackground, .behindWindow)`**，不是 SwiftUI 的
  `.regularMaterial`——后者只在窗口内部混合，铺满整窗时看着就是一块灰纸。
- **窗口配置要跑两次。** `Settings { }` 场景的 NSWindow 不归我们创建，`viewDidMoveToWindow` 时
  窗口还在组装、红绿灯会被系统再摆一次，下一轮 runloop 里补一次才稳。
- **侧边栏条目的深浅色要分开写。** 同一组白色透明度在深色模式下会糊成一团。
- **顶边和左侧那两道 1px 高光别省**，它们是「玻璃有厚度」的唯一线索，去掉整面就发平。

光晕颜色留给各 App 传自己的身份色（Dam 是青蓝，FreeSwitch 用图标上那两个蓝）。

## 默认分组是算过的

面板一行 5 列，**每组独立换行**，所以一组的「格子数」（宽磁贴算 2 格）最好落在 5 的倍数上，
否则行尾就留洞。22 个开关 + 2 个宽磁贴 = 24 格，理论下限是 **5 行 1 个空位**。

现在的分组正好打到下限：

| 组 | 成员 | 个数 / 格数 |
|---|---|---|
| 屏幕 | 黑暗模式、夜览、原彩显示、屏幕分辨率(2) | 4 / **5** |
| 电源 | 保持亮屏(2)、低电量模式、显示器休眠、屏幕保护 | 4 / **5** |
| 清屏 | 隐藏桌面、自动隐藏程序坞、隐藏所有窗口、隐藏小组件、屏幕清洁 | 5 / **5** |
| 文件与清理 | 显示隐藏文件、清空剪贴板、清空废纸篓、推出磁盘、Xcode 清理 | 5 / **5** |
| 其他 | 锁定屏幕、麦克风静音、播放 / 暂停、锁定键盘 | 4 / **4** |

改动归属之前先按这个算一遍。之前的分法是 6 行 6 个空位，最刺眼的是「声音与输入」只有 2 个——
一整行只填 2/5。

两条容易忽略的规则：

- **`pack` 会让行里的宽磁贴吃掉剩余空位**（`row[wide].span += columns - used`），
  所以**一行里只要有宽磁贴就不会留洞**。我们只有 2 个宽磁贴，它们该被放在「格子数不是 5 的倍数」的组里当补丁用；
  旧分法把它们俩都放进了已经正好 5 格的组，这个补洞能力一格都没用上。
- **组内顺序跟着目录顺序走**（`GroupLayout.defaultGroups` 按 catalog offset 排），
  所以调整宽磁贴在组里的位置要改目录里 `SwitchItem` 的先后。

最后那组老实叫「其他」：它本来就是零散但常用的那一格抽屉，硬编一个「声音与锁定」之类的假类别反而更难找东西。

**用户能自己造分组**：在设置里把开关拖到**最顶上**（第一个分组标题之前）就新建一组。
新组不起名字，而**空名字的分组在面板上不画标题**，只剩组与组之间的间距——想要一条纯粹的空白分隔，这就是入口。
默认分组也一样，把名字删干净就变成纯分隔。

所以 `displayName(of:)` 里**空字符串是有意义的取值**，不能像以前那样「名字空了就退回默认名」，
那样用户永远得不到无标题的分组。面板里空标题要**整个不画**，别退而求其次画一个空 `Text`——
那仍然占着一行字高，间距反而比有标题时更怪。

新分组的 id 用「没被占用的最小编号」（`group1`、`group2`…）而不是 UUID：
`GroupLayout` 是纯逻辑、有独立测试，随机 id 会让测试不可复现。

**改默认分组不会动已有用户的面板**——`Preferences` 里存的是用户自己那份，默认值只影响「首次使用」和「恢复默认分组」。

## 弹层的内容高度不能随状态变化

`popover` 一弹出就按当时的内容定死尺寸，**之后内容变高不会跟着长，只会被裁掉**——
这就是「有时候显示不全、有时候又正常」的来历。踩到过两处：

- `ResolutionOptions` 的分辨率列表原来在 `.onAppear` 里才读。弹出那一刻内容只有
  「没有检测到可切换的分辨率」一行，尺寸按这一行定死，随后列表填进来就超出被裁。
  改成在视图创建时（`@State` 的初值）就读。
- `KeepAwakeOptions` 最后那行「还剩 N 分钟」是条件渲染的，在弹层里改时长会让它出现，
  内容变高同样被裁。改成常驻：不适用时画一个空字符串占住同样的高度。

宽度也别定死，用 `minWidth` + `fixedSize()`：德语、俄语的分段选择器比中文宽得多。

## 首次启动引导

`OnboardingView.swift` 四页：欢迎与隐私 / 排序与快捷键 / 加进控制中心 / 按需授权。
首次启动自动弹一次（`pref.onboardingCompleted`），之后可以从设置的「开关」页底部「查看引导」回看。

两条贯穿的做法：

- **能给真东西就不要给插图。** 第二页右边嵌的就是设置里那张「开关」页，第四页嵌的就是「权限」页——
  用户在引导里拖的那一下、授的那一次权都真的生效，以后打开设置看到的还是同一张脸。
  为此 `SwitchesPane` 有个 `embedded` 参数，嵌入时藏掉底部那条操作栏（那里有「查看引导」，在引导里再点一次就递归了）。
- **隐私那一页给的是可核对的依据，不是承诺。** 一个要辅助功能和自动化授权的 App，光说「我们不收集数据」没有说服力。
  写进去之前核实过：源码里 `URLSession`/`NWConnection`/socket 一处都没有，`otool -L` 也没有链接任何网络框架。

第三页原来右边有一张控制中心的示意图，去掉了：那张图既不是真的、也代替不了真的，占着半页却什么都没多说。

**窗口层级必须是 `.normal`，别改。** 第四页要用户直接在嵌进来的权限面板里授权，而授权会拉起「系统设置」——
只要引导窗口高于普通层级，系统设置就会被压在它下面，用户看不到自己该点哪儿。
`.normal` 下两扇窗口按焦点排序，谁激活谁在上。实测确认过：引导窗口 `layer=0`，打开系统设置后它排在引导之上。

也因此窗口铺的是 `visibleFrame` 而不是 `frame`：`.normal` 本来就盖不住菜单栏，强行铺满整屏只会在顶上留一条错位的缝。

另外无边框窗口默认**不能成为 key window**，键盘和文本框都不响应，必须自己 `override var canBecomeKey { true }`。

## 切换界面语言

设置里有「语言」一页（`AppLanguage.swift`）。系统匹配到的语言未必是用户想要的，所以给个显式开关。
语言名一律用它自己的语言写——让看不懂当前界面语言的人也能找到自己那一行（这几个名字**不进翻译目录**）。

**切换要重启，不是当场刷新。** 文案有两条取词路径：SwiftUI 的 `Text("中文字面量")` 走
`LocalizedStringKey`，由系统在 `Bundle.main` 里查；`L()` 走 `String(localized:)`，同样落在 `Bundle.main`。
想当场换语言只能改成从某个 `.lproj` 子 bundle 取词，但那对第一条路径无效，结果会是
「一半跟着切、一半不动」，比不支持还糟。所以走系统那套：把选择写进本 App 域的 `AppleLanguages`，然后重启进程。

**判断「当前选了什么」不能回头读 `AppleLanguages`。** `UserDefaults.standard` 读它会从 NSGlobalDomain
穿透过来，拿到的是系统的语言列表（实测 `["zh-Hans-CN", "en-CN"]`），不是本 App 的设置——
那串带地区后缀的值和列表里的 `zh-Hans` 对不上，选择器会显示成空白，「跟随系统」也永远选不中。
所以另存一个只属于本 App 域的 `pref.language` 当准绳。

引导第一页底部也有一个语言切换——**它的读者恰恰是看不懂当前界面文字的人**。所以用地球图标（不靠文字就能认出这是语言）、菜单里每种语言都用它自己的语言写、不加任何说明文字（写了他也读不懂）。那里选完**立刻重启**，不像设置里那样先提示「重启后生效」再等他点：引导还没走完，`hasCompleted` 还是假，重启后会用新语言从第一页重来，正是这个人想要的结果。

重启用的是「先睡一秒再 `open`」的子进程（和卸载脚本同一招）：子进程被 launchd 接管，在本进程退出后继续跑。
直接在退出前 `openApplication` 有可能在旧实例还没退干净时被系统当成「已经在运行」而忽略。

## 权限：用到了才请求

原则是**没真用到就不要去碰**。只要发一条 AppleEvent、请求一次辅助功能，系统就会把授权弹窗甩到用户脸上——
而那时候他可能刚装上、一个开关都还没点过。

所以每一项都有一个**不触发弹窗**的读法（`FreeSwitch/Support/Permissions.swift`）：

| 权限 | 只读状态 | 触发弹窗 |
|---|---|---|
| 自动化 | `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` | 同一个调用传 `true` |
| 辅助功能 | `AXIsProcessTrusted()` | `AXIsProcessTrustedWithOptions([prompt: true])` |

几个要点：

- **不要用「试着调一次、看结果对不对」来判断授权。** 试的那一下就把弹窗招出来了。
- **蓝牙依赖已经整个去掉。** 「耳机连接」删掉之后 App 不再碰 IOBluetooth，`NSBluetoothAlwaysUsageDescription` 也一并撤了——留着会让系统在隐私设置里给它列一项本来不需要的权限。
- **目标 App 没在跑时，自动化这套 API 什么也答不了。** 「系统事件」是按需启动的后台 agent，平时根本不在进程列表里；这时查询返回 `procNotFound`(-600)，既读不出状态，`askUserIfNeeded: true` 也弹不出授权框——症状就是「点了请求授权毫无反应」。两处都要处理：
  - **读**：-600 不能当成任何结论，要退回上一次**确定过**的答案（记在偏好里），否则同一项会随着目标 App 的起落在「已授权」和「请求授权」之间来回跳。
  - **请求**：不要调 `AEDeterminePermissionToAutomateTarget(…, true)`，改成发一条最无害的 AppleScript（`tell application id "…" to return name`）——脚本引擎会顺手把目标拉起来，授权框也就跟着出现了。结论**直接从这次执行的结果得出**，不要回头再查一次：后台 agent 服务完这条事件就退出了，再查只会拿到 -600，于是刚授权完按钮还是「请求授权」。

- **自动化的返回码要分三态**：`noErr` 已授权 / `errAEEventWouldRequireUserConsent`(-1744) 还没问过 / `errAEEventNotPermitted`(-1743) 问过被拒。被拒之后再调请求 API 系统不会再弹，所以那种情况按钮要换成「打开系统设置」，留着「请求授权」只会让人以为坏了。
- **辅助功能没有「没问过」和「被拒」的区别**，系统只告诉你信不信任，所以未授权一律按「可以再请求」处理。

## 多语言

界面共 9 种语言：简体中文（源语言）、English、繁體中文、日本語、한국어、Deutsch、Français、Español、Русский。

**字符串的键就是中文原文**，源语言是 `zh-Hans`，所以中文那份不用再抄一遍——改中文原文等于改键（也就等于让那条译文失配，记得同步改 `Localizable.xcstrings`）。

两份字符串目录，各归各的 bundle：

| 文件 | 属于 | 装进 |
|---|---|---|
| `FreeSwitch/Localizable.xcstrings` | 主 App（自动同步文件夹，无需登记） | `FreeSwitch.app/Contents/Resources/<lang>.lproj` |
| `Controls/Localizable.xcstrings` | 控制中心扩展（要在 pbxproj 里显式登记到它的 Resources 阶段） | `FreeSwitchControls.appex/Contents/Resources/<lang>.lproj` |

扩展是独立 bundle，查表走的是它自己的 `Bundle.main`，读不到主 App 那份——所以控件名必须在扩展那份目录里再写一遍。

**什么时候需要 `L("…")`**（`FreeSwitch/Support/Localized.swift`）：

- SwiftUI 的 `Text("中文")`、`Label("中文", systemImage:)`、`.help("中文")` 收的是 `LocalizedStringKey`，**字面量会自动查表**，不用套。
- 以下三种**不会**自动查表，必须显式取词：
  - AppKit：`NSAlert.messageText` / `informativeText` / `addButton(withTitle:)` 都是普通 `String`；
  - 文案先存进变量再交给界面：`Text(item.title)` 不查表（所以有 `SwitchItem.localizedTitle`）；
  - 三元和空合并：`Text(connected ? "已连接" : "未连接")`、`Text(x ?? "未选择设备")` 会落到 `StringProtocol` 重载上。

几个踩过的坑：

- **`LocalizedStringResource(stringLiteral:)` 不查表**，它的语义是「就用这个字面量」。控件的 `.displayName()` 要写成 `LocalizedStringResource(String.LocalizationValue(name))`。
- **本地化字面量里别写 Swift 插值**。`Text("剩 \(n) 分")` 的键长得跟源码不一样，对不上表；统一改成显式的 `%lld` / `%@` 占位，键就是可见、可核对的一串文字。
- **别在本地化字面量里用 `\` 行接续**。接续会让「源码里的文本」和「运行时的键」差一截，翻译静默失配。
- **默认分组名要按「和默认名一模一样」来判断是否本地化**，光判断空字符串不够：分组是建组时把默认名**存进偏好**的，老用户存的就是中文原文，只看空值的话他们永远看不到译文。
- `IOPMAssertionCreateWithName` 的名字**不本地化**——那是 `pmset -g assertions` 里的诊断标识，不是界面文案。

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
- **沙盒容器的根目录由 App 自己删不掉**（同一个目录，终端却删得掉，差别在发起者的身份）。删不掉时会清空里面的数据，只留一个空壳，并如实报出来。曾试过交给访达移废纸篓——访达同样没权限，还会留下一个一直转的进度窗，已经废弃。

- **容器里的数据要趁 App 还活着、用 App 自己的身份清**（`UninstallController.wipeContainerData`）。退出后那个脚本虽然继承了 App 的身份，却不带 App 的 entitlement，group 容器**连列目录都不允许**——早先的 `is_empty_shell` 把「列不出东西」当成「里面是空的」，于是谎报成已清空。现在 `container_state` 分三态：`empty` / `hasdata` / `unreadable`，读不了就明说读不了。

- **App 清完要当场核对，并把结论用 `--verified-empty <path>` 传给脚本**。只分三态还不够：实测一次真卸载，两个容器都被清成 0 个文件，脚本却因为看不见 group 容器而报「无法确认是否已清空」，弹出一条「卸载未完全」的通知——比谎报好，但仍旧不准。现在脚本对自己看不了、而 App 已核对过的路径采信 App 的结论。

- **报告三类一次报全**。以前只要有一项「无法确认」就提前 `exit`，把后面「空壳」那段整个吞掉，用户只看到「无法确认」，不知道其余的到底清没清。

- **判断容器空不空要数文件，不能数顶层条目**。容器被清空后系统会把 `Data/` 下那套标准骨架（Desktop、Documents、Library、Movies…几十个空目录）重新建出来，那是系统的脚手架，不是残留数据。

- **控件只要还留在控制中心里，扩展的容器就会被重新建出来**。实测：卸载在 12:23 把扩展容器删干净，12:36 它又出现，里面只有 `Data/SystemData/com.apple.chrono/…` 下两个 `lockKeyboard` 的占位快照——用户一拉开控制中心，chronod 就照着占位重新渲染。这种残留删多少次都会回来，所以卸载确认框和残留报告都会提醒去控制中心把控件移除。

## 系统控制中心

除了菜单栏面板，常用开关也可以直接加进 macOS 自带的控制中心（macOS 26+），执行仍然走本 App：

- **带状态的开关**：深色模式、夜览、保持亮屏、低电量、麦克风静音、锁定键盘、显示隐藏文件 —— 控制中心里直接显示开/关，和面板双向同步。
- **点按动作**：锁定屏幕、屏幕清洁、清空废纸篓、Xcode 清理。

添加方式：控制中心 › 编辑控件 › 从控件库里找 FreeSwitch。

实现上，控件是一个沙盒 App Extension，和主 App 之间走两条独立的通道：

- **动作**：控件发 Darwin 通知 `MXHBUQH27V.group.com.freeswitch.FreeSwitch.trigger.<id>` / `.set.<id>.<1|0>`，主 App 监听并执行。
- **状态回读**：主 App 把真实状态写进**控件扩展自己的沙盒容器**（`~/Library/Containers/com.freeswitch.FreeSwitch.Controls/Data/Library/Application Support/FreeSwitch/states.json`），扩展读自己的容器即可。

状态这条**刻意不走 App Group 容器**：App Group 必须被沙盒真正授予（Team ID 前缀之外还要有相应的描述文件），本地签名下扩展往往拿不到，`containerURL(...)` 返回 nil，状态永远读成 `false`——症状是控制中心里开关能正常显示、一翻就弹回，像个只读的状态指示器。扩展读自己的容器不需要任何 entitlement，而主 App 本就非沙盒，可以直接往里写。

> **Fork 须知**：Darwin 通知名以 Team ID 开头，用你自己的证书编译时把 `MXHBUQH27V` 换成你的 Team ID，共四处：两个 `.entitlements`、`FreeSwitchTrigger.swift`、`FreeSwitchControls.swift`。

> **改控件时注意**：控制中心里**已经放置**的控件实例，绑定的是它被添加时的那个 intent。若之后改了该 kind 的模板类型（按钮 ↔ 开关）或换了 intent，旧实例会继续发送旧的通知——而那个名字通常已经没人监听了，于是**点击完全没反应，且不报任何错**。重装和重启控制中心都救不了，必须把控件**移除再重新添加**。所以同一个 kind 上不要反复换交互形态；开发期改了就记得重加一次再测。

动作类控件（屏幕清洁、清空废纸篓、Xcode 清理）点一下即执行，并带执行阶段反馈：常态 →「处理中…」→「已完成」（绿色）→ 五秒后回到常态。阶段存在 `phases.json`（与 `states.json` 同目录，schema 不同故分开）。扩展在发通知**之前**先自己写入 `running`，反馈才能在点下的瞬间出现；同时它会丢弃处理中的重复点击——控制中心本身是允许连点的。

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
- **勿扰 / 专注已经删掉**。现代 macOS 禁止第三方 App 直接切换「专注」（私有框架 `DoNotDisturb` 需 Apple 专属授权，实测第三方调用被 `donotdisturbd` 以 XPC 拒绝）。唯一的官方路径是让用户自己去「快捷指令」建一个名为 `FreeSwitch DND` 的快捷指令，我们再 `shortcuts run` 它——为了一个开关要求用户先手工搭一条快捷指令，价值抵不过这个门槛，所以整条功能连同设置项一起移除了。控制中心里系统本来就有「专注模式」模块。
- **低电量模式**需要管理员权限，切换时会弹出系统密码框。
- **隐藏所有窗口**：**访达整个 App 藏不掉**。其它 App 全部隐藏后，系统必须有一个「当前 App」，于是它激活访达，而激活会取消隐藏。单独隐藏访达是成功的，改用 `hideOtherApplications` 也一样——这是 macOS 的行为，不是调用方式的问题。实现上分三轮收，每轮之前先激活 FreeSwitch 自己占住「当前 App」，能从「剩两三个」收敛到「只剩访达」。另外 `NSRunningApplication.hide()` 的**返回值不可信**（实测返回 `false`，一秒后那个 App 却确实隐藏了），所以不按返回值记账，真实状态一律按 `isHidden` 回读。

- **访达单独用 AppleScript 折叠窗口**（`collapsed`），效果等同最小化到程序坞。只记「原本没折叠」的窗口 id，还原时只恢复它们。三个坑都是实测撞出来的：
  - 必须用 `Finder window`，不能用泛称的 `window`。后者会把访达挂住——同一时刻 `count of windows` 两次都等到 AppleEvent 超时（-1712），而 `count of Finder windows` 立刻返回 2。
  - 不能 `repeat with w in (every Finder window)`：拿到的是 `item 1 of every Finder window` 这种引用，访达解不开，报 -1728。要按下标取。
  - 不能边遍历边折叠：折叠会把窗口挪到最后，而下标就是前后次序，第二轮取到的正是刚折叠的那个，真正该折叠的反倒被跳过（实测两个窗口只收掉一个）。所以先收集 id，再按 id 逐个折叠。
  - 一律套 `with timeout`：访达卡住时默认要等两分钟，而这段脚本跑在主线程上，整个 App 会跟着僵住。
  - 端到端实测：12 个窗口 → 0 个（三个访达窗口一并收掉）→ 还原 11 个。

- **有的 App 被 `unhide()` 恢复后不会自己把窗口放回屏幕**（实测微信：`isHidden` 已回到 `false`，窗口却全部 `onscreen=false`）。AppKit 只保证 App 不再处于隐藏状态，窗口怎么摆是 App 自己的事，我们不额外 `activate()` 去抢焦点。
- **彻底卸载会重置隐私授权**：重装之后「自动化」需要重新授权，否则黑暗模式、自动隐藏程序坞、清空废纸篓会**静默失效**。现在遇到这种情况会弹一次说明，并可直接跳到设置页。
- **免密授权（可选）**：默认切换「合盖不休眠 / 低电量模式」每次要输一次管理员密码。可在设置里安装一个内置的特权助手（`SMAppService` 后台守护进程，随 App 打包、非单独下载），**一次授权后即免密**；助手只接受签名匹配的 FreeSwitch 调用，随时可在设置里移除。安装前 App 会先弹一段说明再触发系统授权。
- **合盖也不休眠**用 `pmset -a disablesleep`（需管理员密码，每次开/关时弹一次；改定时不重复弹）。⚠️ 开启后合上盖子电脑**不会休眠**，装在包里会持续发热、耗电——**强烈建议配合定时**（到点自动关）。若 App 崩溃/强退时它还开着，下次启动会自动恢复系统设置。它做的是 Amphetamine「闭屏模式」那件事，但无需额外下载 Enhancer 之类的组件。

## 许可证

[MIT](LICENSE) — 免费使用、修改、分发。
