import SwiftUI

/// 单个开关磁贴。
struct SwitchTileView: View {
    let item: SwitchItem
    let isFlashing: Bool
    let action: () -> Void

    @State private var hovering = false

    private var highlighted: Bool {
        (item.kind == .toggle && item.isOn) || isFlashing
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(highlighted ? Color.accentColor : Color.primary.opacity(hovering ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(hovering && item.isSupported ? 1.04 : 1)
            .opacity(item.isSupported ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!item.isSupported)
        .onHover { hovering = $0 }
        .help(item.isSupported ? item.title : "\(item.title)（当前设备不支持）")
        .animation(.easeInOut(duration: 0.15), value: highlighted)
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}

/// 保持亮屏磁贴：点击弹出时长菜单（一直 / 30 分 / 1 小时 / 2 小时 / 关闭）。
/// 全局热键仍可直接切换“一直亮屏”。
struct KeepAwakeTileView: View {
    let item: SwitchItem
    @EnvironmentObject private var store: SwitchStore

    var body: some View {
        Menu {
            Button { apply(nil) } label: {
                menuRow("一直亮屏", checked: item.isOn && PowerController.shared.keepAwakeDeadline == nil)
            }
            Button { apply(30) } label: { Text("30 分钟") }
            Button { apply(60) } label: { Text("1 小时") }
            Button { apply(120) } label: { Text("2 小时") }
            if item.isOn {
                Divider()
                Button("关闭") { apply(off: true) }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .foregroundStyle(item.isOn ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.isOn ? Color.accentColor : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func apply(_ minutes: Int?) {
        PowerController.shared.setKeepAwake(true, minutes: minutes)
        store.refresh()
    }

    private func apply(off: Bool) {
        PowerController.shared.setKeepAwake(false)
        store.refresh()
    }

    @ViewBuilder
    private func menuRow(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// 分辨率磁贴：点击弹出分辨率菜单。多显示器时每块屏一个子菜单。
struct ResolutionTileView: View {
    let item: SwitchItem

    @State private var displays: [ResolutionController.Display] = []

    var body: some View {
        Menu {
            if displays.count <= 1, let display = displays.first {
                resolutionButtons(for: display)
            } else {
                ForEach(displays) { display in
                    Menu(display.name) {
                        resolutionButtons(for: display)
                    }
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onAppear { displays = ResolutionController.displays() }
    }

    @ViewBuilder
    private func resolutionButtons(for display: ResolutionController.Display) -> some View {
        ForEach(display.resolutions) { resolution in
            Button {
                ResolutionController.apply(resolution, to: display.id)
                displays = ResolutionController.displays()
            } label: {
                if display.currentID == resolution.id {
                    Label(resolution.label, systemImage: "checkmark")
                } else {
                    Text(resolution.label)
                }
            }
        }
    }
}
