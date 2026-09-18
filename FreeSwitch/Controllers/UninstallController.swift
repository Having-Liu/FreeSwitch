import AppKit
import ServiceManagement

/// 彻底卸载。
///
/// 分两段完成：
///  1. 需要 App 自己身份的几步，在退出前于进程内完成——还原「合盖不休眠」、解锁键盘、
///     注销特权助手与开机自启（SMAppService 只能由 App 本身注销）。
///  2. 删除文件和偏好，交给随 App 打包的 uninstall.sh，在 App 退出之后执行。
///     那份脚本也是命令行 scripts/uninstall.sh 的实现，两个入口共用一套。
///
/// 为什么不再在进程内删文件——两点都实测过：
///  - App 还活着时删掉的偏好，会在退出时被写回来（残留的偏好里有设置窗口的位置，
///    那是 AppKit 在窗口关闭时自动写的）；
///  - 扩展的沙盒容器、App 不再声明的旧 group 容器，由 App 发起的删除会静默失败，
///    按容器的创建时间核对过，是压根没删掉而不是删了又被重建。
///    脚本里对这些有兜底（交给访达移到废纸篓）和逐项核对，删不掉会通知并在访达里标出来。
@MainActor
enum UninstallController {

    // MARK: 入口

    static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L("彻底卸载 FreeSwitch？")
        alert.informativeText = L("""
        会删除并还原下面这些东西：

        • FreeSwitch.app 本身
        • 控制中心里的 FreeSwitch 控件与其扩展登记
        • 免密特权助手、开机自启登录项
        • 你的全部设置：开关顺序、显示项、全局快捷键
        • 「合盖也不休眠」改过的系统电源设置（还原为默认）
        • 授予过的隐私权限（辅助功能、自动化等）

        沙盒容器的根目录归系统管，App 自己删不掉，只能把里面清空；
        如果仍有没清掉的，卸载完会通知你，并在访达里标出来。

        另外请记得拉开控制中心，把 FreeSwitch 的控件长按移除——
        只要它们还在那儿，系统就会为它们把扩展的容器重新建出来。

        这一步不可撤销。卸载开始后 FreeSwitch 会立即退出。
        """)
        alert.addButton(withTitle: L("彻底卸载"))
        alert.addButton(withTitle: L("取消"))
        alert.buttons.first?.hasDestructiveAction = true

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        perform()
    }

    // MARK: 执行

    private static func perform() {
        // 这几步需要 App 自己的身份，必须在退出前做。
        PowerController.shared.recoverClamshellIfNeeded()   // 否则卸载后合盖永不休眠
        InputBlocker.shared.setKeyboardLocked(false)
        HelperClient.shared.uninstall()
        try? SMAppService.mainApp.unregister()

        let verifiedEmpty = wipeContainerData()

        guard launchCleanupScript(verifiedEmpty: verifiedEmpty) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("没能启动卸载脚本")
            alert.informativeText = L("App 包里缺少 uninstall.sh，文件和设置没有被删除。请在终端运行项目里的 scripts/uninstall.sh 完成卸载。")
            alert.runModal()
            return
        }
        NSApp.terminate(nil)
    }

    /// 趁 App 还活着，用 App 自己的身份把容器里的数据清掉，并**当场核对**清干净了没有。
    /// 返回核对通过的容器路径。
    ///
    /// 这一步不能留给退出后那个脚本：脚本虽然继承了 App 的身份，却不带 App 的 entitlement，
    /// group 容器连列目录都不允许——实测它因此把「列不出东西」当成「里面是空的」，
    /// 谎报成已清空。容器根目录仍旧删不掉（归 containermanagerd 管），
    /// 但至少数据是在这里、由有权限的一方清干净的。
    ///
    /// 核对结果要带给脚本：否则脚本只能说「没权限查看，无法确认」，于是明明已经清干净了，
    /// 用户还是收到一条「卸载未完全」的通知——实测过一次，比谎报好，但仍旧不准。
    private static func wipeContainerData() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let containers = [
            home.appendingPathComponent("Library/Containers/\(FreeSwitchTrigger.extensionBundleID)"),
            home.appendingPathComponent("Library/Group Containers/\(FreeSwitchTrigger.suite)"),
        ]
        return containers.filter { container in
            wipe(container)
            return remainingFileCount(in: container) == 0
        }
    }

    private static let containerMetadata = ".com.apple.containermanagerd.metadata.plist"

    /// 删掉容器里除系统元数据之外的一切。根目录本身留着——那是删不掉的。
    private static func wipe(_ container: URL) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: container, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent != containerMetadata {
            try? manager.removeItem(at: item)
        }
    }

    /// 只数真正的文件。清空之后系统会把 Data/ 下那套标准骨架（Desktop、Documents…）
    /// 重新建出来，那是系统的脚手架，不是残留数据。
    private static func remainingFileCount(in container: URL) -> Int {
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: container, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let url as URL in walker {
            guard url.lastPathComponent != containerMetadata,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            count += 1
        }
        return count
    }

    /// 把脚本拷到临时目录再运行：脚本会删掉 App 包，不能让它从即将被删除的包里执行。
    /// 子进程在 App 退出后继续运行（会被 launchd 接管），它会先等 App 进程完全退出再动手。
    private static func launchCleanupScript(verifiedEmpty: [URL]) -> Bool {
        guard let bundled = Bundle.main.url(forResource: "uninstall", withExtension: "sh") else { return false }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("FreeSwitch-uninstall.sh")
        try? FileManager.default.removeItem(at: temp)
        guard (try? FileManager.default.copyItem(at: bundled, to: temp)) != nil else { return false }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        var arguments = [temp.path, "--from-app", "--app-path", Bundle.main.bundleURL.path]
        for url in verifiedEmpty { arguments += ["--verified-empty", url.path] }
        task.arguments = arguments
        return (try? task.run()) != nil
    }
}
