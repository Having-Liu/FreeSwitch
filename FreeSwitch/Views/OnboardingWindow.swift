import AppKit
import SwiftUI

/// 首次启动的引导窗口。
///
/// **层级必须是 `.normal`。** 第四页要用户直接在嵌进来的权限面板里授权，
/// 而授权会拉起「系统设置」——只要引导窗口高于普通层级，系统设置就会被压在它下面，
/// 用户看不到自己该点哪儿。`.normal` 下两扇窗口按焦点排序，谁激活谁在上，正合适。
///
/// 也因此它铺的是 `visibleFrame` 而不是 `frame`：`.normal` 层级本来就盖不住菜单栏，
/// 强行铺满整屏只会在顶上留一条错位的缝。菜单栏留着还有个好处——
/// 引导过程中用户随时能点开菜单栏图标看一眼真家伙。
@MainActor
enum OnboardingWindow {

    private static let completedKey = "pref.onboardingCompleted"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// 首次启动时自动弹一次。已经看过就什么都不做。
    static func presentIfNeeded() {
        guard !hasCompleted else { return }
        present()
    }

    static func present() {
        // 菜单栏 App 平时是 accessory，没有窗口焦点概念；要让引导能被激活、能收键盘，
        // 得临时变回普通 App。关掉时再变回去（和设置窗口同一套路）。
        NSApp.setActivationPolicy(.regular)

        let window = makeWindow()
        Self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: completedKey)
        close()
    }

    /// 跳过也算看过——再弹一次只会更烦。想回看可以从设置里进。
    static func close() {
        UserDefaults.standard.set(true, forKey: completedKey)
        window?.orderOut(nil)
        window = nil
        // 设置窗口可能还开着，那就别抢它的 policy。
        if NSApp.windows.allSatisfy({ !$0.isVisible || $0.level == .statusBar }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private static var window: NSWindow?

    private static func makeWindow() -> NSWindow {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = KeyableWindow(
            contentRect: screen.visibleFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.level = .normal                 // 见上面那段说明，别改
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = NSHostingController(rootView: OnboardingView())
        window.setFrame(screen.visibleFrame, display: true)
        return window
    }

    /// 无边框窗口默认不能成为 key window，键盘和文本框都不响应，必须自己放开。
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
