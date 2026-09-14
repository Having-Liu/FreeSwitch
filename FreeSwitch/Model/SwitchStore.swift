import SwiftUI
import Combine

enum SwitchKind {
    case toggle   // 有开/关状态
    case action   // 点一下执行一次
    case picker   // 分辨率等：弹出子菜单
}

struct SwitchItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let kind: SwitchKind
    var isOn: Bool = false
    var isSupported: Bool = true
    var detail: String? = nil   // 磁贴上的小字（如耳机电量）
}

/// 全部开关的静态目录（顺序即默认顺序）。
enum SwitchCatalog {
    static let all: [SwitchItem] = [
        SwitchItem(id: "darkMode",         title: "黑暗模式",     symbol: "moon.fill",               kind: .toggle),
        SwitchItem(id: "nightShift",       title: "夜览",         symbol: "sunset.fill",             kind: .toggle),
        SwitchItem(id: "trueTone",         title: "原彩显示",     symbol: "circle.righthalf.filled", kind: .toggle),
        SwitchItem(id: "keepAwake",        title: "保持亮屏",     symbol: "cup.and.saucer.fill",     kind: .toggle),
        SwitchItem(id: "lowPowerMode",     title: "低电量模式",   symbol: "leaf.fill",               kind: .toggle),
        SwitchItem(id: "muteMic",          title: "麦克风静音",   symbol: "mic.slash.fill",          kind: .toggle),
        SwitchItem(id: "hideDesktop",      title: "隐藏桌面",     symbol: "rectangle.dashed",        kind: .toggle),
        SwitchItem(id: "showHidden",       title: "显示隐藏文件", symbol: "eye.fill",                kind: .toggle),
        SwitchItem(id: "lockKeyboard",     title: "锁定键盘",     symbol: "keyboard",                kind: .toggle),
        SwitchItem(id: "screenClean",      title: "屏幕清洁",     symbol: "sparkles",                kind: .action),
        SwitchItem(id: "displaySleep",     title: "显示器休眠",   symbol: "display",                 kind: .action),
        SwitchItem(id: "lockScreen",       title: "锁定屏幕",     symbol: "lock.fill",               kind: .action),
        SwitchItem(id: "screensaver",      title: "屏幕保护",     symbol: "photo.on.rectangle",      kind: .action),
        SwitchItem(id: "playMusic",        title: "播放 / 暂停",  symbol: "playpause.fill",          kind: .action),
        SwitchItem(id: "connectHeadphones",title: "耳机连接",     symbol: "airpods.pro",             kind: .toggle),
        SwitchItem(id: "emptyTrash",       title: "清空废纸篓",   symbol: "trash.fill",              kind: .action),
        SwitchItem(id: "emptyClipboard",   title: "清空剪贴板",   symbol: "doc.on.clipboard",        kind: .action),
        SwitchItem(id: "ejectDisk",        title: "推出磁盘",     symbol: "eject.fill",              kind: .action),
        SwitchItem(id: "doNotDisturb",     title: "勿扰 / 专注",  symbol: "moon.zzz.fill",           kind: .action),
        SwitchItem(id: "xcodeClean",       title: "Xcode 清理",   symbol: "hammer.fill",             kind: .action),
        SwitchItem(id: "resolution",       title: "屏幕分辨率",   symbol: "aspectratio",             kind: .picker),
    ]

    static let defaultIDs: [String] = all.map(\.id)

    static func item(_ id: String) -> SwitchItem? { all.first { $0.id == id } }

    /// 处于“开启”时算作激活状态（用于菜单栏图标提示）的开关。
    static let stickyIDs: Set<String> = ["keepAwake", "lockKeyboard", "muteMic", "hideDesktop", "showHidden", "lowPowerMode"]
}

/// 全部开关的状态与行为中心（单例，供菜单面板与全局热键共用）。
@MainActor
final class SwitchStore: ObservableObject {
    static let shared = SwitchStore()

    @Published var items: [SwitchItem] = SwitchCatalog.all
    @Published var flashingID: String?

    private var themeObserver: NSObjectProtocol?

