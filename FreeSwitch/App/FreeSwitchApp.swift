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
struct MenuBarLabel: View {
    @ObservedObject var store: SwitchStore
    var body: some View {
        Image(systemName: "switch.2")
            .foregroundStyle(store.anyStickyActive ? Color.accentColor : Color.primary)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏 App：默认不显示 Dock 图标。
        NSApp.setActivationPolicy(.accessory)

        // 若上次异常退出遗留了“合盖不休眠”，启动时恢复系统设置。
        PowerController.shared.recoverClamshellIfNeeded()

        // 全局热键 → 触发对应开关。
        HotkeyManager.shared.onTrigger = { id in
            SwitchStore.shared.activate(id)
        }
        HotkeyManager.shared.reload(from: Preferences.shared.hotkeys)
    }
}
