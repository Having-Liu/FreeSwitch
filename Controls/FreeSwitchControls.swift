import WidgetKit
import SwiftUI
import AppIntents
import Foundation

// 控制中心控件。开关类用 ControlWidgetToggle 显示状态：
//  - 状态从共享 App Group 读取（主 App 负责回写）
//  - 翻动 → SetValueIntent 发 Darwin 通知，主 App 按目标值设置后回写状态并刷新控件
// 动作类用 ControlWidgetButton（点一下执行）。

enum CtrlShared {
    static let suite = "MXHBUQH27V.group.com.freeswitch.FreeSwitch"

    static func state(_ id: String) -> Bool {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: suite)?
                .appendingPathComponent("states.json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else { return false }
        return dict[id] ?? false
    }

    static func post(_ suffix: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName((CtrlShared.suite + "." + suffix) as CFString),
            nil, nil, true
        )
    }
}

struct TriggerSwitchIntent: AppIntent {
    static var title: LocalizedStringResource = "触发 FreeSwitch 开关"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "开关") var id: String
    init() {}
    init(_ id: String) { self.id = id }
    func perform() async throws -> some IntentResult {
        CtrlShared.post("trigger." + id)
        return .result()
    }
}

struct SetSwitchIntent: SetValueIntent {
    static var title: LocalizedStringResource = "设置 FreeSwitch 开关"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "开关") var id: String
    @Parameter(title: "开启") var value: Bool
    init() {}
    init(_ id: String) { self.id = id }
    func perform() async throws -> some IntentResult {
        CtrlShared.post("set." + id + "." + (value ? "1" : "0"))
        return .result()
    }
}

struct FSToggleProvider: ControlValueProvider {
    let id: String
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { CtrlShared.state(id) }
}

private func fsButton(id: String, name: String, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.freeswitch.FreeSwitch.control." + id) {
        ControlWidgetButton(action: TriggerSwitchIntent(id)) {
            Label(name, systemImage: symbol)
        }
    }
    .displayName(LocalizedStringResource(stringLiteral: name))
}

private func fsToggle(id: String, name: String, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.freeswitch.FreeSwitch.control." + id, provider: FSToggleProvider(id: id)) { isOn in
        ControlWidgetToggle(isOn: isOn, action: SetSwitchIntent(id)) {
            Label(name, systemImage: symbol)
        }
    }
    .displayName(LocalizedStringResource(stringLiteral: name))
}

struct FSDarkMode: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "darkMode", name: "深色模式", symbol: "moon.fill") } }
struct FSNightShift: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "nightShift", name: "夜览", symbol: "sunset.fill") } }
struct FSKeepAwake: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "keepAwake", name: "保持亮屏", symbol: "cup.and.saucer.fill") } }
struct FSLowPower: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "lowPowerMode", name: "低电量", symbol: "leaf.fill") } }
struct FSMuteMic: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "muteMic", name: "麦克风静音", symbol: "mic.slash.fill") } }

struct FSDoNotDisturb: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "doNotDisturb", name: "勿扰", symbol: "moon.zzz.fill") } }
struct FSLockScreen: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "lockScreen", name: "锁定屏幕", symbol: "lock.fill") } }
struct FSScreenClean: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "screenClean", name: "屏幕清洁", symbol: "sparkles") } }
struct FSEmptyTrash: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "emptyTrash", name: "清空废纸篓", symbol: "trash.fill") } }

@main
struct FreeSwitchControls: WidgetBundle {
    var body: some Widget {
        FSDarkMode()
        FSNightShift()
        FSKeepAwake()
        FSLowPower()
        FSMuteMic()
        FSDoNotDisturb()
        FSLockScreen()
        FSScreenClean()
        FSEmptyTrash()
    }
}
