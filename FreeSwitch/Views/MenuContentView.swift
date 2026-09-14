import SwiftUI

/// 菜单栏弹出的主界面：开关磁贴网格。
struct MenuContentView: View {
    @EnvironmentObject private var store: SwitchStore
    @ObservedObject private var prefs = Preferences.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var visibleItems: [SwitchItem] { prefs.visibleItems(from: store.items) }

    private var gridHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(visibleItems.count) / 4.0)))
        let needed = CGFloat(rows) * 64 + CGFloat(rows - 1) * 10 + 24
        return min(needed, 384)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(visibleItems) { item in
                            if item.id == "keepAwake" {
                                KeepAwakeTileView(item: item)
                            } else if item.kind == .picker {
                                ResolutionTileView(item: item)
                            } else {
                                SwitchTileView(item: item, isFlashing: store.flashingID == item.id) {
                                    store.activate(item.id)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(height: gridHeight)
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "switch.2")
                .foregroundStyle(Color.accentColor)
            Text("FreeSwitch")
                .font(.headline)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新状态")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "switch.2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有显示任何开关")
                .font(.callout)
            SettingsLink { Text("去设置里开启") }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var footer: some View {
        HStack {
            Text("免费 · 开源 · 献给大家")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