    private init() {
        // 外观在别处被改动时，实时刷新“黑暗模式”状态。
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setOn("darkMode", AppearanceController.isDarkMode()) }
        }
    }

    /// 是否有“常驻类”开关处于激活状态。
    var anyStickyActive: Bool {
        items.contains { SwitchCatalog.stickyIDs.contains($0.id) && $0.isOn }
    }

    private func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }

    private func setOn(_ id: String, _ on: Bool) {
        guard let i = index(id) else { return }
        items[i].isOn = on
    }

    private func setSupported(_ id: String, _ supported: Bool) {
        guard let i = index(id) else { return }
        items[i].isSupported = supported
    }

    private func setDetail(_ id: String, _ detail: String?) {
        guard let i = index(id) else { return }
        items[i].detail = detail
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
        setOn("lowPowerMode", SystemController.lowPowerModeEnabled())
        setOn("muteMic", AudioController.micMuted())
        setOn("hideDesktop", SystemController.desktopIconsHidden())
        setOn("showHidden", SystemController.showHiddenFiles())
        setOn("lockKeyboard", InputBlocker.shared.isKeyboardLocked)

        loadHeadphoneStatus()
    }

    /// 有效目标耳机：优先设置里手动选的，否则自动识别一个已配对音频设备。
    private func effectiveHeadphone() -> BluetoothController.Device? {
        if let address = Preferences.shared.headphoneAddress {
            return .init(id: address, name: BluetoothController.name(for: address) ?? address)
        }
        return BluetoothController.bestAudioDevice()
    }

    /// 刷新耳机连接状态 + 异步读取电量（system_profiler 较慢，放后台）。
    func loadHeadphoneStatus() {
        guard let device = effectiveHeadphone() else {
            setOn("connectHeadphones", false)
            setDetail("connectHeadphones", nil)
            return
        }
        let connected = BluetoothController.isConnected(device.id)
        setOn("connectHeadphones", connected)
        setDetail("connectHeadphones", connected ? "已连接" : nil)
        guard connected else { return }
        let address = device.id
        Task { [weak self] in
            let battery = await Task.detached { BluetoothController.batteryPercent(for: address) }.value
            if let battery { self?.setDetail("connectHeadphones", "\(battery)%") }
        }
    }

    /// 连上耳机后，重试把系统默认输出切到该设备。
    private func switchOutput(to name: String) {
        Task { [weak self] in
            for _ in 0..<10 {
                if AudioController.setDefaultOutput(named: name) { break }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            self?.loadHeadphoneStatus()
        }
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
            performAction(id)
            flash(id)
        case .picker:
            break
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
        case "lowPowerMode": SystemController.setLowPowerMode(on); return SystemController.lowPowerModeEnabled()
        case "muteMic":      AudioController.setMicMuted(on); return AudioController.micMuted()
        case "hideDesktop":  SystemController.setDesktopIconsHidden(on); return on
        case "showHidden":   SystemController.setShowHiddenFiles(on); return on
        case "lockKeyboard": InputBlocker.shared.setKeyboardLocked(on); return InputBlocker.shared.isKeyboardLocked
        case "connectHeadphones":
            guard let device = effectiveHeadphone() else {
                AudioController.connectHeadphones() // 没有已配对音频设备时打开蓝牙设置
                return false
            }
            // 记住自动挑中的设备，之后一直用它。
            if Preferences.shared.headphoneAddress == nil {
                Preferences.shared.headphoneAddress = device.id
            }
            let address = device.id
            let name = device.name
            if on { setDetail("connectHeadphones", "连接中…") }
            // openConnection 会阻塞（设备在盒里时等到超时），放后台执行，避免卡住菜单。
            Task { [weak self] in
                await Task.detached { BluetoothController.setConnected(address, on) }.value
                if on {
                    self?.switchOutput(to: name) // 内部重试并最终刷新状态
                } else {
                    self?.loadHeadphoneStatus()
                }
            }
            return on
        default: return on
        }
    }

    private func performAction(_ id: String) {
        switch id {
        case "screenClean":       InputBlocker.shared.startScreenClean()
        case "displaySleep":      PowerController.shared.sleepDisplayNow()
        case "lockScreen":        PowerController.shared.lockScreen()
        case "screensaver":       PowerController.shared.startScreensaver()
        case "playMusic":         AudioController.playPause()
        case "doNotDisturb":
            if FocusController.isConfigured() { FocusController.toggle() } else { FocusController.openShortcutsApp() }
        case "emptyTrash":        SystemController.emptyTrash()
        case "emptyClipboard":    SystemController.emptyClipboard()
        case "ejectDisk":         SystemController.ejectAllRemovableDisks()
        case "xcodeClean":        SystemController.cleanXcodeCaches()
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
