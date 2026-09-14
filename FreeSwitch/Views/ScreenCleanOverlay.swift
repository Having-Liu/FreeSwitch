import AppKit
import SwiftUI

/// 全屏遮罩：屏幕清洁时用纯黑不透明覆盖每一块显示器，拦住鼠标点击。
/// 键盘全程被锁定（含 Esc），只能点「完成清洁」退出，避免擦拭键盘时误触退出。
@MainActor
final class ScreenCleanOverlay {
    static let shared = ScreenCleanOverlay()

    private var windows: [NSWindow] = []
    private var onStop: (() -> Void)?

    func show(onStop: @escaping () -> Void) {
        guard windows.isEmpty else { return }
        self.onStop = onStop

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false

            // 每一块屏幕都显示提示与退出按钮。
            let root = ScreenCleanContentView { [weak self] in
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
    let stop: () -> Void

    var body: some View {
        ZStack {
            Color.black // 纯黑不透明，同时捕获鼠标点击
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 46, weight: .light))
                Text("屏幕清洁中")
                    .font(.title.bold())
                Text("键盘已锁定，可放心擦拭屏幕和键盘。\n完成后点下方按钮退出。")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                Button(action: stop) {
                    Text("完成清洁")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
