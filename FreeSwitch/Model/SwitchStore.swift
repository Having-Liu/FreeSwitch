import SwiftUI
import Combine
import OSLog

enum SwitchKind {
    case toggle   // 有开/关状态
    case action   // 点一下执行一次
    case picker   // 分辨率等：弹出子菜单
}

struct SwitchItem: Identifiable {
    let id: String
    let title: String
    /// SF Symbols 的符号名。挑选原则：优先用 macOS 在同一功能上自己用的图形
    /// （外观是半圆、专注是月亮、低电量是黄电池），让人一眼认出来而不是去猜；
    /// 并保证彼此之间两两不撞——曾经「黑暗模式」和已经删掉的「勿扰」是两个月亮。
    /// 每个名字都在本机 CoreGlyphs 的 name_availability.plist 里核对过确实存在。
    let symbol: String
    let kind: SwitchKind
    /// 默认分组的 id。只决定第一次使用和「恢复默认分组」时开关落在哪，
    /// 之后用户可以把它拖到任何分组（分组数据在 Preferences.groups）。
    let defaultGroup: String
    let hue: Color
    /// 占几列。带参数的开关占两列，腾出的宽度用来显示它的当前值和量规——
    /// 强行让 21 个东西一样大，正是这些开关此前无处安放的原因。
    let span: Int
    /// 叠在右下角的小角标。SF Symbols 里没有单个符号能表达时才用
    /// （没有「键盘+锁」「显示器+睡眠」），叠加后仍全是系统符号，不自己画。
    var badge: String? = nil
    /// 为真时只给符号的主图层着色、其余保持正文色（麦克风静音：斜线染红，话筒不染）。
    var accentsPrimaryLayer: Bool = false
    var isOn: Bool = false
    var isSupported: Bool = true
    var detail: String? = nil   // 宽磁贴上的当前值（剩余时长、电量、分辨率）
    var gauge: Double? = nil    // 0…1，底边量规；只有真有量可报的开关才给

    /// 界面上显示的标题。
    ///
    /// `title` 存的是中文原文，它同时也是字符串目录（Localizable.xcstrings）里的键——
    /// 源语言就是简体中文，所以中文那份不需要再写一遍译文。
    /// 注意 `Text("中文字面量")` 会自动走本地化（参数是 LocalizedStringKey），
    /// 但 `Text(someString)` 不会，所以凡是把 title 交给界面的地方都得用这个。
    var localizedTitle: String { String(localized: String.LocalizationValue(title)) }
}

/// 全部开关的静态目录。按分区成组——21 个一字排开时谁也扫不出信息。
enum SwitchCatalog {
    /// 默认分组：id 稳定（存储和归属都靠它，改名不影响），名字是默认名，用户可以改。
    /// 默认分组。按**使用场景**分，不按「属于系统哪个模块」分——
    /// 用户打开面板想的是「我要离开电脑了」「我要把屏幕弄干净」，
    /// 不是「这算显示设置还是文件设置」。
    ///
    /// 各组的**格子数**（宽磁贴算 2 格）也是排过的：面板一行 5 列，
    /// 每组独立换行，所以组的格子数最好是 5 的倍数，否则行尾就留洞。
    /// 现在是 5 / 5 / 5 / 5 / 4 = 5 行 1 个空位，正好是 24 格在 5 列下的理论下限。
    /// 改动归属之前先按这个算一遍，别把某一组变成「一整行只填两格」。
    ///
    /// 最后那组老实叫「其他」：它本来就是零散但常用的那一格抽屉，
    /// 硬编一个「声音与锁定」之类的假类别反而更难找东西。
    static let defaultGroups: [(id: String, name: String)] = [
        ("display",   "屏幕"),
        ("power",     "电源"),
        ("declutter", "清屏"),
        ("files",     "文件与清理"),
        ("other",     "其他"),
    ]

    /// 给分组逻辑（SwitchGroups.swift）用的精简视图：每个开关和它的默认分组。
    static var groupCatalog: [(id: String, group: String)] { all.map { ($0.id, $0.defaultGroup) } }

