import SwiftUI
import Combine
import ServiceManagement

/// 用户偏好：开关的分组与顺序、显示项、全局快捷键、开机自启。持久化到 UserDefaults。
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let groups = "pref.groups"
        /// 旧版的全局顺序。只在第一次迁移到分组时读一次，迁移完即删除。
        static let legacyOrder = "pref.order"
        static let hidden = "pref.hidden"
        static let hotkeys = "pref.hotkeys"
        static let headphone = "pref.headphone"
    }

    /// 用户的分组：分组顺序、分组名、组内开关及其顺序，全部归用户所有。
    /// 合并、跨组移动、排版这些核心逻辑在 SwitchGroups.swift，那里有独立测试。
    @Published var groups: [SwitchGroup] { didSet { persistGroups() } }
    @Published var hidden: Set<String> { didSet { persistHidden() } }
    @Published var hotkeys: [String: Hotkey] {
        didSet {
            persistHotkeys()
            HotkeyManager.shared.reload(from: hotkeys)
        }
    }
    private init() {
        if let data = defaults.data(forKey: Keys.groups),
           let stored = try? JSONDecoder().decode([SwitchGroup].self, from: data) {
            // 与当前目录对齐：去掉已删除的开关，新增的开关放进它的默认分组。
            groups = GroupLayout.merged(stored,
                                        defaults: SwitchCatalog.defaultGroups,
                                        catalog: SwitchCatalog.groupCatalog)
        } else {
            // 第一次用分组：按默认分组建，组内沿用旧版保存的顺序。
            let legacy = defaults.stringArray(forKey: Keys.legacyOrder) ?? []
            groups = GroupLayout.defaultGroups(defaults: SwitchCatalog.defaultGroups,
                                               catalog: SwitchCatalog.groupCatalog,
                                               legacyOrder: legacy)
        }

        hidden = Set(defaults.stringArray(forKey: Keys.hidden) ?? [])

        if let data = defaults.data(forKey: Keys.hotkeys),
           let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            hotkeys = decoded
        } else {
            hotkeys = [:]
        }


        // init 里给属性赋值不会触发 didSet，迁移或对齐后的分组必须在这里手动存一次。
        // 否则旧顺序马上被删掉，下次启动就只能退回目录顺序——用户排好的顺序会丢。
        persistGroups()
        defaults.removeObject(forKey: Keys.legacyOrder)
    }

    // MARK: 分组

    /// 设置列表用：分组标题和开关摊平成一个可拖动列表。
    var groupRows: [GroupRow] { GroupLayout.rows(for: groups) }

    func moveRows(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups = GroupLayout.applyingMove(to: groups, from: source, to: destination)
    }

    func moveGroup(_ id: String, by offset: Int) {
        groups = GroupLayout.movingGroup(groups, id: id, by: offset)
    }

    func renameGroup(_ id: String, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    /// 分组的显示名。**空字符串是有意义的取值**：表示这一组不显示标题，只当分隔。
    ///
    /// 所以不能像以前那样「名字空了就退回默认名」——那样用户就没办法要一条纯粹的空白分隔。
    /// 把默认分组的名字删干净，和新建一个不起名的分组，效果一样。
    ///
    /// 默认名要本地化，用户自己起的名字原样保留。判断依据是「和默认名一模一样」——
    /// 分组是建组时把默认名**存下来**的，存的是中文原文，
    /// 所以非中文用户看到的译文来自这一步，而不是空值回退。
    func displayName(of group: SwitchGroup) -> String {
        let trimmed = group.name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        let fallback = SwitchCatalog.defaultGroups.first { $0.id == group.id }?.name
        if trimmed == fallback {
            return fallback.map { String(localized: String.LocalizationValue($0)) } ?? trimmed
        }
        return trimmed
    }

    func resetGroups() {
        groups = GroupLayout.defaultGroups(defaults: SwitchCatalog.defaultGroups,
                                           catalog: SwitchCatalog.groupCatalog)
    }

    // MARK: 显示项

    func isVisible(_ id: String) -> Bool { !hidden.contains(id) }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible { hidden.remove(id) } else { hidden.insert(id) }
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
    private func persistGroups() {
        if let data = try? JSONEncoder().encode(groups) { defaults.set(data, forKey: Keys.groups) }
    }
    private func persistHidden() { defaults.set(Array(hidden), forKey: Keys.hidden) }
    private func persistHotkeys() {
        if let data = try? JSONEncoder().encode(hotkeys) { defaults.set(data, forKey: Keys.hotkeys) }
    }
}
