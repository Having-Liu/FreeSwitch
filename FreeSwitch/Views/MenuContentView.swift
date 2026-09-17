import SwiftUI

/// 菜单栏弹出的主界面：按分区排列的开关磁贴。
///
/// 带参数的开关（保持亮屏、耳机连接、屏幕分辨率）至少占两列，点磁贴弹出 popover 选项。
/// 几条经验写在这里，免得以后走回头路：
///  - 不要用 `Menu` 承载磁贴：配 `.menuStyle(.borderlessButton)` 时自定义 label 的布局
///    会被整个丢掉，磁贴的尺寸和背景都没了。
///  - 整块磁贴只做一件事。曾经磁贴主体切开关、右侧 26pt 的小箭头开选项，
///    那个箭头几乎没人找得到；现在开关态移进了选项面板里。
///  - 高度跟着内容走。只有内容超出屏幕可视高度时才套滚动视图——
///    MenuBarExtra 按内容的理想尺寸定窗口大小，而 ScrollView 没有理想高度，
///    无条件套上去窗口就会塌成一条（最早那个“面板中间是空的”就是这么来的）。
struct MenuContentView: View {
    @EnvironmentObject private var store: SwitchStore
    @ObservedObject private var prefs = Preferences.shared

    @State private var optionsID: String?
    @State private var gridHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleItems.isEmpty {
                emptyState
            } else if gridHeight > maxGridHeight {
                ScrollView { measuredGrid }
                    .frame(height: maxGridHeight)
            } else {
                measuredGrid
            }
        }
        .frame(width: TileMetrics.panelWidth)
        // 打开面板时读一次真实状态。面板开着的期间，状态由系统通知、
        // 蓝牙连接通知和每 5 秒的核对保持最新，所以不再需要手动「刷新」按钮。
        .onAppear { store.refresh() }
    }

    // MARK: 数据

    private var visibleItems: [SwitchItem] { prefs.visibleItems(from: store.items) }

    private func items(in section: String) -> [SwitchItem] {
        visibleItems.filter { $0.section == section }
    }

    /// 面板从菜单栏往下展开，网格能用的高度 = 屏幕可视区域 − 标题栏 − 一点余量。
    private var maxGridHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 64
    }

    /// 把磁贴装进每行 5 列。
    ///  - 放不下时往后找能塞进空位的，而不是直接换行留下空洞；
    ///  - 行尾仍剩空位时分给行内的宽磁贴（它至少两列，有弹性），让每行右边缘对齐。
    /// 只有一行里既没有宽磁贴、又凑不满时才会留空——通常是用户在设置里隐藏了一些开关。
    private func rows(_ items: [SwitchItem]) -> [[PlacedTile]] {
        let columns = TileMetrics.columns
        var pending = items
        var result: [[PlacedTile]] = []
        while !pending.isEmpty {
            var row: [PlacedTile] = []
            var used = 0
            var index = 0
            while index < pending.count, used < columns {
                let span = min(pending[index].span, columns)
                if used + span <= columns {
                    row.append(PlacedTile(item: pending.remove(at: index), span: span))
                    used += span
                } else {
                    index += 1
                }
            }
            if used < columns, let wide = row.firstIndex(where: { $0.item.span > 1 }) {
                row[wide].span += columns - used
            }
            result.append(row)
        }
        return result
    }

    // MARK: 视图

    private var grid: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(SwitchCatalog.sections, id: \.self) { section in
                let items = items(in: section)
                if !items.isEmpty { sectionView(section, items) }
            }
        }
        .padding(TileMetrics.padding)
        .glassGroup(spacing: TileMetrics.gap)
    }

    /// 量出网格的自然高度，用来决定要不要滚动。
    private var measuredGrid: some View {
        grid
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: GridHeightKey.self, value: geo.size.height)
                }
            }
            .onPreferenceChange(GridHeightKey.self) { gridHeight = $0 }
    }

    private func sectionView(_ section: String, _ items: [SwitchItem]) -> some View {
        VStack(alignment: .leading, spacing: TileMetrics.gap) {
            Text(section)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 3)

            ForEach(Array(rows(items).enumerated()), id: \.offset) { _, row in
                HStack(spacing: TileMetrics.gap) {
                    ForEach(row) { placed in tile(placed) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ placed: PlacedTile) -> some View {
        let item = placed.item
        if item.span > 1 {
            // 整块磁贴都是「打开选项」，开/关在选项里，不再有两个热区。
            WideTileView(
                item: item,
                span: placed.span,
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

    // MARK: 标题栏

    /// 底栏已经去掉，退出放到这里；原来的「刷新」按钮也去掉了（见 onAppear 上的说明）。
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "switch.2")
                .foregroundStyle(Color.accentColor)
            Text("FreeSwitch").font(.headline)
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .help("设置")
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("退出 FreeSwitch")
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
}

/// 排版后落到某一行里的磁贴：记录它实际占的列数（宽磁贴可能被拉宽去填空位）。
struct PlacedTile: Identifiable {
    let item: SwitchItem
    var span: Int
    var id: String { item.id }
}

private struct GridHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
