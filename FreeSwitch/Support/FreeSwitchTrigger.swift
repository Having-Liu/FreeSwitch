import Foundation
import WidgetKit
import OSLog

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
    DispatchQueue.main.async {
        MainActor.assumeIsolated { FreeSwitchTrigger.apply(rest) }
    }
}

enum FreeSwitchTrigger {
    static let suite = "MXHBUQH27V.group.com.freeswitch.FreeSwitch"

    /// 诊断用，和扩展共用一个 subsystem，好把两边的时间线并到一起看。debug 级，平时不落盘。
    static let log = Logger(subsystem: "com.freeswitch.FreeSwitch", category: "app")

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

    // MARK: 冷启动时的待办请求

    /// 控件在主 App 没运行时留下的请求（一个请求一个文件，见扩展里的 `CtrlShared.enqueue`）。
    static var pendingDir: URL {
        statesURL.deletingLastPathComponent().appendingPathComponent("pending", isDirectory: true)
    }

    /// 超过这个时间还没被取走的请求就丢掉。
    ///
    /// 拉起 App 失败、或者用户把刚起来的 App 又退了，请求就会一直躺在那儿。
    /// 不设期限的话，它会在几小时后某次手动启动时突然执行——那已经不是用户要的了。
    private static let pendingTTL: TimeInterval = 60

    /// 取走并执行所有待办请求，返回执行了几条。
    ///
    /// 按文件名排序就是按时间排序（名字以毫秒时间戳开头且定长补零）。
    /// 先删后执行：执行途中崩了也不会在下次启动时重放一遍。
    @MainActor
    @discardableResult
    static func drainPending() -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: pendingDir.path) else { return 0 }
        var done = 0
        for name in names.sorted() where !name.hasPrefix(".") {
            let url = pendingDir.appendingPathComponent(name)
            let payload = (try? String(contentsOf: url, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let age = Date().timeIntervalSince(
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            try? fm.removeItem(at: url)
            guard let payload, age <= pendingTTL else {
                log.debug("dropping stale pending \(payload ?? name, privacy: .public)")
                continue
            }
            log.debug("draining pending \(payload, privacy: .public)")
            apply(payload)
            done += 1
        }
        return done
    }

    /// 执行一条请求。`trigger.<id>` 或 `set.<id>.<1|0>`——和达尔文通知的后缀是同一套写法，
    /// 所以两条路（热路径的广播、冷启动的待办）解析逻辑共用这一份。
    @MainActor
    static func apply(_ payload: String) {
        let parts = payload.split(separator: ".").map(String.init)
        if parts.count >= 2, parts[0] == "trigger" {
            SwitchStore.shared.activate(parts[1])
        } else if parts.count >= 3, parts[0] == "set" {
            SwitchStore.shared.setSwitch(parts[1], on: parts[2] == "1")
        }
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
            log.debug("app asks reloadAllControls")
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
