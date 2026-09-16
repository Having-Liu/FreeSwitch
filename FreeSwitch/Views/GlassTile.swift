import SwiftUI

/// 每个开关的色相。开启时磁贴染上它，扫一眼就知道开了什么，不用逐个读字。
/// 控制中心控件那边的 `.tint()` 也用这一套，两处保持同一种色彩语言。
enum SwitchHue {
    static let indigo = Color(red: 0.357, green: 0.357, blue: 0.839)
    static let amber  = Color(red: 0.910, green: 0.569, blue: 0.176)
    static let teal   = Color(red: 0.184, green: 0.659, blue: 0.627)
    static let blue   = Color(red: 0.290, green: 0.549, blue: 0.910)
    static let coffee = Color(red: 0.706, green: 0.475, blue: 0.310)
    static let green  = Color(red: 0.247, green: 0.643, blue: 0.357)
    static let red    = Color(red: 0.878, green: 0.341, blue: 0.353)
    static let cyan   = Color(red: 0.098, green: 0.710, blue: 0.788)
    static let violet = Color(red: 0.608, green: 0.424, blue: 0.969)
    /// 一次性动作的常态：不抢眼，执行完才短暂亮绿。
    static let neutral = Color(red: 0.545, green: 0.576, blue: 0.655)
}

/// 磁贴的材质。
///
/// macOS 26 起直接用系统的液态玻璃：材质本身、边缘高光、按压与悬停反馈
/// 全部由 `.glassEffect` 提供，`.interactive()` 一个参数就带来了跟手的按压效果——
/// 这些都不该自己用渐变和阴影去仿，系统那份还会自动适配深浅色、
/// 「降低透明度」「增强对比度」等辅助功能设置，手搓的不会。
///
/// App 的部署目标是 macOS 14.6，所以更早的系统退回到普通材质。
struct GlassTileBackground: ViewModifier {
    var hue: Color = SwitchHue.neutral
    var isOn: Bool = false
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(isOn ? hue : nil).interactive(),
                in: .rect(cornerRadius: radius, style: .continuous)
            )
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(hue) : AnyShapeStyle(.regularMaterial))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

extension View {
    func glassTile(hue: Color = SwitchHue.neutral, isOn: Bool = false, radius: CGFloat = 12) -> some View {
        modifier(GlassTileBackground(hue: hue, isOn: isOn, radius: radius))
    }

    /// 把一组玻璃元素放进同一个容器，相邻的玻璃才会按系统的方式互相融合。
    /// 26 以下没有这个容器，原样返回即可。
    @ViewBuilder
    func glassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// 宽磁贴底边那条细量规：保持亮屏走剩余时长，耳机走电量。
/// 它用掉了宽磁贴多出来的那点宽度，而且报的是真实数据，不是装饰。
struct TileGauge: View {
    let value: Double          // 0…1
    let hue: Color
    let isOn: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(hue))
                    .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 2)
        .animation(.easeOut(duration: 0.45), value: value)
    }
}
