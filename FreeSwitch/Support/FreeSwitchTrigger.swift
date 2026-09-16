import Foundation
import WidgetKit

// 控制中心控件 ↔ 主 App 的桥。
//  - 控件发 Darwin 通知：<AppGroup>.trigger.<id>（动作）
//    或 .set.<id>.<1|0>（开关设为指定值）。主 App 监听并执行。
//  - 主 App 把开关状态写进共享 App Group，供控件显示；变化后让控制中心刷新。

// 这个前缀只用来给 Darwin 通知划命名空间（沙盒扩展要用带 App Group 前缀的通知名），
// 状态回读不走 App Group —— 见下面 statesURL 的说明。
// macOS 的 App Group 必须以 Team ID 开头，iOS 那套裸 "group." 前缀在 macOS 上
// 无法被签名自证。Fork 时把 MXHBUQH27V 换成你自己的 Team ID。
private let fsPrefix = "MXHBUQH27V.group.com.freeswitch.FreeSwitch."

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
    static let suite = "MXHBUQH27V.group.com.freeswitch.FreeSwitch"

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

    /// 状态写进**控件扩展自己的沙盒容器**，而不是 App Group 容器。
    /// App Group 要沙盒真正授予才能用，本地签名下扩展常常拿不到容器（containerURL 返回 nil），
    /// 于是状态永远读成 false，控制中心里的开关一翻就弹回、活像个只读指示器。
    /// 扩展读自己的容器无需任何 entitlement，而我们是非沙盒 App，可以直接往里写 —— 最稳。
    static let extensionBundleID = "com.freeswitch.FreeSwitch.Controls"

    static var statesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extensionBundleID)")
            .appendingPathComponent("Data/Library/Application Support/FreeSwitch/states.json")
    }

    /// 把开关状态写给控件，并刷新控制中心里的显示。
    /// 动作控件的执行阶段（idle / running / done）。开关状态是 Bool，阶段是字符串，
    /// 两种 schema 不同，所以分开两个文件，各自解码干净。
    static var phasesURL: URL {
        statesURL.deletingLastPathComponent().appendingPathComponent("phases.json")
    }

    /// 接收已经拼好的字典，不要自己从 items 再拼一遍——
    /// 那样调用方额外塞进去的键会在路上被悄悄丢掉（这个坑踩过一次）。
    @MainActor
    static func publishStates(_ dict: [String: Bool], phases: [String: String]) {
        write(statesURL, dict)
        write(phasesURL, phases)
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    private static func write<T: Encodable>(_ url: URL, _ value: T) {
        // 容器由系统在扩展首次运行时创建。它还不存在时不要自己造目录，
        // 免得留下一个畸形容器让 containermanagerd 犯迷糊 —— 等扩展跑起来，下一次发布自然会写进去。
        let container = url.deletingLastPathComponent()
            .deletingLastPathComponent()   // Application Support
            .deletingLastPathComponent()   // Library
        guard FileManager.default.fileExists(atPath: container.path),
              let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
