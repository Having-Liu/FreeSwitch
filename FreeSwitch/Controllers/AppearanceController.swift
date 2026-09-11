import AppKit

/// 外观相关：黑暗模式、夜览、原彩显示。
enum AppearanceController {

    // MARK: 黑暗模式（通过“系统事件”切换，需要一次“自动化”授权）
    static func setDarkMode(_ on: Bool) {
        Shell.runAppleScript("""
        tell application "System Events"
            tell appearance preferences to set dark mode to \(on ? "true" : "false")
        end tell
        """)
    }

    static func isDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    // MARK: 夜览（私有框架 CoreBrightness）
    static var nightShiftSupported: Bool { CoreBrightnessBridge.nightShiftSupported() }
    static func isNightShiftOn() -> Bool { CoreBrightnessBridge.nightShiftEnabled() }
    static func setNightShift(_ on: Bool) { CoreBrightnessBridge.setNightShiftEnabled(on) }

    // MARK: 原彩显示（私有框架 CoreBrightness）
    static var trueToneSupported: Bool { CoreBrightnessBridge.trueToneSupported() }
    static func isTrueToneOn() -> Bool { CoreBrightnessBridge.trueToneEnabled() }
    static func setTrueTone(_ on: Bool) { CoreBrightnessBridge.setTrueToneEnabled(on) }
}
