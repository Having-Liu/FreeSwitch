import WidgetKit
import SwiftUI
import AppIntents
import Foundation
import AppKit
import OSLog

// 诊断用：记录控制中心每次回查 provider 的时刻。已降到 debug 级，平时不写日志库。
// 实时查看（注意要用绝对路径，log 常被 shell 里的同名函数截走）：
//   /usr/bin/log stream --predicate 'subsystem == "com.freeswitch.FreeSwitch"' --level debug
let fsLog = Logger(subsystem: "com.freeswitch.FreeSwitch", category: "control")

// 控制中心控件。开关类用 ControlWidgetToggle 显示状态：
//  - 状态从本扩展自己沙盒容器里的 states.json 读取（主 App 负责回写，见 CtrlShared）
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

    // MARK: 把请求送到主 App

    /// 不由本扩展显示执行阶段的动作。
    ///
    /// 「屏幕清洁」点一下就整屏盖住，反馈是它自己，再补一句「已完成」纯属多余——
    /// 而且那块黑幕落下来的时候，控制中心早就收起来了，根本没人看得见。
    static let unphasedActions: Set<String> = ["screenClean"]

    static let mainAppID = "com.freeswitch.FreeSwitch"

    /// 待办目录：主 App 没在跑时，请求先落在这儿。
    ///
    /// 达尔文通知是「广播给此刻正在听的人」，没人听就直接消失。
    /// 先拉起 App 再发也来不及——App 要几百毫秒才开始监听，那一下就白点了。
    /// 所以顺序反过来：**先落盘，再拉起**，App 启动时自己来取。
    ///
    /// 一个请求一个文件，不共用一份列表：写入方是本扩展、消费方是主 App，
    /// 两个进程各写各的文件、各删各的，天然不打架，不用加锁。
    /// 文件名带毫秒时间戳，既定了执行顺序，也用来判断过期。
    private static var pendingDir: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreeSwitch/pending", isDirectory: true)
    }

    /// 把请求送出去：App 在跑就直接广播（快），不在就落盘再把 App 拉起来。
    static func deliver(_ payload: String) async {
        if isMainAppRunning {
            post(payload)
            return
        }
        fsLog.debug("main app not running, queueing \(payload, privacy: .public)")
        enqueue(payload)
        await launchMainApp()
    }

    private static var isMainAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty
    }

    private static func enqueue(_ payload: String) {
        guard let dir = pendingDir, let data = payload.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(format: "%013.0f-%@", Date().timeIntervalSince1970 * 1000, UUID().uuidString.prefix(8) as CVarArg)
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    /// 宿主 App 的位置。
    ///
    /// 从本扩展自己的 bundle 往上找第一个 `.app`，不要写死层数——
    /// 插件在 bundle 里的位置换过（PlugIns / Extensions），写死迟早对不上。
    /// 万一找不到（比如被单独搬走了），再退回 LaunchServices 按 bundle id 查。
    private static var hostAppURL: URL? {
        var url = Bundle.main.bundleURL
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app" { return url }
            if url.path == "/" { break }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainAppID)
    }

    /// 拉起主 App，**不抢焦点**。
    ///
    /// 实测过：带 App Sandbox 的进程调 `NSWorkspace.openApplication` 是允许的——
    /// 真正 spawn 的是 launchd，沙盒管的是本进程能干什么，不是它能请谁干什么。
    /// `activates = false` 是关键：主 App 是 LSUIElement，拉起来只多一个菜单栏图标，
    /// 用户正在用的那个窗口不会被抢走。
    ///
    /// 这里 await 到启动完成再返回，让本扩展进程多活一会儿；
    /// 请求已经落盘了，所以就算这一步失败，App 下次启动照样能收到。
    private static func launchMainApp() async {
        guard let appURL = hostAppURL else {
            fsLog.error("cannot locate host app")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        do {
            let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            fsLog.debug("launched main app pid=\(app.processIdentifier, privacy: .public)")
        } catch {
            fsLog.error("launch failed: \(error.localizedDescription, privacy: .public)")
        }
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
        fsLog.debug("intent trigger \(id, privacy: .public)")
        if !CtrlShared.unphasedActions.contains(id) {
            // 正在处理就直接返回。控制中心允许连点，不挡住就会把同一个动作叠着跑。
            guard CtrlShared.phase(id) != "running" else { return .result() }
            // 先把「处理中」落进共享文件：控制中心在 intent 返回后会立刻回查，
            // 这时主 App 往往还没收到通知，不先写就要等约一秒才看得到反馈。
            CtrlShared.setPhase(id, "running")
        }
        await CtrlShared.deliver("trigger." + id)
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
        await CtrlShared.deliver("set." + id + "." + (value ? "1" : "0"))
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

/// 取一条本地化文案。扩展是独立 bundle，有自己的 Controls/Localizable.xcstrings，
/// 查表走的是扩展自己的 Bundle.main，和主 App 那份互不相干。
/// 键就是中文原文（源语言 zh-Hans）。字面量交给 `Label("中文", …)` 会自动查表，
/// 需要这个函数的是「文案存在变量里」的情况——控件名就是这样从 fsToggle/fsButton 传进来的。
private func L(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }

/// 动作控件的三种面孔：常态、处理中、已完成。
private struct FSActionLabel: View {
    let phase: String
    let name: String
    let symbol: String
    var body: some View {
        switch phase {
        case "running": Label("处理中…", systemImage: "hourglass")
        case "done":    Label("已完成", systemImage: "checkmark.circle.fill")
        default:        Label(L(name), systemImage: symbol)
        }
    }
}

// 动作控件给的是事后反馈而非事前确认：点一下立刻执行，控件随即显示「处理中」，
// 完成后显示「已完成」并变绿，五秒后回到常态（控制中心的刷新有 5 秒节流，窗口再短就画不出来）。
// 处理中期间的重复点击会被忽略。
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
    .displayName(LocalizedStringResource(String.LocalizationValue(name)))
}

/// 不显示执行阶段的动作控件：点一下就执行，控件本身不变。
///
/// 用于「反馈就是动作本身」的那类动作——见 `CtrlShared.unphasedActions`。
/// 这种控件不需要 provider，`StaticControlConfiguration` 有个不带 provider 的重载。
private func fsPlainButton(id: String, name: String, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.freeswitch.FreeSwitch.control." + id) {
        ControlWidgetButton(action: TriggerSwitchIntent(id)) {
            Label(L(name), systemImage: symbol)
        }
    }
    .displayName(LocalizedStringResource(String.LocalizationValue(name)))
}

