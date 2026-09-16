# FreeSwitch

一个**免费、开源**的 macOS 菜单栏工具，用系统原生 API 复刻 One Switch 的全部开关。
放在菜单栏，一键切换常用系统开关。献给大家 ❤️

> Free & open-source menu-bar toggles for macOS — a clean-room reimplementation of One Switch's feature set, built on public system APIs.

## 功能一览（21 个开关）

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

构建 Release、装进 `/Applications`、重新登记控制中心扩展、重启控制中心，一步到位。

也可以直接在 Xcode 里打开 `FreeSwitch.xcodeproj` 按 Run —— 但**这样调不通控制中心控件**，原因见下。

## 系统控制中心

除了菜单栏面板，常用开关也可以直接加进 macOS 自带的控制中心（macOS 26+），执行仍然走本 App：

- **带状态的开关**：深色模式、夜览、保持亮屏、低电量、麦克风静音 —— 控制中心里直接显示开/关，和面板双向同步。
- **点按动作**：勿扰、锁定屏幕、屏幕清洁、清空废纸篓。

添加方式：控制中心 › 编辑控件 › 从控件库里找 FreeSwitch。

实现上，控件是一个沙盒 App Extension，通过 App Group 和主 App 通信：控件发 Darwin 通知（`group.com.freeswitch.FreeSwitch.trigger.<id>` / `.set.<id>.<1|0>`）触发执行，主 App 把真实状态回写到 App Group 容器里的 `states.json` 供控件显示。

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
- **免密授权（可选）**：默认切换「合盖不休眠 / 低电量模式」每次要输一次管理员密码。可在设置里安装一个内置的特权助手（`SMAppService` 后台守护进程，随 App 打包、非单独下载），**一次授权后即免密**；助手只接受签名匹配的 FreeSwitch 调用，随时可在设置里移除。安装前 App 会先弹一段说明再触发系统授权。
- **合盖也不休眠**用 `pmset -a disablesleep`（需管理员密码，每次开/关时弹一次；改定时不重复弹）。⚠️ 开启后合上盖子电脑**不会休眠**，装在包里会持续发热、耗电——**强烈建议配合定时**（到点自动关）。若 App 崩溃/强退时它还开着，下次启动会自动恢复系统设置。它做的是 Amphetamine「闭屏模式」那件事，但无需额外下载 Enhancer 之类的组件。

## 许可证

[MIT](LICENSE) — 免费使用、修改、分发。
