import AppKit
import OSLog

/// 隐藏所有窗口：把其它 App 整个隐藏起来（等同于逐个按 ⌘H），再一键还原。
///
/// 用 NSRunningApplication 的 hide() / unhide()，既不需要「辅助功能」授权，也不用 AppleScript。
/// 只记住「我们隐藏的那几个」，还原时也只恢复它们——用户自己早就隐藏起来的 App，
/// 不该被我们顺手打开。
///
/// 访达是个例外：它藏不掉。其它 App 全被隐藏后，系统必须激活一个 App，于是激活访达，
/// 而激活会自动取消隐藏。单独隐藏访达是成功的，只有在「其它都藏起来了」这个前提下不行；
/// 换 hideOtherApplications 也一样。这是 macOS 的行为，不是调用方式的问题。
/// 所以对访达改用另一条路：让它把自己的窗口折叠到程序坞，见下面的 minimizeFinderWindows。
@MainActor
final class WindowController {
    static let shared = WindowController()
    private init() {}

    private var hiddenBundleIDs: [String] = []

    /// 以系统的真实情况为准：只要我们隐藏的那些里还有仍处于隐藏状态的，就算「正在隐藏」。
    /// 用户中途自己恢复了某个 App，这里也能跟着变，不会一直显示开着。
    ///
    /// 折叠掉的访达窗口只看「我们收了几个」，不回读访达的真实状态：这个值每 5 秒被核对一次，
    /// 为它每次都发一条 AppleEvent 不划算。代价是用户手动展开窗口后开关不会立刻翻回去。
    var isHiding: Bool {
        !minimizedFinderWindows.isEmpty
            || hiddenBundleIDs.contains { runningApp(for: $0)?.isHidden == true }
    }

    func setHidden(_ hide: Bool) {
        if hide {
            hideAll()
        } else {
            restore()
            restoreFinderWindows()
        }
    }

    // MARK: 访达

    /// 访达整个 App 藏不掉（见上面的说明），但可以让它把自己的窗口折叠到程序坞——
    /// 屏幕上的效果一样，而且不动窗口里的内容。只记「原本没折叠」的那些，还原时也只恢复它们，
    /// 用户自己早就最小化的窗口不该被我们顺手打开。
    ///
    /// 三个坑都是实测撞出来的，改之前先读：
    ///  1. 必须用 `Finder window`，不能用泛称的 `window`。后者会把访达挂住：
    ///     `count of windows` 实测两次都是等到 AppleEvent 超时（-1712），
    ///     而同一时刻 `count of Finder windows` 立刻返回 2。
    ///  2. 不能 `repeat with w in (every Finder window)`：这样拿到的是
    ///     「item 1 of every Finder window」这种引用，访达解不开，报 -1728。要按下标取。
    ///  3. 不能边遍历边折叠。折叠会把窗口挪到最后，而下标就是前后次序，
    ///     于是第二轮取到的正是刚折叠的那个，真正该折叠的反倒被跳过——
    ///     实测两个窗口只收掉一个。所以先收集 id，再按 id 逐个折叠。
    ///
    /// 另外一律套 `with timeout`：访达一旦卡住（比如正在做一个停不下来的文件操作），
    /// 默认要等两分钟才超时，而这段脚本跑在主线程上，整个 App 会跟着僵住。
    private var minimizedFinderWindows: [Int] = []

    private func minimizeFinderWindows() {
        let script = """
        with timeout of 5 seconds
        tell application "Finder"
            set ids to {}
            repeat with i from 1 to (count of Finder windows)
                if collapsed of Finder window i is false then set end of ids to (id of Finder window i)
            end repeat
            repeat with theID in ids
                set collapsed of (Finder window id (theID as integer)) to true
            end repeat
            set AppleScript's text item delimiters to linefeed
            return ids as text
        end tell
        end timeout
        """
        let ids = Shell.runAppleScript(script) ?? ""
        minimizedFinderWindows = ids.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        FreeSwitchTrigger.log.debug("finder: 折叠 \(self.minimizedFinderWindows.count, privacy: .public) 个窗口")
    }

    private func restoreFinderWindows() {
        guard !minimizedFinderWindows.isEmpty else { return }
        let list = minimizedFinderWindows.map(String.init).joined(separator: ", ")
        // 窗口可能已经被用户关掉了，id 找不到会报错——逐个 try，别让一个失败带走其余的。
        Shell.runAppleScript("""
        with timeout of 5 seconds
        tell application "Finder"
            repeat with theID in {\(list)}
                try
                    set collapsed of (Finder window id theID) to false
                end try
            end repeat
        end tell
        end timeout
        """)
        minimizedFinderWindows = []
    }

    /// 分几轮收，每轮之前先激活自己。
    ///
    /// 一轮收不干净：实测第一轮过后还会剩两三个。原因是系统总得有一个「当前 App」，
    /// 我们把别的都藏了，它就去激活剩下的某一个，而激活会取消隐藏。
    /// 先激活 FreeSwitch 自己（菜单栏 App，没有窗口）占住这个位置，系统就不必再去激活别人；
    /// 实测这样能从「剩三个」收敛到「只剩访达」。
    private func hideAll() {
        Task { [weak self] in
            self?.minimizeFinderWindows()
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
