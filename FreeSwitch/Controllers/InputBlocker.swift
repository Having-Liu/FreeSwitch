import AppKit
import ApplicationServices
import CoreGraphics

// 事件拦截模式的位标记（供 C 回调与主线程共用的全局状态）。
// 1 = 拦截键盘, 2 = 拦截鼠标
nonisolated(unsafe) private var fsBlockerMask: UInt64 = 0

/// CGEventTap 的 C 回调：根据全局位标记吞掉相应事件。
/// 该 tap 加入主运行循环，回调在主线程触发。用 C 约定的闭包字面量以形成函数指针。
private let fsInputTapCallback: CGEventTapCallBack = { _, type, event, _ in
    let mask = fsBlockerMask
    switch type {
    case .keyDown, .keyUp, .flagsChanged:
        if mask & 1 != 0 { return nil } // 拦截全部键盘输入（含 Esc），避免擦键盘时误触
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
         .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
         .otherMouseDown, .otherMouseUp, .otherMouseDragged:
        if mask & 2 != 0 { return nil }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

/// 锁定键盘 + 屏幕清洁：基于 CGEventTap 拦截输入（需“辅助功能”授权）。
@MainActor
final class InputBlocker {
    static let shared = InputBlocker()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var isKeyboardLocked = false
    private(set) var isScreenCleanActive = false

    // MARK: 锁定键盘
    func setKeyboardLocked(_ locked: Bool) {
        if locked {
            guard ensureAccessibility(), ensureTap() else { return }
            fsBlockerMask |= 1
            isKeyboardLocked = true
        } else {
            fsBlockerMask &= ~1
            isKeyboardLocked = false
            teardownIfIdle()
        }
    }

    // MARK: 屏幕清洁
    func startScreenClean() {
        guard ensureAccessibility(), ensureTap() else { return }
        fsBlockerMask |= 1 // 拦截全部键盘；鼠标由全屏遮罩层拦住，仅「完成清洁」按钮可退出
        isScreenCleanActive = true
        ScreenCleanOverlay.shared.show { [weak self] in
            self?.stopScreenClean()
        }
    }

    func stopScreenClean() {
        if !isKeyboardLocked { fsBlockerMask &= ~1 }
        isScreenCleanActive = false
        ScreenCleanOverlay.shared.hide()
        teardownIfIdle()
    }

    // MARK: 内部
    private func maskBit(_ type: CGEventType) -> CGEventMask { CGEventMask(1) << type.rawValue }

    private func ensureTap() -> Bool {
        if eventTap != nil { return true }
        let interested: CGEventMask =
            maskBit(.keyDown) | maskBit(.keyUp) | maskBit(.flagsChanged) |
            maskBit(.leftMouseDown) | maskBit(.leftMouseUp) |
            maskBit(.rightMouseDown) | maskBit(.rightMouseUp) |
            maskBit(.otherMouseDown) | maskBit(.otherMouseUp) |
            maskBit(.mouseMoved) | maskBit(.leftMouseDragged) |
            maskBit(.rightMouseDragged) | maskBit(.scrollWheel)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: interested,
            callback: fsInputTapCallback,
            userInfo: nil
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    private func teardownIfIdle() {
        guard fsBlockerMask == 0, let tap = eventTap, let source = runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = nil
        runLoopSource = nil
    }

    @discardableResult
    private func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
