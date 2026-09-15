import Foundation

// 外部入口（控制中心控件 / 快捷指令 / Siri 的 App Intent）通过 Darwin 通知触发某个开关，
// 主 App 收到后执行真正的操作。通知名里带开关 id：group.com.freeswitch.FreeSwitch.trigger.<id>

private let fsTriggerCallback: CFNotificationCallback = { _, _, cfName, _, _ in
    let prefix = "group.com.freeswitch.FreeSwitch.trigger."
    guard let raw = cfName?.rawValue as String?, raw.hasPrefix(prefix) else { return }
    let id = String(raw.dropFirst(prefix.count))
    DispatchQueue.main.async {
        MainActor.assumeIsolated { SwitchStore.shared.activate(id) }
    }
}

enum FreeSwitchTrigger {
    static let prefix = "group.com.freeswitch.FreeSwitch.trigger."

    /// 发出触发（供 App 内部/测试用；扩展侧有自己的一份实现）。
    static func post(_ id: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName((prefix + id) as CFString), nil, nil, true
        )
    }

    /// 注册监听：为每个已知开关注册一个 Darwin 观察者，收到即执行。
    static func startObserving() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for id in SwitchCatalog.defaultIDs {
            CFNotificationCenterAddObserver(
                center, nil, fsTriggerCallback,
                (prefix + id) as CFString, nil, .deliverImmediately
            )
        }
    }
}
