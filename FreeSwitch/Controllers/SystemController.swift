import AppKit
import OSLog

/// 系统杂项：隐藏桌面、显示隐藏文件、清空废纸篓、清空剪贴板、推出磁盘、Xcode 清理。
enum SystemController {

    // MARK: 隐藏桌面图标
    static func setDesktopIconsHidden(_ hidden: Bool) {
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    /// 读别的 App 的某个偏好项。用 CFPreferences 直接读，不 fork `defaults read`——
    /// 只有足够便宜，这些状态才能纳入每 5 秒的核对。
    /// 这很要紧：访达里 Cmd+Shift+. 就能切「显示隐藏文件」，不核对的话控件会一直显示过期值。
    /// 读之前先同步一次，否则拿到的可能是本进程缓存里的旧值，看不见别人刚改的。
    private static func prefFlag(_ key: String, in domain: String) -> Bool? {
        let appID = domain as CFString
        CFPreferencesAppSynchronize(appID)
        guard let value = CFPreferencesCopyAppValue(key as CFString, appID) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["1", "true", "yes"].contains(text.lowercased()) }
        return nil
    }

    private static func setPrefFlag(_ value: Bool, _ key: String, in domain: String) {
        let appID = domain as CFString
        CFPreferencesSetAppValue(key as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, appID)
        CFPreferencesAppSynchronize(appID)
    }

    private static func finderFlag(_ key: String) -> Bool? { prefFlag(key, in: "com.apple.finder") }

    // MARK: 自动隐藏程序坞

    static func dockAutohide() -> Bool { prefFlag("autohide", in: "com.apple.dock") ?? false }

    /// 用 System Events 设置，而不是 `defaults write` + `killall Dock`：
    /// 后者会重启程序坞，画面闪一下、动画也断；前者走系统自己的设置通道，立即生效且平滑。
    /// 脚本字典里这个属性属于 “dock preferences object”（已核对）。
    static func setDockAutohide(_ on: Bool) {
        setDockPreference("autohide", on)
    }