private func fsToggle(id: String, name: String, symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.freeswitch.FreeSwitch.control." + id, provider: FSToggleProvider(id: id)) { isOn in
        ControlWidgetToggle(isOn: isOn, action: SetSwitchIntent(id)) {
            Label(L(name), systemImage: symbol)
        }
    }
    .displayName(LocalizedStringResource(String.LocalizationValue(name)))
}

// 控件库是一个平铺列表，多一个就挤掉别人一格，所以只放**系统自己没有**的。
// 已经确认属于系统自带、因此不在这里重复的：深色模式、低电量（电池模块）、
// 锁定屏幕、启动屏幕保护程序、将显示器置于睡眠状态
// （后三个同属系统的「锁定屏幕」分类）、播放/暂停（正在播放）、原彩显示与夜览（显示器模块）。
//
// 删控件要趁发布之前：控件一旦被用户放进控制中心，删掉它只会变成一个占位符，
// 而占位符会让 chronod 不断把扩展的沙盒容器重建出来（卸载 13 分钟后容器带着
// 占位快照回来过，见 README 的卸载那节）。
struct FSNightShift: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "nightShift", name: "夜览", symbol: "sunset.fill") } }
struct FSKeepAwake: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "keepAwake", name: "保持亮屏", symbol: "cup.and.heat.waves.fill") } }
struct FSMuteMic: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "muteMic", name: "麦克风静音", symbol: "mic.slash.fill") } }
// 锁定键盘特别适合放控制中心：键盘被锁住时，这里是纯鼠标可达的解锁入口。
struct FSLockKeyboard: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "lockKeyboard", name: "锁定键盘", symbol: "keyboard.fill") } }
struct FSShowHidden: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "showHidden", name: "显示隐藏文件", symbol: "eye.fill") } }
struct FSHideWindows: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "hideWindows", name: "隐藏所有窗口", symbol: "macwindow.on.rectangle") } }
struct FSDockAutohide: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "dockAutohide", name: "自动隐藏程序坞", symbol: "dock.arrow.down.rectangle") } }
struct FSHideDesktop: ControlWidget { var body: some ControlWidgetConfiguration { fsToggle(id: "hideDesktop", name: "隐藏桌面", symbol: "rectangle.on.rectangle.slash") } }

// 屏幕清洁不报阶段：它本来就是「一个动作」，黑幕一落用户就知道成了。
struct FSScreenClean: ControlWidget { var body: some ControlWidgetConfiguration { fsPlainButton(id: "screenClean", name: "屏幕清洁", symbol: "bubbles.and.sparkles.fill") } }
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
        FSNightShift()
        FSKeepAwake()
        FSMuteMic()
        FSLockKeyboard()
        FSShowHidden()
        FSHideWindows()
        FSDockAutohide()
        FSHideDesktop()
    }

    /// 点一下执行一次的，用 ControlWidgetButton。
    @WidgetBundleBuilder
    private var actions: some Widget {
        FSScreenClean()
        FSEmptyTrash()
        FSXcodeClean()
    }
}
