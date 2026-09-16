import WidgetKit
import SwiftUI
import AppIntents
import Foundation
import OSLog

// 诊断用：记录控制中心每次回查 provider 的时刻。已降到 debug 级，平时不写日志库。
// 实时查看（注意要用绝对路径，log 常被 shell 里的同名函数截走）：
//   /usr/bin/log stream --predicate 'subsystem == "com.freeswitch.FreeSwitch"' --level debug
let fsLog = Logger(subsystem: "com.freeswitch.FreeSwitch", category: "control")

// 控制中心控件。开关类用 ControlWidgetToggle 显示状态：
//  - 状态从共享 App Group 读取（主 App 负责回写）
//  - 翻动 → SetValueIntent 发 Darwin 通知，主 App 按目标值设置后回写状态并刷新控件
// 动作类用 ControlWidgetButton（点一下执行）。

enum CtrlShared {
    static let suite = "MXHBUQH27V.group.com.freeswitch.FreeSwitch"

    /// 状态文件放在**本扩展自己的沙盒容器**里，不用 App Group 容器。
    /// App Group 需要沙盒真正授予（Team ID 前缀 + 相应描述文件），本地签名下常常拿不到，
    /// 那时 containerURL(...) 返回 nil、状态永远读成 false —— 表现就是控制中心里
    /// 开关能显示却一翻就弹回，像个只读的状态指示器。
    /// 读自己的容器则无需任何 entitlement，而非沙盒的主 App 也能直接往里写。
    /// 沙盒内这个路径实际落在：
    ///   ~/Library/Containers/<本扩展 id>/Data/Library/Application Support/FreeSwitch/states.json
    private static var statesURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeSwitch/states.json")
    }

    static func state(_ id: String) -> Bool {
        guard let url = statesURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else { return false }
        return dict[id] ?? false
    }

    /// 由扩展自己先把目标值落进状态文件（乐观值）。
    ///
    /// 扩展发完通知就返回了，真正执行并回写状态的是主 App——另一个进程。
    /// 控制中心在 intent 返回后会马上回查 currentValue()，那一刻主 App 往往还没处理完，
    /// 读到的仍是旧值，于是控件“先不切换、过一会才跳到对的”。
    /// 先在这里落一个乐观值就能消掉这段空窗；主 App 随后会用真实结果确认或纠正它。
    ///
    /// 这之所以可行，是因为状态文件就在本扩展自己的沙盒容器里，写它不需要任何 entitlement。
    static func setOptimistic(_ id: String, _ value: Bool) {
        guard let url = statesURL else { return }
        var dict = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
        dict[id] = value
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    // MARK: 动作的执行阶段（idle / running / done）
    // 开关状态是 Bool、阶段是字符串，schema 不同，所以分开两个文件。

    private static var phasesURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeSwitch/phases.json")
    }

    static func phase(_ id: String) -> String {
        guard let url = phasesURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return "idle" }
        return dict[id] ?? "idle"
    }

    static func setPhase(_ id: String, _ phase: String) {
        guard let url = phasesURL else { return }
        var dict = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        if phase == "idle" { dict.removeValue(forKey: id) } else { dict[id] = phase }
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
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
        // 正在处理就直接返回。控制中心允许连点，不挡住就会把同一个动作叠着跑。
        guard CtrlShared.phase(id) != "running" else { return .result() }
        // 先把「处理中」落进共享文件：控制中心在 intent 返回后会立刻回查，
        // 这时主 App 往往还没收到通知，不先写就要等约一秒才看得到反馈。
        fsLog.debug("intent trigger \(id, privacy: .public)")
        CtrlShared.setPhase(id, "running")
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
        // 顺序要紧：先落乐观值，再发通知。
        // 反过来的话，主 App 可能抢在我们写文件之前就完成并回写，随后又被这里的旧值覆盖。
        CtrlShared.setOptimistic(id, value)
        CtrlShared.post("set." + id + "." + (value ? "1" : "0"))
        return .result()
    }
}

