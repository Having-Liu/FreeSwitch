import SwiftUI

/// 菜单栏弹出的主界面：按分区排列的开关磁贴。
///
/// 带参数的开关（保持亮屏、耳机连接、屏幕分辨率）占两列，点磁贴弹出 popover 选项。
/// 两条经验写在这里，免得以后走回头路：
///  - 不要用 `Menu` 承载磁贴：配 `.menuStyle(.borderlessButton)` 时自定义 label 的布局
///    会被整个丢掉，磁贴的尺寸和背景都没了。
///  - 整块磁贴只做一件事。此前磁贴主体切开关、右侧 26pt 的小箭头开选项，
///    那个箭头几乎没人找得到；现在开关态移进了选项面板里。
struct MenuContentView: View {
    @EnvironmentObject private var store: SwitchStore
    @ObservedObject private var prefs = Preferences.shared

    @State private var optionsID: String?

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
        .onAppear { store.refresh() }
    }

    // MARK: 数据

    private var visibleItems: [SwitchItem] { prefs.visibleItems(from: store.items) }

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
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: SwitchItem) -> some View {
        if item.span > 1 {
            // 整块磁贴都是「打开选项」，开/关在选项里，不再有两个热区。
            WideTileView(
                item: item,
                isExpanded: optionsID == item.id,
                primary: { optionsID = item.id },
                toggleExpand: { optionsID = item.id }
            )
            .popover(isPresented: Binding(
                get: { optionsID == item.id },
                set: { if !$0 { optionsID = nil } }
            )) {
                options(for: item.id)
                    .padding(13)
                    .environmentObject(store)
            }
        } else {
            SwitchTileView(item: item, phase: store.phases[item.id] ?? "idle") {
                store.activate(item.id)
            }
        }
    }

    @ViewBuilder
    private func options(for id: String) -> some View {
        switch id {
        case "keepAwake":         KeepAwakeOptions()
        case "connectHeadphones": HeadphoneOptions()
        case "resolution":        ResolutionOptions()
        default:                  EmptyView()
        }
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
