import SwiftUI
import AppKit

// MARK: - 设置窗口的家族外壳
//
// 这一层是和 Dam 共用的「家族语言」：玻璃外壳 + 浮在上面的侧边栏 + 压住侧边栏右缘的内容卡片。
// 类型名、度量、材质参数都和 Dam/SettingsWindowChrome.swift、Dam/SettingsView.swift 一致，
// 整个文件可以在两个项目之间直接搬。**改动请两边同步**，否则家族语言就散了。
//
// 里面的数字不是随手挑的，改之前先读注释里的理由。

/// 家族度量。Dam 的原值，不要按「这个 App 内容少」去缩——缩了就不是同一套语言了。
enum SettingsSurface {
    /// 侧边栏占据的横向区域（含左右留白）。
    static let sidebarWidth: CGFloat = 286
    /// 侧边栏里条目的实际宽度。
    static let sidebarContentWidth: CGFloat = 224
    /// 内容卡片往左压住侧边栏的量。卡片压上去才有前后层次，齐边会显得是两块拼版。
    static let contentOverlap: CGFloat = 34
    /// 给左上角红绿灯按钮让出的高度。
    static let titlebarClearance: CGFloat = 70
    /// 卡片到窗口边的留白。
    static let surfaceInset: CGFloat = 14
    /// NSWindow 的系统圆角没有稳定的公开接口，这是校准出来的近似值，
    /// 用它反推内容卡片的圆角，让内外两层曲率接近同心。
    static let outerWindowCornerRadiusEstimate: CGFloat = 28

    static var contentCardLeadingInset: CGFloat { sidebarWidth - contentOverlap }

    static var sidebarHorizontalInset: CGFloat {
        max(18, (contentCardLeadingInset - sidebarContentWidth) / 2)
    }

    static var contentCardCornerRadius: CGFloat {
        max(12, outerWindowCornerRadiusEstimate - surfaceInset)
    }
}

// MARK: 窗口

/// 去掉系统标题栏，自己画一层玻璃。
///
/// 为什么不要系统标题栏：这个窗口左边是一条浮在玻璃上的侧边栏，
/// 标题栏那条不透明的横条会把玻璃从顶上切断，侧边栏就变成「悬在一块白板上」。
enum SettingsWindowChrome {

    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
        // 没有标题栏可抓，所以整块背景都能拖动窗口。
        window.isMovableByWindowBackground = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        layoutTrafficLights(in: window)
        window.invalidateShadow()
    }

    /// 红绿灯按钮默认在标题栏高度里居中；标题栏透明之后那个位置偏低、
    /// 和侧边栏顶部的留白对不齐，所以手动摆到 (16, 14)。
    static func layoutTrafficLights(in window: NSWindow) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview else { return }

        let top: CGFloat = 14, leading: CGFloat = 16, spacing: CGFloat = 6
        let isRTL = window.windowTitlebarLayoutDirection == .rightToLeft
        for (index, button) in buttons.enumerated() {
            let y = container.bounds.height - button.frame.height - top
            let offset = CGFloat(index) * (button.frame.width + spacing)
            let x = isRTL ? container.bounds.width - leading - button.frame.width - offset
                          : leading + offset
            button.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

/// 把上面那套配置挂到 SwiftUI 窗口上。
///
/// `Settings { }` 场景的 NSWindow 不归我们创建，只能等视图进了窗口再回头改它。
/// 配置要跑两次：`viewDidMoveToWindow` 时窗口还在组装，红绿灯会被系统再摆一次，
/// 下一轮 runloop 里补一次才稳。
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObserverView { WindowObserverView() }
    func updateNSView(_ view: WindowObserverView, context: Context) { view.applyIfPossible() }

    final class WindowObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyIfPossible()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyIfPossible()
        }

        func applyIfPossible() {
            guard let window else { return }
            SettingsWindowChrome.configure(window)
            DispatchQueue.main.async { SettingsWindowChrome.configure(window) }
        }
    }
}

// MARK: 材质

/// 窗口背后的系统材质。
///
/// `.underWindowBackground` + `.behindWindow` 是「整扇窗户的底」那一档，会真的把桌面糊进来；
/// SwiftUI 那几个 `.regularMaterial` 只在窗口内部混合，铺满整窗时看着就是一块灰纸。
struct SettingsGlassBackgroundView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// 玻璃外壳：系统材质打底，叠一层对角渐变、两团模糊光晕、顶边和左侧两道高光。
///
/// 两道高光是「玻璃有厚度」的关键，缺了整面就发平。
/// 光晕的颜色留给各 App 自己传——那是每个 App 的身份色，Dam 是青蓝，FreeSwitch 用图标上那两个蓝。
struct SettingsGlassShell: View {
    var primaryHalo: Color
    var secondaryHalo: Color

    var body: some View {
        ZStack {
            SettingsGlassBackgroundView()

            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.03), .black.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(primaryHalo.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 100)
                .offset(x: -140, y: -170)

            Circle()
                .fill(secondaryHalo.opacity(0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: -120, y: 260)

            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.20), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: SettingsSurface.sidebarWidth + 120)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: 内容卡片

extension View {
    /// 压在侧边栏右缘上的那张卡片：窗口底色的竖向渐变 + 一圈白描边 + 一层大而软的阴影。
    /// 描边是让卡片「从玻璃上浮起来」的那一笔，去掉就糊在背景里了。
    func settingsContentCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsSurface.contentCardCornerRadius,
                                     style: .continuous)
        return self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor).opacity(0.98),
                                 Color(nsColor: .windowBackgroundColor).opacity(0.94)],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.stroke(.white.opacity(0.42), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 14)
    }
}

// MARK: 侧边栏条目

/// 选中和悬停都靠不同透明度的白色填充 + 描边，
/// 让它看起来是「浮在玻璃上的一小片玻璃」，而不是涂了个色块。
/// 深浅色两套值分开写：深色模式下同一组白色透明度会糊成一团。
struct SettingsSidebarItem: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    var badgeText: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isDark: Bool { colorScheme == .dark }

    private var fillColor: Color {
        if isSelected { return isDark ? .white.opacity(0.14) : .white.opacity(0.84) }
        if isHovering { return isDark ? .white.opacity(0.07) : .white.opacity(0.38) }
        return .clear
    }

    private var strokeColor: Color {
        if isSelected { return isDark ? .white.opacity(0.26) : .white.opacity(0.96) }
        if isHovering { return isDark ? .white.opacity(0.14) : .white.opacity(0.55) }
        return .clear
    }

    private var foregroundColor: Color {
        if isDark {
            if isSelected { return .white.opacity(0.96) }
            return isHovering ? .white.opacity(0.90) : .white.opacity(0.72)
        }
        return isSelected ? .primary : (isHovering ? .primary.opacity(0.92) : .secondary)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDark ? Color.orange.opacity(0.96) : Color.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous)
                            .fill(Color.orange.opacity(isDark ? 0.18 : 0.10)))
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

/// 侧边栏里的一组：11pt 半粗的次要色小标题 + 若干条目。
struct SettingsSidebarGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
            content
        }
    }
}
