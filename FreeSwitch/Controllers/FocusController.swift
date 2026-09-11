import AppKit

/// 勿扰 / 专注：现代 macOS 不允许第三方 App 直接切换专注（私有框架需 Apple 专属授权）。
/// 官方许可的方式是「快捷指令」——用户一次性建一个名为 "FreeSwitch DND" 的快捷指令
/// （含「设定专注 → 勿扰 → 切换」动作），之后本 App 用 `shortcuts run` 触发它。
enum FocusController {
    static let shortcutName = "FreeSwitch DND"

    static var shortcutsAvailable: Bool {
        FileManager.default.fileExists(atPath: "/usr/bin/shortcuts")
    }

    /// 用户是否已创建对应快捷指令。
    static func isConfigured() -> Bool {
        guard shortcutsAvailable else { return false }
        let output = Shell.run("/usr/bin/shortcuts", ["list"]).output
        return output.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == shortcutName
        }
    }

    /// 触发切换。
    static func toggle() {
        Shell.run("/usr/bin/shortcuts", ["run", shortcutName])
    }

    static func openShortcutsApp() {
        Shell.run("/usr/bin/open", ["-a", "Shortcuts"])
    }
}