    static let all: [SwitchItem] = [
        // 外观与显示
        SwitchItem(id: "darkMode",   title: "黑暗模式",   symbol: "circle.lefthalf.filled", kind: .toggle, defaultGroup: "display", hue: SwitchHue.indigo, span: 1),
        SwitchItem(id: "nightShift", title: "夜览",       symbol: "sunset.fill",            kind: .toggle, defaultGroup: "display", hue: SwitchHue.amber,  span: 1),
        // 原彩讲的是颜色准确，调色盘直接指向「颜色」，而且是实心的。
        // 弃用过的：lightspectrum.horizontal 缩小后像条形码；camera.filters 是细线圆，
        // 放在浅色玻璃上发虚看不清；sun.max.fill 读作「亮度」，还会和旁边夜览的太阳撞。
        SwitchItem(id: "trueTone",   title: "原彩显示",   symbol: "paintpalette.fill",      kind: .toggle, defaultGroup: "display", hue: SwitchHue.teal,   span: 1),
        // aspectratio 像裁切比例；屏幕加外扩箭头才是「尺寸」。
        SwitchItem(id: "resolution", title: "屏幕分辨率", symbol: "arrow.up.left.and.arrow.down.right.rectangle", kind: .picker, defaultGroup: "display", hue: SwitchHue.blue, span: 2),

        // 电源
        // kind 仍是 .toggle：它有真实的开/关态，控制中心的开关控件、全局热键、
        // 以及写进共享状态文件的那一份都依赖这个语义。“占两列、可展开”是表现，由 span 决定。
        SwitchItem(id: "keepAwake",    title: "保持亮屏",   symbol: "cup.and.heat.waves.fill", kind: .toggle, defaultGroup: "power", hue: SwitchHue.coffee,  span: 2),
        // 叶子是 iOS 的节能暗示；Mac 上低电量就是菜单栏那个黄电池。
        SwitchItem(id: "lowPowerMode", title: "低电量模式", symbol: "battery.25percent",       kind: .toggle, defaultGroup: "power", hue: SwitchHue.yellow,  span: 1),
        // powersleep 名字看着对，画出来却是一轮月亮，会和「专注」撞；改用显示器叠 zzz 角标。
        SwitchItem(id: "displaySleep", title: "显示器休眠", symbol: "display",                 kind: .action, defaultGroup: "power", hue: SwitchHue.indigo,  span: 1, badge: "zzz"),
        SwitchItem(id: "lockScreen",   title: "锁定屏幕",   symbol: "lock.display",            kind: .action, defaultGroup: "other", hue: SwitchHue.neutral, span: 1),

        // 声音与输入
        SwitchItem(id: "muteMic",           title: "麦克风静音",  symbol: "mic.slash.fill", kind: .toggle, defaultGroup: "other", hue: SwitchHue.red,     span: 1, accentsPrimaryLayer: true),
        SwitchItem(id: "playMusic",         title: "播放 / 暂停", symbol: "playpause.fill", kind: .action, defaultGroup: "other", hue: SwitchHue.neutral, span: 1),

        // 桌面与文件
        // 虚线框太抽象；带菜单栏和程序坞的屏幕才是「桌面」。
        SwitchItem(id: "hideDesktop",    title: "隐藏桌面",     symbol: "menubar.dock.rectangle", kind: .toggle, defaultGroup: "declutter", hue: SwitchHue.blue,    span: 1),
        SwitchItem(id: "showHidden",     title: "显示隐藏文件", symbol: "eye.fill",               kind: .toggle, defaultGroup: "files", hue: SwitchHue.violet,  span: 1),
        // dock.arrow.down.rectangle 是「程序坞往下收起」，和「隐藏桌面」那个带菜单栏的屏幕分得开。
        SwitchItem(id: "dockAutohide", title: "自动隐藏程序坞", symbol: "dock.arrow.down.rectangle", kind: .toggle, defaultGroup: "declutter", hue: SwitchHue.cyan,   span: 1),
        SwitchItem(id: "hideWindows",  title: "隐藏所有窗口",   symbol: "rectangle.on.rectangle.slash", kind: .toggle, defaultGroup: "declutter", hue: SwitchHue.indigo, span: 1),
        SwitchItem(id: "hideWidgets",  title: "隐藏小组件",     symbol: "widget.small",                 kind: .toggle, defaultGroup: "declutter", hue: SwitchHue.amber,  span: 1),
        // doc.on.clipboard 是系统的「粘贴/复制」图标，会被读成复制；换成剪贴板本身。
        SwitchItem(id: "emptyClipboard", title: "清空剪贴板",   symbol: "clipboard.fill",         kind: .action, defaultGroup: "files", hue: SwitchHue.neutral, span: 1),
        SwitchItem(id: "emptyTrash",     title: "清空废纸篓",   symbol: "trash.fill",             kind: .action, defaultGroup: "files", hue: SwitchHue.neutral, span: 1),
        SwitchItem(id: "ejectDisk",      title: "推出磁盘",     symbol: "eject.fill",             kind: .action, defaultGroup: "files", hue: SwitchHue.neutral, span: 1),

        // 清洁与输入
        // 屏幕里带闪光才是「擦屏幕」：屏幕把意思钉在了「屏幕」上。单独的 sparkles 如今常被读成 AI，
        // 之前的 bubbles.and.sparkles 又只说了「清洁」，没说清洁什么。
        // sparkles.tv.fill 从 macOS 12 就有（查 CoreGlyphs.bundle 里的 name_availability.plist），
        // 早于本 App 的最低版本 14.6，所以不需要按系统版本分支。
        // 它的闪光是从屏幕里**镂空**出来的，靠的是单色渲染；实测改成只给一种颜色的 palette，
        // 闪光会被涂成和屏幕同色，整个糊成一台空电视。
        SwitchItem(id: "screenClean",  title: "屏幕清洁",    symbol: "sparkles.tv.fill",          kind: .action, defaultGroup: "declutter", hue: SwitchHue.cyan,    span: 1),
        // SF 里没有「键盘+锁」，叠一个锁角标。
        SwitchItem(id: "lockKeyboard", title: "锁定键盘",    symbol: "keyboard.fill",             kind: .toggle, defaultGroup: "other", hue: SwitchHue.neutral, span: 1, badge: "lock.fill"),
        // play.display 的三角会和「播放 / 暂停」撞；photo.tv 是屏幕里有画面。
        SwitchItem(id: "screensaver",  title: "屏幕保护",    symbol: "photo.tv",                  kind: .action, defaultGroup: "power", hue: SwitchHue.teal,    span: 1),
        // Xcode 自己的图标就是锤子。
        SwitchItem(id: "xcodeClean",   title: "Xcode 清理",  symbol: "hammer.fill",               kind: .action, defaultGroup: "files", hue: SwitchHue.blue,    span: 1),
    ]

