import SwiftUI

// 面板的网格尺寸：每行 5 列，面板宽度由列宽反推。
// 5 列时各分区恰好能排满一行（1+1+1+2、2+1+1+1、五个单列），4 列则到处是空洞。
// 带参数的开关至少占两列，多出来的宽度用于显示它的当前值和量规。
enum TileMetrics {
    static let columns = 5
    static let unit: CGFloat = 76        // 单列宽度：放得下「显示隐藏文件」这样的六字标签
    static let padding: CGFloat = 11
    static let gap: CGFloat = 7
    static let height: CGFloat = 60
    static var panelWidth: CGFloat {
        unit * CGFloat(columns) + gap * CGFloat(columns - 1) + padding * 2
    }
    static func width(span: Int) -> CGFloat {
        unit * CGFloat(span) + gap * CGFloat(span - 1)
    }
}

/// 开关的图标：SF 符号，加上可选的右下角标。
///
/// 关闭时按各自色相着色——扫一眼靠颜色就能分辨，不用逐个读字；中性色的开关用正文色，
/// 免得灰蒙蒙的像被禁用。开启时磁贴已经染上色相，图标改为白色，否则会和底色糊成一片。
struct SwitchIcon: View {
    let item: SwitchItem
    let isOn: Bool
    let size: CGFloat

    private var tint: Color { item.hue == SwitchHue.neutral ? Color.primary : item.hue }

    var body: some View {
        glyph(item.symbol, size: size)
            .overlay(alignment: .bottomTrailing) {
                if let badge = item.badge {
                    glyph(badge, size: size * 0.46)
                        .offset(x: size * 0.30, y: size * 0.16)
                }
            }
    }

    @ViewBuilder
    private func glyph(_ name: String, size: CGFloat) -> some View {
        let image = Image(systemName: name).font(.system(size: size, weight: .medium))
        if isOn {
            image.foregroundStyle(Color.white)
        } else if item.accentsPrimaryLayer {
            // 只染主图层：麦克风静音是斜线红、话筒保持正文色。
            image.symbolRenderingMode(.palette).foregroundStyle(tint, Color.primary)
        } else {
            image.foregroundStyle(tint)
        }
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
                Group {
                    if phase == "idle" {
                        SwitchIcon(item: item, isOn: isOn, size: 19)
                    } else {
                        // 处理中 / 已完成：临时换成沙漏和对勾，不带角标。
                        Image(systemName: symbol)
                            .font(.system(size: 19, weight: .medium))
                            .symbolEffect(.pulse, isActive: phase == "running")
                    }
                }
                .frame(height: 22)
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
        .help(item.isSupported ? item.localizedTitle : L("%@（当前设备不支持）", item.localizedTitle))
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
        case "running": return L("处理中…")
        case "done":    return L("已完成")
        default:        return item.localizedTitle
        }
    }
}

/// 双列磁贴：带参数的开关。左半边按主操作，右侧箭头就地展开选项。
///
/// 这里刻意不用 `Menu`——`Menu` 配 `.menuStyle(.borderlessButton)` 不采纳自定义 label 的
/// 布局，磁贴的尺寸和背景会被整个丢掉（这正是旧版「保持亮屏」塌掉的原因）。
struct WideTileView: View {
    let item: SwitchItem
    /// 实际占的列数。排版时行尾剩下的空位会分给宽磁贴，所以可能比 item.span 大。
    let span: Int
    let isExpanded: Bool
    let primary: () -> Void
    let toggleExpand: () -> Void

    private var isOn: Bool { item.kind == .toggle && item.isOn }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: primary) {
                HStack(spacing: 9) {
                    SwitchIcon(item: item, isOn: isOn, size: 19)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.localizedTitle)
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
        .frame(width: TileMetrics.width(span: span), height: TileMetrics.height)
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

