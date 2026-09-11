import AppKit
import IOKit.pwr_mgt

/// 电源/屏幕：保持亮屏、显示器休眠、锁定屏幕、屏幕保护。
@MainActor
final class PowerController {
    static let shared = PowerController()

    private var assertionID: IOPMAssertionID = 0
    private(set) var keepAwake = false

    /// 保持亮屏：创建一个阻止显示器与系统闲置休眠的断言。
    func setKeepAwake(_ on: Bool) {
        if on {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "FreeSwitch 保持亮屏" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
                keepAwake = true
            }
        } else {
            if assertionID != 0 {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }
            keepAwake = false
        }
    }

    /// 立即让显示器休眠（不锁屏、不睡整机）。
    func sleepDisplayNow() {
        Shell.run("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// 启动屏幕保护。
    func startScreensaver() {
        Shell.run("/usr/bin/open", ["-a", "/System/Library/CoreServices/ScreenSaverEngine.app"])
    }

    /// 立即锁定屏幕。优先私有 API，失败则回退到快捷键。
    func lockScreen() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockFunction = @convention(c) () -> Int32
            _ = unsafeBitCast(symbol, to: LockFunction.self)()
        } else {
            Shell.runAppleScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
        }
    }
}