    static let defaultIDs: [String] = all.map(\.id)

    static func item(_ id: String) -> SwitchItem? { all.first { $0.id == id } }

    /// 处于“开启”时算作激活状态（用于菜单栏图标提示）的开关。
    static let stickyIDs: Set<String> = ["keepAwake", "lockKeyboard", "muteMic", "hideDesktop",
                                         "showHidden", "lowPowerMode", "hideWindows"]
}

/// 全部开关的状态与行为中心（单例，供菜单面板与全局热键共用）。
@MainActor
final class SwitchStore: ObservableObject {
    static let shared = SwitchStore()

    @Published var items: [SwitchItem] = SwitchCatalog.all
    @Published var flashingID: String?

    private var themeObserver: NSObjectProtocol?
    private var powerObserver: NSObjectProtocol?
    private var reconcileTimer: Timer?
    private var lastPublished: [String: Bool] = [:]

    private init() {
        // 外观在别处被改动时，实时刷新“黑暗模式”状态。
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setOn("darkMode", AppearanceController.isDarkMode())
                self?.publish()
            }
        }

        // 低电量模式不只有我们会改：电量低于 20% 时系统会自动打开，
        // 用户也可能在系统设置或控制中心的电池区里改。这是官方通知，及时且免费。
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // 通知到了就说明写入已落地，从这一刻起系统读数才可信。
                self?.endPendingWrite("lowPowerMode")
                self?.setOn("lowPowerMode", SystemController.lowPowerModeEnabled())
                self?.publish()
            }
        }

        // 麦克风被会议 App / 硬件键静音，或默认输入设备被换掉。
        AudioController.observeMicChanges { [weak self] in
            self?.setOn("muteMic", AudioController.micMuted())
            self?.publish()
        }


        // 兜底：夜览、原彩这些在系统设置里也能改，却没有好用的通知。
        // 定期只做“进程内、不 fork 子进程”的廉价读取核对一遍。
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    /// 廉价核对：只读进程内就能拿到的状态，绝不 fork 子进程
    /// （`pmset -g`、`system_profiler` 这类太贵，不能每 5 秒跑一次）。
    private func reconcile() {
        setFromSystem("darkMode", AppearanceController.isDarkMode())
        if AppearanceController.nightShiftSupported { setFromSystem("nightShift", AppearanceController.isNightShiftOn()) }
        if AppearanceController.trueToneSupported { setFromSystem("trueTone", AppearanceController.isTrueToneOn()) }
        setFromSystem("lowPowerMode", SystemController.lowPowerModeEnabled())
        setFromSystem("muteMic", AudioController.micMuted())
        // 这两个在访达里也能改（Cmd+Shift+. 切隐藏文件），所以要核对。
        // 现在它们走 CFPreferences 读，进程内、不 fork，够便宜。
        setFromSystem("showHidden", SystemController.showHiddenFiles())
        setFromSystem("hideDesktop", SystemController.desktopIconsHidden())
        setFromSystem("dockAutohide", SystemController.dockAutohide())
        setFromSystem("hideWidgets", SystemController.desktopWidgetsHidden())
        setOn("hideWindows", WindowController.shared.isHiding)
        setOn("keepAwake", PowerController.shared.keepAwake)
        setOn("lockKeyboard", InputBlocker.shared.isKeyboardLocked)
        publish()
    }

    /// 把状态发布给控制中心控件。默认只在真的发生变化时才写文件、刷控件，
    /// 免得定时核对每 5 秒都触发一次无谓的 IO 与控件重载。
    // MARK: 动作的执行阶段（控制中心里显示「处理中 / 已完成」）
    // 控件没有弹窗能力，但换得了图标和文字。比起事前确认，事后反馈更有用：
    // 能看见它真的在做、做完了；而「处理中」本身就挡住了重复触发。
    /// 面板和控制中心读同一份执行阶段，两处显示才一致。
    @Published private(set) var phases: [String: String] = [:]
    private var lastPhases: [String: String] = [:]
    private var idleTasks: [String: Task<Void, Never>] = [:]

    private func setPhase(_ id: String, _ phase: String) {
        let wanted: String? = phase == "idle" ? nil : phase
        guard phases[id] != wanted else { return }
        if let wanted { phases[id] = wanted } else { phases.removeValue(forKey: id) }
        FreeSwitchTrigger.log.debug("app writes \(id, privacy: .public) = \(phase, privacy: .public)")
        publish(force: true)
    }

    /// 执行一个动作：先把「处理中」发出去，做完显示「已完成」，两秒后回到常态。
    /// 会把调用线程卡住的动作，一律丢到后台。
    ///
    /// 三个各有各的卡法：清 DerivedData 要删好几个 G；推出磁盘要等缓冲刷干净、
    /// 等占用文件的进程让开；清空废纸篓则是访达弹了确认框，脚本一直等到用户回答。
    /// 留在主线程上的后果是光标转彩虹——「推出磁盘转了几秒」就是这么来的——
    /// 而且「处理中」那一帧根本没机会被画出来。
    private static let blockingActions: Set<String> = ["xcodeClean", "ejectDisk", "emptyTrash"]

    private func beginAction(_ id: String) {
        setPhase(id, "running")
        flash(id)
        if Self.blockingActions.contains(id) {
            Task { [weak self] in
                await Task.detached { Self.performBlockingAction(id) }.value
                self?.finishAction(id)
            }
        } else {
            performAction(id)
            finishAction(id)
        }
    }

    /// `blockingActions` 里那几个的实现。都不碰界面，所以放后台是安全的。
    private nonisolated static func performBlockingAction(_ id: String) {
        switch id {
        case "xcodeClean": _ = SystemController.cleanXcodeCaches()
        case "ejectDisk":  SystemController.ejectAllRemovableDisks()
        case "emptyTrash": SystemController.emptyTrash()
        default:           break
        }
    }

    /// 「已完成」要停留够久。
    ///
    /// 控制中心只在 intent 返回后必定回查一次，之后就靠 reloadAllControls()——而那是
    /// 被系统节流的，不是立即重绘。慢动作（比如清 DerivedData）的时序是：回查时看到
    /// running，显示「处理中」；等真正完成写下 done 时，早已过了那次回查，只能等刷新。
    /// 停留窗口若短于刷新延迟，刷新落地时阶段已经回落，「已完成」就永远看不见。
    /// 所以这里给足 5 秒——快动作那边不受影响，它在回查时就已经是 done 了。
    private static let doneDisplaySeconds: UInt64 = 5

    private func finishAction(_ id: String) {
        setPhase(id, "done")
        idleTasks[id]?.cancel()
        idleTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.doneDisplaySeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.setPhase(id, "idle")
        }
    }

    private func publish(force: Bool = false) {
        var dict: [String: Bool] = [:]
        for item in items where item.kind == .toggle { dict[item.id] = item.isOn }
        guard force || dict != lastPublished || phases != lastPhases else { return }
        lastPublished = dict
        lastPhases = phases
        FreeSwitchTrigger.publishStates(dict, phases: phases)
    }

    /// 是否有“常驻类”开关处于激活状态。
    var anyStickyActive: Bool {
        items.contains { SwitchCatalog.stickyIDs.contains($0.id) && $0.isOn }
    }

    private func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }

    // 下面这几个写入前都要先比一次「值变了没有」。
    //
    // items 是 @Published，每赋值一次就发一次 objectWillChange，而 SwiftUI 会把所有观察
    // 这个 store 的视图整棵作废重建——包括**关着的**那个面板：MenuBarExtra(.window) 的
    // 内容视图一直活着，不是关了就不算。reconcile() 每 5 秒调十来个 setter，
    // 于是每 5 秒就有十几次全量重建，24 个磁贴连玻璃材质一起重算。
    //
    // 实测：不加这个判断时 App 空转常驻约 0.7% CPU，采样里能看到 MenuContentView.grid、
    // sectionView、SwitchTileView 在面板关着的情况下反复求值。
    private func setOn(_ id: String, _ on: Bool) {
        guard let i = index(id), items[i].isOn != on else { return }
        items[i].isOn = on
    }

    // MARK: 写入在途
    // 有些开关（低电量、合盖不休眠）要改系统电源设置，写入是异步的：
    // 我们已经按目标值显示了，但系统里还没落地，这时任何“读当前值”都还是旧值。
    // 把旧值当真相发布出去，控件就会闪一下（新值 → 旧值 → 通知到达 → 又回到新值）。
    // 所以写入在途期间，一律忽略从系统读到的值，只信最终那个变更通知。

    private var pendingWrites: [String: Date] = [:]

    private func beginPendingWrite(_ id: String) { pendingWrites[id] = Date() }

    private func endPendingWrite(_ id: String) { pendingWrites.removeValue(forKey: id) }

    private func isPending(_ id: String) -> Bool {
        guard let started = pendingWrites[id] else { return false }
        // 兜底：变更通知可能永远不来（比如用户在授权弹窗上点了取消）。
        // 超时后就放开，让定时核对把状态纠正回系统的真实值。
        guard Date().timeIntervalSince(started) < 5 else {
            pendingWrites.removeValue(forKey: id)
            return false
        }
        return true
    }

    /// 用“从系统读到的值”更新状态。该开关正有写入在途时，读数必然是旧的，忽略。
    private func setFromSystem(_ id: String, _ value: Bool) {
        guard !isPending(id) else { return }
        setOn(id, value)
    }

    private func setSupported(_ id: String, _ supported: Bool) {
        guard let i = index(id), items[i].isSupported != supported else { return }
        items[i].isSupported = supported
    }

    private func setDetail(_ id: String, _ detail: String?) {
        guard let i = index(id), items[i].detail != detail else { return }
        items[i].detail = detail
    }

    private func setGauge(_ id: String, _ value: Double?) {
        guard let i = index(id), items[i].gauge != value else { return }
        items[i].gauge = value
    }

    /// 从系统读取当前真实状态。
    func refresh() {
        setOn("darkMode", AppearanceController.isDarkMode())

        setSupported("nightShift", AppearanceController.nightShiftSupported)
        setOn("nightShift", AppearanceController.isNightShiftOn())

        let trueToneOK = AppearanceController.trueToneSupported
        setSupported("trueTone", trueToneOK)
        setOn("trueTone", trueToneOK && AppearanceController.isTrueToneOn())

        setOn("keepAwake", PowerController.shared.keepAwake)
        if PowerController.shared.keepAwake {
            var text = PowerController.shared.remainingMinutes.map { L("剩 %lld 分", $0) } ?? L("一直亮屏")
            if PowerController.shared.clamshell { text += L(" · 合盖") }
            setDetail("keepAwake", text)
            setGauge("keepAwake", PowerController.shared.progress)
        } else {
            setDetail("keepAwake", L("已关闭"))
            setGauge("keepAwake", nil)
        }
        setFromSystem("lowPowerMode", SystemController.lowPowerModeEnabled())
        setFromSystem("muteMic", AudioController.micMuted())
        setFromSystem("hideDesktop", SystemController.desktopIconsHidden())
        setFromSystem("showHidden", SystemController.showHiddenFiles())
        setFromSystem("dockAutohide", SystemController.dockAutohide())
        setFromSystem("hideWidgets", SystemController.desktopWidgetsHidden())
        setOn("hideWindows", WindowController.shared.isHiding)
        setOn("lockKeyboard", InputBlocker.shared.isKeyboardLocked)

        publish(force: true)
    }

    /// 处理一次点击 / 热键触发。
    func activate(_ id: String) {
        guard let item = SwitchCatalog.item(id) else { return }
        switch item.kind {
        case .toggle:
            let current = items[index(id) ?? 0].isOn
            let newValue = !current
            // 用回读到的真实状态更新，避免授权失败/设备不支持时磁贴“说谎”。
            setOn(id, perform(id, on: newValue))
        case .action:
            // 正在处理就忽略这次触发，别把同一个动作叠着跑。
            guard phases[id] != "running" else { return }
            beginAction(id)
        case .picker:
            break
        }
        publish(force: true)
    }

    /// 设为指定状态（供控制中心开关控件用；非开关类则执行动作）。
    func setSwitch(_ id: String, on: Bool) {
        guard let item = SwitchCatalog.item(id) else { return }
        if item.kind == .toggle {
            setOn(id, perform(id, on: on))
            publish(force: true)
        } else {
            activate(id)
        }
    }

    /// 执行开关并返回“真实的结果状态”（尽量回读硬件/系统，回读不可靠的返回目标值）。
    @discardableResult
    private func perform(_ id: String, on: Bool) -> Bool {
        switch id {
        case "darkMode":     AppearanceController.setDarkMode(on); return on
        case "nightShift":   AppearanceController.setNightShift(on); return on
        case "trueTone":     AppearanceController.setTrueTone(on); return AppearanceController.isTrueToneOn()
        case "keepAwake":    PowerController.shared.setKeepAwake(on); return PowerController.shared.keepAwake
        // 改电源设置是异步的（走 XPC 助手或管理员授权弹窗），此刻回读必然是旧值。
        // 标记为写入在途：这期间的系统读数一律忽略，等 NSProcessInfoPowerStateDidChange
        // 通知到了才认。否则助手的 XPC 回调或定时核对会抢先发布旧值，控件就闪一下。
        case "lowPowerMode":
            beginPendingWrite(id)
            SystemController.setLowPowerMode(on)
            return on
        case "muteMic":      AudioController.setMicMuted(on); return AudioController.micMuted()
        case "hideDesktop":  SystemController.setDesktopIconsHidden(on); return on
        // 走 Apple 事件，写完不一定立刻反映到偏好里；标记写入在途，由 5 秒核对纠正。
        case "dockAutohide":
            beginPendingWrite(id)
            SystemController.setDockAutohide(on)
            return on
        case "hideWindows":  WindowController.shared.setHidden(on); return WindowController.shared.isHiding
        case "hideWidgets":  SystemController.setDesktopWidgetsHidden(on); return SystemController.desktopWidgetsHidden()
        case "showHidden":   SystemController.setShowHiddenFiles(on); return on
        case "lockKeyboard": InputBlocker.shared.setKeyboardLocked(on); return InputBlocker.shared.isKeyboardLocked
        default: return on
        }
    }

    /// 一次性动作：点一下就执行，没有开/关状态。
    private func performAction(_ id: String) {
        switch id {
        case "screenClean":       InputBlocker.shared.startScreenClean()
        case "displaySleep":      PowerController.shared.sleepDisplayNow()
        case "lockScreen":        PowerController.shared.lockScreen()
        case "screensaver":       PowerController.shared.startScreensaver()
        case "playMusic":         AudioController.playPause()
        case "emptyClipboard":    SystemController.emptyClipboard()
        // emptyTrash / ejectDisk / xcodeClean 不在这儿——它们会阻塞，
        // 由 beginAction 走 performBlockingAction 丢到后台。
        default: break
        }
    }

    private func flash(_ id: String) {
        flashingID = id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if self?.flashingID == id { self?.flashingID = nil }
        }
    }
}
