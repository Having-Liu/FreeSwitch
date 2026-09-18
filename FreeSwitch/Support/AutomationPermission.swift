import AppKit

/// 「自动化」权限缺失时的提示。
///
/// 黑暗模式、自动隐藏程序坞、清空废纸篓这些开关要通过「系统事件」或「访达」执行。
/// 没有授权时 AppleScript 会直接失败，而失败原本只写进日志——用户看到的是
/// 「点了开关毫无反应」，完全无从判断原因（实测就发生过：彻底卸载会重置隐私授权，
/// 重装之后这几个开关全部静默失效）。所以这里把它挑明，并直接送到对应的设置页。
@MainActor
enum AutomationPermission {
    /// macOS 拒绝发送 Apple 事件时的错误码。
    static let notAuthorized = -1743

    private static var explained = false

    /// 整个运行期只提示一次，免得每点一次开关就弹一次。
    static func explainOnce() {
        guard !explained else { return }
        explained = true

        let alert = NSAlert()
        alert.messageText = L("这个开关需要「自动化」权限")
        alert.informativeText = L("""
        黑暗模式、自动隐藏程序坞、清空废纸篓这几个开关，要通过「系统事件」或「访达」来执行。macOS 目前不允许 FreeSwitch 这么做，所以刚才那次点击没有产生任何效果。

        打开「系统设置 › 隐私与安全性 › 自动化」，把 FreeSwitch 下面的「系统事件」和「访达」打开即可。

        （彻底卸载会重置隐私授权，重装后需要重新授权一次。）
        """)
        alert.addButton(withTitle: L("打开设置"))
        alert.addButton(withTitle: L("以后再说"))

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
