import AppKit

/// 系统杂项：隐藏桌面、显示隐藏文件、清空废纸篓、清空剪贴板、推出磁盘、Xcode 清理、勿扰。
enum SystemController {

    // MARK: 隐藏桌面图标
    static func setDesktopIconsHidden(_ hidden: Bool) {
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    static func desktopIconsHidden() -> Bool {
        let result = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
    }

    // MARK: 显示隐藏文件
    static func setShowHiddenFiles(_ show: Bool) {
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", show ? "true" : "false"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    static func showHiddenFiles() -> Bool {
        let result = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"])
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    // MARK: 清空废纸篓（会弹出访达的确认）
    static func emptyTrash() {
        Shell.runAppleScript("tell application \"Finder\" to empty the trash")
    }

    // MARK: 清空剪贴板
    static func emptyClipboard() {
        NSPasteboard.general.clearContents()
    }

    // MARK: 推出所有可推出/外置磁盘
    static func ejectAllRemovableDisks() {
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
    static func cleanXcodeCaches() -> Int {
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

    // MARK: 勿扰 / 专注（回退入口，真正的开关走 FocusBridge）
    static func openFocusSettings() {
        Shell.run("/usr/bin/open", ["x-apple.systempreferences:com.apple.Focus-Settings.extension"])
    }

    // MARK: 低电量模式
    static func lowPowerModeEnabled() -> Bool {
        let result = Shell.run("/usr/bin/pmset", ["-g"])
        for line in result.output.split(separator: "\n") where line.contains("lowpowermode") {
            return line.contains("1")
        }
        return false
    }

    /// 切换低电量模式。需要管理员权限，AppleScript 会弹出系统密码框。
    static func setLowPowerMode(_ on: Bool) {
        let value = on ? "1" : "0"
        Shell.runAppleScript("do shell script \"/usr/bin/pmset -a lowpowermode \(value)\" with administrator privileges")
    }
}
