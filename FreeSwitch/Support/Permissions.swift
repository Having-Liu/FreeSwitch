import AppKit
import OSLog

/// 权限的**读**与**请求**，严格分开。
///
/// 这个 App 的原则是：没真用到就不要去碰。只要发一条 AppleEvent、请求一次辅助功能，
/// 系统就会把授权弹窗甩到用户脸上——而那时候用户可能只是刚装上、还没点过任何开关。
/// 所以每一项都有一个**不触发弹窗**的读法，弹窗只在用户自己按下「请求授权」时才出现。
enum Permission {

    enum State {
        case granted        // 已授权
        case notDetermined  // 还没问过——可以请求
        case denied         // 问过被拒——只能去系统设置里改

        var isGranted: Bool { self == .granted }
    }

    // MARK: 自动化（AppleEvent）

    /// 查某个 App 的自动化授权，**不问用户**。
    ///
    /// `askUserIfNeeded: false` 时的返回码：
    ///  - `noErr`                            已授权
    ///  - `errAEEventWouldRequireUserConsent`(-1744) 还没问过
    ///  - `errAEEventNotPermitted`           (-1743) 问过被拒
    /// **目标没在跑时这个 API 什么也答不了。**
    ///
    /// 「系统事件」是个按需启动的后台 agent，平时根本不在进程列表里；这时查询返回
    /// `procNotFound`(-600)，既读不出授权状态，`askUserIfNeeded: true` 也弹不出授权框——
    /// 这正是「点了请求授权没反应」的原因（实测：System Events 没在跑 → -600，
    /// 运行中的访达 → 0）。
    ///
    /// 所以 -600 不能当成任何一种结论，而要退回上一次**确定过**的答案。
    /// 否则同一项会随着目标 App 的起落在「已授权」和「请求授权」之间来回跳。
    static func automation(of bundleID: String) -> State {
        var target = AEAddressDesc()
        let data = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, data, data.count, &target) == noErr else {
            return remembered(bundleID) ?? .notDetermined
        }
        defer { AEDisposeDesc(&target) }

        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) {
        case noErr:
            remember(.granted, for: bundleID)
            return .granted
        case OSStatus(errAEEventNotPermitted):
            remember(.denied, for: bundleID)
            return .denied
        case OSStatus(procNotFound):
            return remembered(bundleID) ?? .notDetermined
        default:
            return .notDetermined
        }
    }

    /// 触发自动化的系统弹窗。只应该由用户的点击调用。
    ///
    /// 这里**不能**只调 `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: true)`：
    /// 目标没在跑时它直接返回 -600，按钮按下去毫无反应。
    /// 改成发一条最无害的 AppleScript——脚本引擎会顺手把目标拉起来，
    /// TCC 的授权框也就跟着出现了。执行会阻塞到用户点完，所以扔到后台线程。
    static func requestAutomation(of bundleID: String,
                                  _ completion: @escaping @MainActor (State) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: "tell application id \"\(bundleID)\" to return name")
            var errorInfo: NSDictionary?
            let output = script?.executeAndReturnError(&errorInfo)

            // 结论直接从这一次的执行结果得出，**不要**回头再查一次
            // `AEDeterminePermissionToAutomateTarget`：像系统事件这样的后台 agent
            // 服务完这条事件就立刻退出了，再查只会拿到 -600，于是刚授权完按钮还是「请求授权」。
            // 脚本跑通了本身就是「已授权」的铁证。
            let state: State
            if let code = (errorInfo?["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue {
                state = code == AutomationPermission.notAuthorized ? .denied : .notDetermined
            } else if output != nil {
                state = .granted
            } else {
                state = .notDetermined
            }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if state != .notDetermined { remember(state, for: bundleID) }
                    completion(state)
                }
            }
        }
    }

    // MARK: 记住上一次确定过的答案

    private static func key(_ bundleID: String) -> String { "automationState." + bundleID }

    private static func remember(_ state: State, for bundleID: String) {
        UserDefaults.standard.set(state == .granted, forKey: key(bundleID))
    }

    private static func remembered(_ bundleID: String) -> State? {
        guard let granted = UserDefaults.standard.object(forKey: key(bundleID)) as? Bool else { return nil }
        return granted ? .granted : .denied
    }

    // MARK: 辅助功能（锁定键盘要用）

    /// `AXIsProcessTrusted()` 是纯查询，不弹窗。
    /// 注意它没有「没问过」和「被拒」的区别——系统只告诉你信不信任，所以未授权一律当 notDetermined，
    /// 让用户可以再点一次（重复请求是安全的，已经拒过的话系统自己不会再弹）。
    static var accessibility: State {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: 去系统设置

    static func openSettings(_ pane: String) {
        Shell.run("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?\(pane)"])
    }
}
