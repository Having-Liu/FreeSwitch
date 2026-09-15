import Foundation
import WidgetKit

// 控制中心控件 ↔ 主 App 的桥。
//  - 控件发 Darwin 通知：group.com.freeswitch.FreeSwitch.trigger.<id>（动作）
//    或 .set.<id>.<1|0>（开关设为指定值）。主 App 监听并执行。
//  - 主 App 把开关状态写进共享 App Group，供控件显示；变化后让控制中心刷新。

private let fsPrefix = "group.com.freeswitch.FreeSwitch."

private let fsCallback: CFNotificationCallback = { _, _, cfName, _, _ in
    guard let raw = cfName?.rawValue as String?, raw.hasPrefix(fsPrefix) else { return }
    let rest = String(raw.dropFirst(fsPrefix.count))       // "trigger.darkMode" / "set.muteMic.1"
    let parts = rest.split(separator: ".").map(String.init)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            if parts.count >= 2, parts[0] == "trigger" {
                SwitchStore.shared.activate(parts[1])
            } else if parts.count >= 3, parts[0] == "set" {
                SwitchStore.shared.setSwitch(parts[1], on: parts[2] == "1")
            }
        }
    }
}

enum FreeSwitchTrigger {
    static let suite = "group.com.freeswitch.FreeSwitch"
    static let statesKey = "control.states"

    static func startObserving() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for id in SwitchCatalog.defaultIDs {
            add(center, fsPrefix + "trigger." + id)
            if SwitchCatalog.item(id)?.kind == .toggle {
                add(center, fsPrefix + "set." + id + ".1")
                add(center, fsPrefix + "set." + id + ".0")
            }
        }
    }

    private static func add(_ center: CFNotificationCenter?, _ name: String) {
        CFNotificationCenterAddObserver(center, nil, fsCallback, name as CFString, nil, .deliverImmediately)
    }

    /// 把开关状态写进共享 App Group 并刷新控制中心里的控件。
    @MainActor
    static func publishStates(_ items: [SwitchItem]) {
        var dict: [String: Bool] = [:]
        for item in items where item.kind == .toggle { dict[item.id] = item.isOn }
        UserDefaults(suiteName: suite)?.set(dict, forKey: statesKey)
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }
}
