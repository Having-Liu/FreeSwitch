import AppKit
import ServiceManagement

/// 彻底卸载：把 App 在系统里登记过的一切清干净，再删掉自己。
///
/// 单纯把 App 拖进废纸篓是不够的 —— 控制中心的扩展登记（pluginkit）、
/// 控件快照缓存（chronod）、特权助手与登录项（SMAppService）、
/// 以及「合盖也不休眠」改过的 pmset 设置，都会留在系统里继续生效。
@MainActor
enum UninstallController {

    /// 卸载过的 App Group（含历史命名），卸载时一并清掉。
    private static let groupIDs = [
        FreeSwitchTrigger.suite,
        "group.com.freeswitch.FreeSwitch",   // 早期版本用过的 iOS 式命名
    ]

    private static let bundleID = "com.freeswitch.FreeSwitch"
    private static let extensionID = "com.freeswitch.FreeSwitch.Controls"

    // MARK: 入口

    static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "彻底卸载 FreeSwitch？"
        alert.informativeText = """
        会删除并还原下面这些东西：

        • FreeSwitch.app 本身
        • 控制中心里的 FreeSwitch 控件与其扩展登记
        • 免密特权助手、开机自启登录项
        • 你的全部设置：开关顺序、显示项、全局快捷键、耳机选择
        • 「合盖也不休眠」改过的系统电源设置（还原为默认）

        这一步不可撤销。卸载完成后 FreeSwitch 会自动退出。
        """
        alert.addButton(withTitle: "彻底卸载")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        perform()
    }

    // MARK: 清理

    private static func perform() {
        // 1) 先还原改过的系统设置，否则卸载后合盖将永不休眠。
        PowerController.shared.recoverClamshellIfNeeded()

        // 2) 关掉所有还开着的常驻开关（锁键盘的事件拦截等）。
        InputBlocker.shared.setKeyboardLocked(false)

        // 3) 注销特权助手与开机自启。
        HelperClient.shared.uninstall()
        try? SMAppService.mainApp.unregister()

        // 4) 注销控制中心扩展。pluginkit 按 bundle id 只认一份，
        //    不注销的话残留登记会一直指向一个已经不存在的包。
        let appexPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/FreeSwitchControls.appex").path
        _ = Shell.run("/usr/bin/pluginkit", ["-r", appexPath])

        // 5) 删掉用户数据。
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths: [URL] = [
            home.appendingPathComponent("Library/Preferences/\(bundleID).plist"),
            home.appendingPathComponent("Library/Preferences/\(extensionID).plist"),
            home.appendingPathComponent("Library/Caches/\(bundleID)"),
            home.appendingPathComponent("Library/Caches/\(extensionID)"),
            home.appendingPathComponent("Library/HTTPStorages/\(bundleID)"),
            home.appendingPathComponent("Library/Saved Application State/\(bundleID).savedState"),
            home.appendingPathComponent("Library/Containers/\(extensionID)"),
        ]
        for group in groupIDs {
            paths.append(home.appendingPathComponent("Library/Group Containers/\(group)"))
        }
        for path in paths { try? FileManager.default.removeItem(at: path) }

        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        // 6) 剩下的必须在本进程退出之后做（删掉正在运行的自己），
        //    交给一个脱离本进程的 shell：等我们退出，再删包、注销 LaunchServices、
        //    最后重启 chronod/ControlCenter 把控件快照缓存清掉。
        scheduleSelfRemoval()

        NSApp.terminate(nil)
    }

    private static func scheduleSelfRemoval() {
        let appPath = Bundle.main.bundleURL.path
        let lsregister = "/System/Library/Frameworks/CoreServices.framework"
            + "/Frameworks/LaunchServices.framework/Support/lsregister"

        let script = """
        while pgrep -x FreeSwitch >/dev/null 2>&1; do sleep 0.5; done
        "\(lsregister)" -u "\(appPath)" 2>/dev/null
        rm -rf "\(appPath)"
        killall chronod 2>/dev/null
        killall ControlCenter 2>/dev/null
        """

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        try? task.run()   // 不 wait：本进程马上就退出了，交给它自己跑完
    }
}
