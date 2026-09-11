import SwiftUI
import Combine
import ServiceManagement

/// 用户偏好：开关的显示/顺序、全局快捷键、开机自启。持久化到 UserDefaults。
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let order = "pref.order"
        static let hidden = "pref.hidden"
        static let hotkeys = "pref.hotkeys"
        static let headphone = "pref.headphone"
    }

    @Published var order: [String] { didSet { persistOrder() } }
    @Published var hidden: Set<String> { didSet { persistHidden() } }
    @Published var hotkeys: [String: Hotkey] {
        didSet {
            persistHotkeys()
            HotkeyManager.shared.reload(from: hotkeys)
        }
    }
    @Published var headphoneAddress: String? {
        didSet { defaults.set(headphoneAddress, forKey: Keys.headphone) }
    }

    private init() {
        // 顺序：以存储为准，并补上目录里新增、去掉已删除的开关。
        let stored = defaults.stringArray(forKey: Keys.order) ?? []
        let valid = stored.filter { SwitchCatalog.defaultIDs.contains($0) }
        let missing = SwitchCatalog.defaultIDs.filter { !valid.contains($0) }
        order = valid + missing

        hidden = Set(defaults.stringArray(forKey: Keys.hidden) ?? [])

        if let data = defaults.data(forKey: Keys.hotkeys),
           let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            hotkeys = decoded
        } else {
            hotkeys = [:]
        }

        headphoneAddress = defaults.string(forKey: Keys.headphone)
    }

    // MARK: 显示的开关（按顺序、去掉隐藏的）
    func visibleItems(from items: [SwitchItem]) -> [SwitchItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return order.compactMap { id in hidden.contains(id) ? nil : byID[id] }
    }

    func isVisible(_ id: String) -> Bool { !hidden.contains(id) }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible { hidden.remove(id) } else { hidden.insert(id) }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    // MARK: 快捷键
    func setHotkey(_ hotkey: Hotkey?, for id: String) {
        if let hotkey { hotkeys[id] = hotkey } else { hotkeys.removeValue(forKey: id) }
    }

    // MARK: 开机自启（SMAppService）
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                }
            } catch {
                NSLog("[FreeSwitch] launchAtLogin error: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    // MARK: 持久化
    private func persistOrder()  { defaults.set(order, forKey: Keys.order) }
    private func persistHidden() { defaults.set(Array(hidden), forKey: Keys.hidden) }
    private func persistHotkeys() {
        if let data = try? JSONEncoder().encode(hotkeys) { defaults.set(data, forKey: Keys.hotkeys) }
    }
}
