import AppKit
import IOKit.pwr_mgt

/// 电源/屏幕：保持亮屏、显示器休眠、锁定屏幕、屏幕保护。
@MainActor
final class PowerController {
    static let shared = PowerController()

    private var assertionID: IOPMAssertionID = 0
    private(set) var keepAwake = false
    private(set) var keepAwakeDeadline: Date?   // nil = 一直亮屏（无限）
    private(set) var clamshell = false          // 合盖也不休眠
    private(set) var totalMinutes: Int?         // 本次设定的总时长，用来算剩余比例

    /// 剩余比例，供磁贴底边的量规用。「一直亮屏」没有终点，视作满格。
    var progress: Double? {
        guard keepAwake else { return nil }
        guard let total = totalMinutes, total > 0, let left = remainingMinutes else { return 1 }
        return min(1, max(0, Double(left) / Double(total)))
    }
    private var autoOffTask: Task<Void, Never>?
    private let clamshellFlagKey = "keepAwake.clamshellActive"

    /// 剩余分钟（向上取整）；一直亮屏或未开启时返回 nil。
    var remainingMinutes: Int? {
        guard let deadline = keepAwakeDeadline else { return nil }
        return max(0, Int(ceil(deadline.timeIntervalSinceNow / 60)))
    }

    /// 保持亮屏。minutes 为 nil 表示一直亮屏；clamshell 为“合盖也不休眠”。
    func setKeepAwake(_ on: Bool, minutes: Int? = nil, clamshell wantClamshell: Bool = false) {
        autoOffTask?.cancel()
        autoOffTask = nil
        keepAwakeDeadline = nil
        totalMinutes = on ? minutes : nil

        if on {
            if assertionID == 0 {
                var id: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    // 不本地化：这是 `pmset -g assertions` 里显示的诊断标识，不是界面文案。
                    "FreeSwitch 保持亮屏" as CFString,
                    &id
                )
                if result == kIOReturnSuccess { assertionID = id }
            }
            keepAwake = assertionID != 0
            applyClamshell(keepAwake && wantClamshell)
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
            applyClamshell(false)
        }
    }

    /// 只在状态变化时调用 pmset（避免无变化时反复弹密码框）。
    private func applyClamshell(_ want: Bool) {
        guard want != clamshell else { return }
        SystemController.setLidCloseSleepDisabled(want)
        clamshell = want
        UserDefaults.standard.set(want, forKey: clamshellFlagKey)
    }

    /// App 启动时调用：若上次异常退出（崩溃/强退）遗留了“合盖不休眠”，恢复系统设置，
    /// 避免电脑一直装在包里不睡。只根据我们自己的标记恢复，不动别人设的值。
    func recoverClamshellIfNeeded() {
        guard UserDefaults.standard.bool(forKey: clamshellFlagKey) else { return }
        SystemController.setLidCloseSleepDisabled(false)
        UserDefaults.standard.set(false, forKey: clamshellFlagKey)
        clamshell = false
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
