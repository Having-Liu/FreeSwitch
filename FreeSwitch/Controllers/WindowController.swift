import AppKit
import OSLog

/// 隐藏所有窗口：把其它 App 整个隐藏起来（等同于逐个按 ⌘H），再一键还原。
///
/// 用 NSRunningApplication 的 hide() / unhide()，既不需要「辅助功能」授权，也不用 AppleScript。
/// 只记住「我们隐藏的那几个」，还原时也只恢复它们——用户自己早就隐藏起来的 App，
/// 不该被我们顺手打开。
///
/// 已知限制：**访达的窗口藏不掉**。其它 App 全被隐藏后，系统必须激活一个 App，
/// 于是激活访达，而激活会自动取消隐藏。单独隐藏访达是成功的，只有在「其它都藏起来了」
/// 这个前提下不行；换 hideOtherApplications 也一样。这是 macOS 的行为，不是调用方式的问题。
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

    /// 分几轮收，每轮之前先激活自己。
    ///
    /// 一轮收不干净：实测第一轮过后还会剩两三个。原因是系统总得有一个「当前 App」，
    /// 我们把别的都藏了，它就去激活剩下的某一个，而激活会取消隐藏。
    /// 先激活 FreeSwitch 自己（菜单栏 App，没有窗口）占住这个位置，系统就不必再去激活别人；
    /// 实测这样能从「剩三个」收敛到「只剩访达」。
    private func hideAll() {
        Task { [weak self] in
            var recorded: [String] = []
            for pass in 0..<3 {
                guard let self else { return }
                NSApp.activate()
                try? await Task.sleep(nanoseconds: pass == 0 ? 120_000_000 : 300_000_000)
                let targeted = self.hidePass()
                for id in targeted where !recorded.contains(id) { recorded.append(id) }
                self.hiddenBundleIDs = recorded
                if targeted.isEmpty { break }   // 已经没有可藏的了
            }
        }
    }

    /// 隐藏一轮，返回这一轮真正被隐藏的 App。
    ///
    /// 不能只筛 `activationPolicy == .regular`：实测有 accessory 类型的 App 照样在屏幕上留窗口
    /// （菜单栏工具、悬浮面板一类），只按 regular 筛就会漏掉它们——这正是「总剩几个窗口」的原因。
    /// 所以再补一个条件：屏幕上确实有窗口的，也一并隐藏。
    private func hidePass() -> [String] {
        let windowOwners = pidsWithVisibleWindows()
        var targeted: [String] = []
        for app in NSWorkspace.shared.runningApplications
        where !app.isHidden
            && app.bundleIdentifier != Bundle.main.bundleIdentifier
            && (app.activationPolicy == .regular || windowOwners.contains(app.processIdentifier)) {
            // hide() 的返回值不可信：实测它返回 false，可一秒后那个 App 确实已经隐藏了。
            // 所以不拿返回值记账——先记下我们对谁发过请求，真实结果由 isHiding 按 isHidden 回读。
            _ = app.hide()
            if let id = app.bundleIdentifier, !targeted.contains(id) { targeted.append(id) }
        }
        FreeSwitchTrigger.log.debug("hide pass: \(targeted.count, privacy: .public) 个目标")
        return targeted
    }

    /// 屏幕上有普通窗口的进程。只取 layer 0（普通窗口层），排除桌面元素，
    /// 不读窗口标题——读标题才需要「屏幕录制」授权，只要 pid 和层级则不需要。
    private func pidsWithVisibleWindows() -> Set<pid_t> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var pids: Set<pid_t> = []
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            pids.insert(pid)
        }
        return pids
    }

    private func restore() {
        for id in hiddenBundleIDs { runningApp(for: id)?.unhide() }
        hiddenBundleIDs = []
    }

    private func runningApp(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
}
