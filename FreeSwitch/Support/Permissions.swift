import AppKit
import CoreBluetooth
import OSLog

/// 权限的**读**与**请求**，严格分开。
///
/// 这个 App 的原则是：没真用到就不要去碰。只要碰一下 IOBluetooth、发一条 AppleEvent，
/// 系统就会把授权弹窗甩到用户脸上——而那时候用户可能只是刚装上、还没点过任何开关。
/// 所以每一项都有一个**不触发弹窗**的读法，弹窗只在用户自己按下「请求授权」时才出现。
enum Permission {

    enum State {
        case granted        // 已授权
        case notDetermined  // 还没问过——可以请求
        case denied         // 问过被拒——只能去系统设置里改

        var isGranted: Bool { self == .granted }
    }

    // MARK: 蓝牙（耳机连接）

    /// `CBManager.authorization` 是个纯查询，不会实例化 central、也不会弹窗。
    /// 不能用「试着列一次已配对设备，看是不是空的」来判断——那一下就把弹窗招出来了。
    static var bluetooth: State {
        switch CBManager.authorization {
        case .allowedAlways:  return .granted
        case .notDetermined:  return .notDetermined
        default:              return .denied      // denied / restricted
        }
    }

    /// 真正触发系统弹窗。只应该由用户的点击调用。
    ///
    /// 实例化 CBCentralManager 是唯一能主动把弹窗叫出来的方式；
    /// 拿着这个实例不放，否则它会在回调前被释放。
    private static var bluetoothRequester: CBCentralManager?

    static func requestBluetooth(_ completion: @escaping @MainActor (State) -> Void) {
        guard bluetooth == .notDetermined else {
            completion(bluetooth)
            return
        }
        bluetoothRequester = CBCentralManager(delegate: nil, queue: nil)
        // 系统弹窗是异步的，轮询到状态不再是「没问过」为止（最多 30 秒）。
        pollBluetooth(remaining: 60, completion)
    }

    private static func pollBluetooth(remaining: Int,
                                      _ completion: @escaping @MainActor (State) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                let state = bluetooth
                if state != .notDetermined || remaining <= 0 {
                    bluetoothRequester = nil
                    completion(state)
                } else {
                    pollBluetooth(remaining: remaining - 1, completion)
                }
            }
        }
    }

    // MARK: 自动化（AppleEvent）

    /// 查某个 App 的自动化授权，**不问用户**。
    ///
    /// `askUserIfNeeded: false` 时的返回码：
    ///  - `noErr`                            已授权
    ///  - `errAEEventWouldRequireUserConsent`(-1744) 还没问过
    ///  - `errAEEventNotPermitted`           (-1743) 问过被拒
    static func automation(of bundleID: String) -> State {
        var target = AEAddressDesc()
        let data = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, data, data.count, &target) == noErr else {
            return .notDetermined
        }
        defer { AEDisposeDesc(&target) }

        // 注意 -600（procNotFound）：目标 App 没在跑时就是这个码，不能当成「被拒」。
        // 实测 com.apple.Music 没启动时 wildcard 查询返回 -600，而运行中的访达/系统事件返回 0。
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) {
        case noErr:                              return .granted
        case OSStatus(errAEEventNotPermitted):   return .denied
        default:                                 return .notDetermined
        }
    }

    /// 触发自动化的系统弹窗。只应该由用户的点击调用。
    /// 这个调用会阻塞到用户点完，所以扔到后台线程去。
    static func requestAutomation(of bundleID: String,
                                  _ completion: @escaping @MainActor (State) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var target = AEAddressDesc()
            let data = Array(bundleID.utf8)
            if AECreateDesc(typeApplicationBundleID, data, data.count, &target) == noErr {
                _ = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
                AEDisposeDesc(&target)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(automation(of: bundleID)) }
            }
        }
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
