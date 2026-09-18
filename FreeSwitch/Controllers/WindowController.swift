import AppKit

/// 隐藏所有窗口：把其它 App 整个隐藏起来（等同于逐个按 ⌘H），再一键还原。
///
/// 用 NSRunningApplication 的 hide() / unhide()，既不需要「辅助功能」授权，也不用 AppleScript。
/// 只记住「我们隐藏的那几个」，还原时也只恢复它们——用户自己早就隐藏起来的 App，
/// 不该被我们顺手打开。
@MainActor
final class WindowController {
    static let shared = WindowController()
    private init() {}

    private var hiddenBundleIDs: [String] = []

    /// 以系统的真实情况为准：只要我们隐藏的那些里还有仍处于隐藏状态的，就算「正在隐藏」。
    /// 用户中途自己恢复了某个 App，这里也能跟着变，不会一直显示开着。
    var isHiding: Bool {
        hiddenBundleIDs.contains { runningApp(for: $0)?.isHidden == true }
    }

    func setHidden(_ hide: Bool) {
        hide ? hideAll() : restore()
    }

    private func hideAll() {
        var hidden: [String] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular          // 只管有界面的 App，后台服务不动
            && !app.isHidden                            // 用户已经隐藏的，还原时不该被我们打开
            && app.bundleIdentifier != Bundle.main.bundleIdentifier {
            if app.hide(), let id = app.bundleIdentifier { hidden.append(id) }
        }
        hiddenBundleIDs = hidden
    }

    private func restore() {
        for id in hiddenBundleIDs { runningApp(for: id)?.unhide() }
        hiddenBundleIDs = []
    }

    private func runningApp(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
}