struct FSToggleProvider: ControlValueProvider {
    let id: String
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool {
        let value = CtrlShared.state(id)
        fsLog.debug("query state \(id, privacy: .public) -> \(value, privacy: .public)")
        return value
    }
}

struct FSPhaseProvider: ControlValueProvider {
    let id: String
    var previewValue: String { "idle" }
    func currentValue() async throws -> String {
        let phase = CtrlShared.phase(id)
        fsLog.debug("query phase \(id, privacy: .public) -> \(phase, privacy: .public)")
        return phase
    }
}

/// 动作控件的三种面孔：常态、处理中、已完成。
private struct FSActionLabel: View {
    let phase: String
    let name: String
    let symbol: String
    var body: some View {
        switch phase {
        case "running": Label("处理中…", systemImage: "hourglass")
        case "done":    Label("已完成", systemImage: "checkmark.circle.fill")
        default:        Label(name, systemImage: symbol)
        }
    }
}

// 动作控件给的是事后反馈而非事前确认：点一下立刻执行，控件随即显示「处理中」，
// 完成后显示「已完成」并变绿，两秒后回到常态。处理中期间的重复点击会被忽略。
private func fsButton(id: String, name: String, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(
        kind: "com.freeswitch.FreeSwitch.control." + id,
        provider: FSPhaseProvider(id: id)
    ) { phase in
        ControlWidgetButton(action: TriggerSwitchIntent(id)) {
            FSActionLabel(phase: phase, name: name, symbol: symbol)
        }
        .tint(phase == "done" ? Color.green : nil)
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
// 锁定键盘特别适合放控制中心：键盘被锁住时，这里是纯鼠标可达的解锁入口。
struct FSLockKeyboard: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "lockKeyboard", name: "锁定键盘", symbol: "keyboard") } }
struct FSShowHidden: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "showHidden", name: "显示隐藏文件", symbol: "eye.fill") } }

struct FSDoNotDisturb: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "doNotDisturb", name: "勿扰", symbol: "moon.zzz.fill") } }
struct FSLockScreen: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "lockScreen", name: "锁定屏幕", symbol: "lock.fill") } }
struct FSScreenClean: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "screenClean", name: "屏幕清洁", symbol: "sparkles") } }
struct FSEmptyTrash: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "emptyTrash", name: "清空废纸篓", symbol: "trash.fill") } }
// 注：这里曾试过用 AppIntents 官方的 requestConfirmation 做二次确认，实测它在
// macOS 控制中心里是静默放行——不渲染界面、不抛错、直接往下走（探针显示 perform()
// 入口与“确认通过”两条通知每次都在同一秒成对出现）。控件 API 也没有弹窗能力。
// 最终改成点一下就执行，用「处理中 / 已完成」做事后反馈，顺带挡住重复触发。
struct FSXcodeClean: ControlWidget { var body: some ControlWidgetConfiguration { fsButton(id: "xcodeClean", name: "Xcode 清理", symbol: "hammer.fill") } }

// WidgetBundle 的 builder 不嵌套时最多只放得下 10 个，第 11 个就编译不过。
// 拆成几组各自用 @WidgetBundleBuilder 标注的属性再拼起来，就能继续往下加
// （每组自己仍受那个 10 个的上限约束）。
@main
struct FreeSwitchControls: WidgetBundle {
    var body: some Widget {
        toggles
        actions
    }

    /// 有开/关状态的，用 ControlWidgetToggle。
    @WidgetBundleBuilder
    private var toggles: some Widget {
        FSDarkMode()
        FSNightShift()
        FSKeepAwake()
        FSLowPower()
        FSMuteMic()
        FSLockKeyboard()
        FSShowHidden()
    }

    /// 点一下执行一次的，用 ControlWidgetButton。
    @WidgetBundleBuilder
    private var actions: some Widget {
        FSDoNotDisturb()
        FSLockScreen()
        FSScreenClean()
        FSEmptyTrash()
        FSXcodeClean()
    }
}
