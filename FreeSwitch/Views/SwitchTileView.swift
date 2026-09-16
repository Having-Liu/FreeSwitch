import SwiftUI

// 面板的网格尺寸。面板宽度固定，所以直接算出列宽——
// 带参数的开关占两列，多出来的宽度用于显示它的当前值和量规。
enum TileMetrics {
    static let panelWidth: CGFloat = 340
    static let padding: CGFloat = 11
    static let gap: CGFloat = 7
    static let height: CGFloat = 60
    static var unit: CGFloat { (panelWidth - padding * 2 - gap * 3) / 4 }
    static func width(span: Int) -> CGFloat {
        unit * CGFloat(span) + gap * CGFloat(span - 1)
    }
}

/// 单列磁贴：开关或一次性动作。
struct SwitchTileView: View {
    let item: SwitchItem
    let phase: String            // idle / running / done
    let action: () -> Void

    private var isOn: Bool { item.kind == .toggle && item.isOn }
    private var isDone: Bool { phase == "done" }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 22)
                    .symbolEffect(.pulse, isActive: phase == "running")
                Text(label)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: TileMetrics.width(span: item.span), height: TileMetrics.height)
            .foregroundStyle(isOn || isDone ? Color.white : Color.primary)
            .glassTile(hue: isDone ? SwitchHue.green : item.hue, isOn: isOn || isDone)
            .opacity(item.isSupported ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!item.isSupported)
        .help(item.isSupported ? item.title : "\(item.title)（当前设备不支持）")
        .animation(.easeInOut(duration: 0.18), value: isOn)
        .animation(.easeInOut(duration: 0.18), value: phase)
    }

    private var symbol: String {
        switch phase {
        case "running": return "hourglass"
        case "done":    return "checkmark"
        default:        return item.symbol
        }
    }
    private var label: String {
        switch phase {
        case "running": return "处理中…"
        case "done":    return "已完成"
        default:        return item.title
        }
    }
}

/// 双列磁贴：带参数的开关。左半边按主操作，右侧箭头就地展开选项。
///
/// 这里刻意不用 `Menu`——`Menu` 配 `.menuStyle(.borderlessButton)` 不采纳自定义 label 的
/// 布局，磁贴的尺寸和背景会被整个丢掉（这正是旧版「保持亮屏」塌掉的原因）。
struct WideTileView: View {
    let item: SwitchItem
    let isExpanded: Bool
    let primary: () -> Void
    let toggleExpand: () -> Void

    private var isOn: Bool { item.kind == .toggle && item.isOn }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: primary) {
                HStack(spacing: 9) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .opacity(0.75)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: toggleExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 26, height: TileMetrics.height)
                    .opacity(0.55)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("展开选项")
        }
        .frame(width: TileMetrics.width(span: item.span), height: TileMetrics.height)
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .overlay(alignment: .bottom) {
            // 量规：保持亮屏走剩余时长，耳机走电量。有量可报才画。
            if let gauge = item.gauge {
                TileGauge(value: gauge, hue: item.hue, isOn: isOn)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
            }
        }
        .glassTile(hue: item.hue, isOn: isOn)
        .animation(.easeInOut(duration: 0.18), value: isOn)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
}

/// 抽屉里的选项胶囊。
struct TileChip: View {
    let title: String
    let selected: Bool
    let hue: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .glassTile(hue: hue, isOn: selected, radius: 8)
        }
        .buttonStyle(.plain)
    }
}
