import SwiftUI

/// 菜单栏弹出的主界面：按分区排列的开关磁贴。
///
/// 带参数的开关（保持亮屏、耳机连接、屏幕分辨率）占两列，选项在面板内就地展开，
/// 不再弹系统菜单——旧版用 `Menu` 承载这类开关，磁贴的布局会被整个丢掉。
struct MenuContentView: View {
    @EnvironmentObject private var store: SwitchStore
    @ObservedObject private var prefs = Preferences.shared

    @State private var expandedID: String?
    @State private var displays: [ResolutionController.Display] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(SwitchCatalog.sections, id: \.self) { section in
                            let items = items(in: section)
                            if !items.isEmpty { sectionView(section, items) }
                        }
                    }
                    .padding(TileMetrics.padding)
                    .glassGroup(spacing: TileMetrics.gap)
                }
                .frame(height: contentHeight)
            }
            Divider()
            footer
        }
        .frame(width: TileMetrics.panelWidth)
        .onAppear {
            store.refresh()
            displays = ResolutionController.displays()
        }
    }

    // MARK: 数据

    private var visibleItems: [SwitchItem] { prefs.visibleItems(from: store.items) }

    /// 分区内按用户在设置里排定的顺序。
    private func items(in section: String) -> [SwitchItem] {
        visibleItems.filter { $0.section == section }
    }

    /// 把磁贴按跨列数装进每行 4 列。
    private func rows(_ items: [SwitchItem]) -> [[SwitchItem]] {
        var out: [[SwitchItem]] = []
        var current: [SwitchItem] = []
        var used = 0
        for item in items {
            if used + item.span > 4 {
                out.append(current); current = []; used = 0
            }
            current.append(item); used += item.span
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private var contentHeight: CGFloat {
        var height: CGFloat = TileMetrics.padding * 2
        for section in SwitchCatalog.sections {
            let items = items(in: section)
            guard !items.isEmpty else { continue }
            height += 18 + 13
            height += CGFloat(rows(items).count) * (TileMetrics.height + TileMetrics.gap)
        }
        if expandedID != nil { height += 78 }
        return min(height, 520)
    }

    // MARK: 视图

    private func sectionView(_ section: String, _ items: [SwitchItem]) -> some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            Text(section)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 3)

            ForEach(Array(rows(items).enumerated()), id: \.offset) { _, row in
                HStack(spacing: TileMetrics.gap) {
                    ForEach(row) { item in tile(item) }
                    Spacer(minLength: 0)
                }
                // 抽屉紧跟在它所属的那一行下面。
                if let id = expandedID, row.contains(where: { $0.id == id }) {
                    drawer(for: id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: SwitchItem) -> some View {
        if item.span > 1 {
            WideTileView(
                item: item,
                isExpanded: expandedID == item.id,
                primary: {
                    // 选择器没有开/关态，主操作就是展开。
                    if item.kind == .picker { toggleExpand(item.id) } else { store.activate(item.id) }
                },
                toggleExpand: { toggleExpand(item.id) }
            )
        } else {
            SwitchTileView(item: item, phase: store.phases[item.id] ?? "idle") {
                store.activate(item.id)
            }
        }
    }

    private func toggleExpand(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            expandedID = (expandedID == id) ? nil : id
        }
    }

    // MARK: 抽屉

    @ViewBuilder
    private func drawer(for id: String) -> some View {
        Group {
            switch id {
            case "keepAwake":         keepAwakeDrawer
            case "connectHeadphones": headphoneDrawer
            case "resolution":        resolutionDrawer
            default:                  EmptyView()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private var keepAwakeDrawer: some View {
        let power = PowerController.shared
        return chipGrid(minimum: 74) {
            TileChip(title: "一直", selected: power.keepAwake && power.totalMinutes == nil, hue: SwitchHue.coffee) {
                setAwake(nil)
            }
            ForEach([30, 60, 120], id: \.self) { minutes in
                TileChip(title: minutes < 60 ? "\(minutes) 分钟" : "\(minutes / 60) 小时",
                         selected: power.totalMinutes == minutes, hue: SwitchHue.coffee) {
                    setAwake(minutes)
                }
            }
            TileChip(title: "合盖不休眠", selected: power.clamshell, hue: SwitchHue.coffee) {
                PowerController.shared.setKeepAwake(true, minutes: power.totalMinutes, clamshell: !power.clamshell)
                store.refresh()
            }
            if power.keepAwake {
                TileChip(title: "关闭", selected: false, hue: SwitchHue.coffee) {
                    PowerController.shared.setKeepAwake(false)
                    store.refresh()
                }
            }
        }
    }

    private var headphoneDrawer: some View {
        let connected = store.items.first { $0.id == "connectHeadphones" }?.isOn ?? false
        return chipGrid(minimum: 88) {
            TileChip(title: connected ? "断开" : "连接", selected: false, hue: SwitchHue.cyan) {
                store.setSwitch("connectHeadphones", on: !connected)
            }
            TileChip(title: "选择设备…", selected: false, hue: SwitchHue.cyan) {
                AudioController.connectHeadphones()
            }
        }
    }

    private var resolutionDrawer: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(displays) { display in
                if displays.count > 1 {
                    Text(display.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                chipGrid(minimum: 96) {
                    ForEach(display.resolutions) { resolution in
                        TileChip(title: resolution.label,
                                 selected: display.currentID == resolution.id,
                                 hue: SwitchHue.blue) {
                            ResolutionController.apply(resolution, to: display.id)
                            displays = ResolutionController.displays()
                        }
                    }
                }
            }
        }
    }

    private func chipGrid<Content: View>(minimum: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 6)],
                  alignment: .leading, spacing: 6) {
            content()
        }
    }

    private func setAwake(_ minutes: Int?) {
        // 改时长时保留当前的「合盖不休眠」，避免重复弹密码。
        PowerController.shared.setKeepAwake(true, minutes: minutes, clamshell: PowerController.shared.clamshell)
        store.refresh()
    }

    // MARK: 头尾

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "switch.2")
                .foregroundStyle(Color.accentColor)
            Text("FreeSwitch").font(.headline)
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("设置")
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("刷新状态")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "switch.2").font(.largeTitle).foregroundStyle(.secondary)
            Text("还没有显示任何开关").font(.callout)
            SettingsLink { Text("去设置里开启") }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var footer: some View {
        HStack {
            Text("免费 · 开源 · 献给大家")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
