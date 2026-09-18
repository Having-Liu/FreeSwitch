import SwiftUI

@main
struct FreeSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = SwitchStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// 菜单栏图标：有常驻开关激活时用强调色提示。
///
/// 用的是自制符号 `handle`（Assets.xcassets/handle.symbolset，SF Symbols App 导出的模板）。
/// 自制符号要用 `Image(_:)` 而不是 `Image(systemName:)`——后者只认系统符号库里的名字。
/// 它和系统符号一样支持字重、缩放和着色，所以 foregroundStyle 照旧生效。
struct MenuBarLabel: View {
    @ObservedObject var store: SwitchStore
    var body: some View {
        Image("handle")
            .foregroundStyle(store.anyStickyActive ? Color.accentColor : Color.primary)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏 App：默认不显示 Dock 图标。
        NSApp.setActivationPolicy(.accessory)

        // 若上次异常退出遗留了“合盖不休眠”，启动时恢复系统设置。
        PowerController.shared.recoverClamshellIfNeeded()

        // 接收来自控制中心控件 / 快捷指令 / Siri 的触发。
        FreeSwitchTrigger.startObserving()
        // 启动即读一次真实状态并写入共享区，让控制中心控件一开始就显示正确开/关。
        SwitchStore.shared.refresh()

        // 全局热键 → 触发对应开关。
        HotkeyManager.shared.onTrigger = { id in
            SwitchStore.shared.activate(id)
        }
        HotkeyManager.shared.reload(from: Preferences.shared.hotkeys)

        // 首次启动弹一次引导。放在最后：前面那些初始化要先跑完，
        // 引导第二、四页嵌的是真的设置页，它们读的就是这些初始化后的状态。
        OnboardingWindow.presentIfNeeded()
    }
}
