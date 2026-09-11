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
            VStack(spacing: 8) {
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

/// 分辨率磁贴：点击弹出可选分辨率菜单。
struct ResolutionTileView: View {
    let item: SwitchItem
    let onSelect: (ResolutionController.Resolution) -> Void

    @State private var resolutions: [ResolutionController.Resolution] = []
    @State private var current: ResolutionController.Resolution?

    var body: some View {
        Menu {
            ForEach(resolutions) { resolution in
                Button {
                    onSelect(resolution)
                    current = resolution
                } label: {
                    if current?.id == resolution.id {
                        Label(resolution.label, systemImage: "checkmark")
                    } else {
                        Text(resolution.label)
                    }
                }
            }
        } label: {
            VStack(spacing: 8) {
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
        .onAppear {
            resolutions = ResolutionController.availableResolutions()
            current = ResolutionController.currentResolution()
        }
    }
}
