import AppKit
import IOKit.pwr_mgt

/// 电源/屏幕：保持亮屏、显示器休眠、锁定屏幕、屏幕保护。
@MainActor
final class PowerController {
    static let shared = PowerController()

    private var assertionID: IOPMAssertionID = 0
    private(set) var keepAwake = false
    private(set) var keepAwakeDeadline: Date?   // nil = 一直亮屏（无限）
    private var autoOffTask: Task<Void, Never>?

    /// 剩余分钟（向上取整）；一直亮屏或未开启时返回 nil。
    var remainingMinutes: Int? {
        guard let deadline = keepAwakeDeadline else { return nil }
        return max(0, Int(ceil(deadline.timeIntervalSinceNow / 60)))
    }

    /// 保持亮屏。minutes 为 nil 表示一直亮屏；否则到点自动关闭。
    func setKeepAwake(_ on: Bool, minutes: Int? = nil) {
        autoOffTask?.cancel()
        autoOffTask = nil
        keepAwakeDeadline = nil

        if on {
            if assertionID == 0 {
                var id: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "FreeSwitch 保持亮屏" as CFString,
                    &id
                )
                if result == kIOReturnSuccess { assertionID = id }
            }
            keepAwake = assertionID != 0
            if keepAwake, let minutes, minutes > 0 {
                keepAwakeDeadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)
                autoOffTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
                    if Task.isCancelled { return }
                    self?.setKeepAwake(false)
                    SwitchStore.shared.refresh()
                }
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
