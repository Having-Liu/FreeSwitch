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
            if !hasVisibleItems {
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

    /// 某个分组里要显示的开关：按用户排定的顺序，去掉在设置里隐藏的。
    private func visibleItems(in group: SwitchGroup) -> [SwitchItem] {
        let byID = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
        return group.items.compactMap { byID[$0] }.filter { prefs.isVisible($0.id) }
    }

    private var hasVisibleItems: Bool {
        prefs.groups.contains { !visibleItems(in: $0).isEmpty }
    }

    /// 面板从菜单栏往下展开，网格能用的高度 = 屏幕可视区域 − 标题栏 − 一点余量。
    private var maxGridHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 64
    }

    /// 排进每行 5 列。规则在 GroupLayout.pack（有独立测试）：用户排定的顺序优先，
    /// 放不下就换行，绝不把后面的开关往前挪；行尾空位只拉宽宽磁贴去补。
    private func rows(_ items: [SwitchItem]) -> [[PlacedTile]] {
        GroupLayout.pack(spans: items.map(\.span), columns: TileMetrics.columns).map { row in
            row.map { PlacedTile(item: items[$0.index], span: $0.span) }
        }
    }

    // MARK: 视图

    private var grid: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(prefs.groups) { group in
                let items = visibleItems(in: group)
                if !items.isEmpty { sectionView(prefs.displayName(of: group), items) }
            }
            utilityRow
        }
        .padding(TileMetrics.padding)
        .glassGroup(spacing: TileMetrics.gap)
    }

    // MARK: 末尾的设置 / 退出

    /// 顶部标题栏去掉了（一行只写个 App 名字，不值一整条），设置和退出挪到列表最后，
    /// 压到最低存在感：小字号、次要色，鼠标移上去才变亮。
    /// 它们跟着网格一起滚，不是常驻底栏——常驻底栏会把面板高度撑起来，
    /// 而这个面板的高度是按内容算的。
    private var utilityRow: some View {
        HStack(spacing: 14) {
            SettingsLink { QuietLabel(symbol: "gearshape", title: L("设置")) }
                .buttonStyle(.plain)
            Button { NSApplication.shared.terminate(nil) } label: {
                QuietLabel(symbol: "power", title: L("退出"))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.leading, 3)
        .padding(.top, 2)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("handle").font(.largeTitle).foregroundStyle(.secondary)
            Text("还没有显示任何开关").font(.callout)
            SettingsLink { Text("去设置里开启") }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }
}

/// 列表末尾那两个按钮的样子：默认次要色，悬停才变正文色。
private struct QuietLabel: View {
    let symbol: String
    let title: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 11))
        .foregroundStyle(hovering ? Color.primary : Color.secondary)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