    /// 通过 System Events 改 dock preferences 里的一项，**在后台跑**。
    ///
    /// System Events 是按需启动的 agent，脚本得先等它起来（实测一次 0.41 秒）；
    /// 还没给「自动化」授权时更糟——脚本会一直挂到用户在授权框上点完为止。
    /// 两种情况留在主线程上都是转彩虹。调用方本来就不等结果：
    /// 它们按目标值乐观显示并标记写入在途，由 5 秒一次的核对纠正。
    private static func setDockPreference(_ property: String, _ value: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.runAppleScript("tell application \"System Events\" to set \(property) of dock preferences to \(value)")
        }
    }

    // MARK: 桌面小组件

    static func desktopWidgetsHidden() -> Bool {
        prefFlag("StandardHideWidgets", in: "com.apple.WindowManager") ?? false
    }

    /// 实测过：写完约 0.1 秒 WindowManager 就会 “refreshing layout controller”，
    /// 所以不需要 killall WindowManager（那会让窗口和台前调度闪一下）。
    /// 桌面和台前调度里的小组件一起处理，「隐藏小组件」才是一致的含义。
    static func setDesktopWidgetsHidden(_ hidden: Bool) {
        setPrefFlag(hidden, "StandardHideWidgets", in: "com.apple.WindowManager")
        setPrefFlag(hidden, "StageManagerHideWidgets", in: "com.apple.WindowManager")
    }

    static func desktopIconsHidden() -> Bool {
        // CreateDesktop 缺省（没设过）时桌面图标是显示的。
        finderFlag("CreateDesktop") == false
    }

    // MARK: 显示隐藏文件
    static func setShowHiddenFiles(_ show: Bool) {
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", show ? "true" : "false"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    static func showHiddenFiles() -> Bool {
        finderFlag("AppleShowAllFiles") ?? false
    }

    // MARK: 清空废纸篓（会弹出访达的确认）
    /// 访达会弹确认框，脚本一直等到用户回答为止——所以务必在主线程之外调用。
    nonisolated static func emptyTrash() {
        Shell.runAppleScript("tell application \"Finder\" to empty the trash")
    }

    // MARK: 清空剪贴板
    static func emptyClipboard() {
        NSPasteboard.general.clearContents()
    }

    // MARK: 推出所有可推出/外置磁盘
    /// 务必在主线程之外调用。
    ///
    /// `unmountAndEjectDevice` 是同步的：它要等写缓冲刷干净、等占用文件的进程让开，
    /// 一块机械盘或者刚拷完东西的 U 盘要好几秒。挂在主线程上就是光标转彩虹
    /// （实测：点「推出磁盘」后转了几秒；盘是空闲的那次就没转）。
    /// 枚举卷本身也可能慢——`mountedVolumeURLs` 会去 stat 网络卷，对面不在就得等超时。
    nonisolated static func ejectAllRemovableDisks() {
        let workspace = NSWorkspace.shared
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        for url in volumes {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let removable = values?.volumeIsRemovable ?? false
            let ejectable = values?.volumeIsEjectable ?? false
            let external = (values?.volumeIsInternal == false)
            if removable || ejectable || external {
                try? workspace.unmountAndEjectDevice(at: url)
            }
        }
    }

    // MARK: Xcode 缓存清理（DerivedData）
    @discardableResult
    /// 可能要删好几个 G，务必放在主线程之外调用。
    nonisolated static func cleanXcodeCaches() -> Int {
        let base = ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: base) else { return 0 }
        var count = 0
        for item in items {
            let path = (base as NSString).appendingPathComponent(item)
            if (try? fileManager.removeItem(atPath: path)) != nil { count += 1 }
        }
        return count
    }

    // MARK: 低电量模式
    /// 用 ProcessInfo 读，不要 fork `pmset -g` 去解析文本：
    /// 前者是进程内的即时值，后者既贵又滞后于刚刚写下去的设置（回读会拿到旧值）。
    /// 它还配套一个 NSProcessInfoPowerStateDidChange 通知，外部改动也能第一时间知道。
    static func lowPowerModeEnabled() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// 切换低电量模式。装了特权助手就免密走 XPC，否则回退到 AppleScript 管理员授权（弹密码）。
    static func setLowPowerMode(_ on: Bool) {
        runPrivileged({ HelperClient.shared.setLowPowerMode(on, completion: $0) },
                      fallback: "/usr/bin/pmset -a lowpowermode \(on ? "1" : "0")")
    }

    // MARK: 合盖休眠（clamshell）
    /// 是否已禁用“合盖即休眠”。读 pmset 输出里的 SleepDisabled 字段。
    static func lidCloseSleepDisabled() -> Bool {
        for line in Shell.run("/usr/bin/pmset", ["-g"]).output.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.contains("1")
        }
        return false
    }

    /// 禁用/恢复“合盖即休眠”。装了特权助手就免密走 XPC，否则回退到 AppleScript 管理员授权（弹密码）。
    static func setLidCloseSleepDisabled(_ disabled: Bool) {
        runPrivileged({ HelperClient.shared.setDisableSleep(disabled, completion: $0) },
                      fallback: "/usr/bin/pmset -a disablesleep \(disabled ? "1" : "0")")
    }

    /// 走特权助手；**助手没能把事办成就退回输密码那条路**。
    ///
    /// 不能只看 `HelperClient.isInstalled`（它读的是 `SMAppService.status == .enabled`）：
    /// **「注册了」不等于「起得来」**。App 换一次签名（比如从 Apple Development 换成
    /// Developer ID 出包），launchd 记录的轻量代码要求（LWCR）就对不上新二进制，
    /// spawn 会以 EX_CONFIG 失败，可 `status` 照样报 `.enabled`。
    /// 实测日志：
    ///   launchd: Could not find and/or execute program specified by service:
    ///            3: No such process: Contents/MacOS/FreeSwitchHelper
    ///   last exit code = 78: EX_CONFIG   properties = ... needs LWCR update
    /// 那次「低电量模式开关点了没反应」就是这么来的——XPC 调用失败，返回值被 `_` 丢掉，
    /// 于是静默失效。现在失败就回退，最差也只是多输一次密码。
    private static func runPrivileged(_ viaHelper: @escaping (@escaping (Bool) -> Void) -> Void,
                                      fallback command: String) {
        // 密码框挂在那儿等用户输入的整段时间，脚本都不返回；这事绝不能占着主线程。
        //
        // `explainBroken` 的提示要**等密码流程走完**再出来。两个对话框同时堆在屏幕上，
        // 用户只会更糊涂——何况那句提示讲的正是「刚才为什么要你输密码」，
        // 密码还没输完就说这话，顺序是反的。
        func askPassword(explainBroken: Bool = false) {
            DispatchQueue.global(qos: .userInitiated).async {
                Shell.runAppleScript("do shell script \"\(command)\" with administrator privileges")
                Task { @MainActor in
                    SwitchStore.shared.refresh()
                    if explainBroken { HelperClient.shared.explainBrokenHelperOnce() }
                }
            }
        }
        guard HelperClient.shared.isInstalled else {
            askPassword()
            return
        }
        viaHelper { ok in
            if ok {
                Task { @MainActor in SwitchStore.shared.refresh() }
            } else {
                // 「装了助手却还要输密码」这件事本身是个故障，等密码走完说清楚并给条修的路。
                FreeSwitchTrigger.log.debug("helper call failed, falling back to password prompt")
                askPassword(explainBroken: true)
            }
        }
    }
}
