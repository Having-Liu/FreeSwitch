import AppKit
import SwiftUI

/// 全屏遮罩：屏幕清洁时覆盖所有显示器，拦住鼠标点击，并提供退出方式。
@MainActor
final class ScreenCleanOverlay {
    static let shared = ScreenCleanOverlay()

    private var windows: [NSWindow] = []
    private var onStop: (() -> Void)?

    func show(onStop: @escaping () -> Void) {
        guard windows.isEmpty else { return }
        self.onStop = onStop

        for (index, screen) in NSScreen.screens.enumerated() {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.78)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false

            // 只在主屏显示提示卡片，其余屏幕纯遮黑。
            let showsHint = (index == 0)
            let root = ScreenCleanContentView(showsHint: showsHint) { [weak self] in
                self?.onStop?()
            }
            window.contentView = NSHostingView(rootView: root)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        onStop = nil
    }
}

private struct ScreenCleanContentView: View {
    let showsHint: Bool
    let stop: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001) // 捕获鼠标点击，避免落到底层 App
            if showsHint {
                VStack(spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 46, weight: .light))
                    Text("屏幕清洁模式")
                        .font(.title.bold())
                    Text("键盘已锁定，可以放心擦拭屏幕。")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                    Button(action: stop) {
                        Text("完成清洁 (Esc)")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
                .foregroundStyle(.white)
                .padding(48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
