import SwiftUI

/// 设置窗口。
///
/// 外壳、度量、侧边栏条目全部来自 `SettingsChrome.swift` 那层家族语言（和 Dam 共用一套，
/// 整个文件可以在两个项目之间直接搬）。这里只负责：分几页、每页放什么。
///
/// 为什么从「一条长滚动」改成分页——旧版把五件性质完全不同的事塞进同一个 List：
/// 二十多个开关的排序、耳机选设备、勿扰的一次性配置、免密助手、彻底卸载。
/// 结果是想点「彻底卸载」得先滚过 24 行开关，而分区标题吸顶时还会糊在开关上。
struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var pane: SettingsPane = .switches
    @State private var identityHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsGlassShell(primaryHalo: SwitchHue.indigo, secondaryHalo: SwitchHue.blue)

            sidebar
                .frame(width: SettingsSurface.sidebarContentWidth)
                .padding(.leading, SettingsSurface.sidebarHorizontalInset)
                .padding(.top, SettingsSurface.titlebarClearance)
                .padding(.bottom, 20)

            page
                .settingsContentCard()
                .padding(.top, SettingsSurface.surfaceInset)
                .padding(.bottom, SettingsSurface.surfaceInset)
                .padding(.trailing, SettingsSurface.surfaceInset)
                .padding(.leading, SettingsSurface.contentCardLeadingInset)
        }
        .background(SettingsWindowConfigurator())
        // 侧边栏本身就占 286，窗口再窄内容卡片就没地方了。
        // 比 Dam 的 990×720 小一圈：这边内容少，但结构和留白保持同一套。
        .frame(minWidth: 880, idealWidth: 940, maxWidth: .infinity,
               minHeight: 620, idealHeight: 700, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            // 设置窗口要能被前置、能进 Command-Tab，所以临时变回普通 App；
            // 关掉窗口再变回菜单栏附件，否则程序坞里会一直留一个图标。
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: 侧边栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSidebarGroup(title: L("常用")) {
                item(.switches)
                item(.language)
            }
            SettingsSidebarGroup(title: L("高级")) {
                item(.permissions)
                item(.uninstall)
            }
            Spacer(minLength: 0)
            // 「更多 App」不属于任何一组设置，摆在最下面、紧挨着身份块，读起来像页脚导航。
            item(.moreApps)
            identity
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func item(_ target: SettingsPane) -> some View {
        SettingsSidebarItem(symbol: target.symbol,
                            title: target.title,
                            isSelected: pane == target) { pane = target }
    }

    /// App 身份放侧边栏最下角——它是「这是什么」而不是「要设置什么」，
    /// 不该在导航列表里占一格。Dam 的使用指南入口也在这个位置。
    /// 整块就是项目主页的入口：一个「项目主页」按钮单独占一个设置区太孤零零了。
    private var identity: some View {
        Button {
            if let url = URL(string: "https://github.com/Having-Liu/FreeSwitch") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 9) {
                Image("handle")
                    .font(.system(size: 18))
                    .foregroundStyle(SwitchHue.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FreeSwitch").font(.system(size: 12, weight: .semibold))
                    Text(Self.versionString).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(identityHovering ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(identityHovering ? Color.white.opacity(0.32) : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(L("项目主页"))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { identityHovering = h } }
    }

    static var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return L("版本 %@", short)
    }

    // MARK: 内容

    @ViewBuilder
    private var page: some View {
        switch pane {
        case .switches:    SwitchesPane(prefs: prefs)
        case .language:    LanguagePane()
        case .permissions: PermissionsPane()
        case .uninstall:   UninstallPane()
        case .moreApps:    MoreAppsPane()
        }
    }
}

// MARK: - 分页

enum SettingsPane: String, CaseIterable, Identifiable {
    case switches, language, permissions, uninstall, moreApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .switches:    return L("开关")
        case .language:    return L("语言")
        case .permissions: return L("权限")
        case .uninstall:   return L("彻底卸载")
        case .moreApps:    return L("更多 App")
        }
    }

    var symbol: String {
        switch self {
        case .switches:    return "switch.2"
        case .language:    return "globe"
        case .permissions: return "lock.shield"
        case .uninstall:   return "trash"
        case .moreApps:    return "square.grid.2x2"
        }
    }
}

/// 每一页共用的头：标题 + 一句说明。说明是灰的小字，不抢标题。
struct PaneHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 16, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}
