import WidgetKit
import SwiftUI
import AppIntents
import Foundation

// 控制中心控件：按一下 → 发 Darwin 通知 → 主 App 执行对应开关。
// openAppWhenRun = 主 App 未运行时自动拉起。

struct FreeSwitchTriggerIntent: AppIntent {
    static var title: LocalizedStringResource = "触发 FreeSwitch 开关"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "开关") var id: String

    init() {}
    init(_ id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        let name = "com.freeswitch.FreeSwitch.trigger." + id
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true
        )
        return .result()
    }
}

private func fsControl(id: String, name: String, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.freeswitch.FreeSwitch.control." + id) {
        ControlWidgetButton(action: FreeSwitchTriggerIntent(id)) {
            Label(name, systemImage: symbol)
        }
    }
    .displayName(LocalizedStringResource(stringLiteral: name))
}

struct FSDarkMode: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "darkMode", name: "深色模式", symbol: "moon.fill") } }
struct FSNightShift: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "nightShift", name: "夜览", symbol: "sunset.fill") } }
struct FSKeepAwake: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "keepAwake", name: "保持亮屏", symbol: "cup.and.saucer.fill") } }
struct FSLowPower: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "lowPowerMode", name: "低电量", symbol: "leaf.fill") } }
struct FSMuteMic: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "muteMic", name: "麦克风静音", symbol: "mic.slash.fill") } }
struct FSDoNotDisturb: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "doNotDisturb", name: "勿扰", symbol: "moon.zzz.fill") } }
struct FSLockScreen: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "lockScreen", name: "锁定屏幕", symbol: "lock.fill") } }
struct FSScreenClean: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "screenClean", name: "屏幕清洁", symbol: "sparkles") } }
struct FSEmptyTrash: ControlWidget { var body: some ControlWidgetConfiguration { fsControl(id: "emptyTrash", name: "清空废纸篓", symbol: "trash.fill") } }

@main
struct FreeSwitchControls: ControlWidgetBundle {
    var body: some ControlWidget {
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
