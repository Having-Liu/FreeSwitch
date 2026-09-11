import AppKit
import Carbon.HIToolbox

/// 一个全局快捷键的键值表示。
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32          // 虚拟键码（NSEvent.keyCode）
    var carbonModifiers: UInt32  // Carbon 修饰键掩码
    var display: String          // 例如 "⌥⌘L"

    /// 从一次按键事件构造。返回 nil 表示只按了修饰键。
    init?(event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        // 必须带至少一个修饰键，避免和普通输入冲突。
        guard carbon != 0 else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon

        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option)  { text += "⌥" }
        if flags.contains(.shift)   { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += Self.keyName(for: event)
        self.display = text
    }

    private static func keyName(for event: NSEvent) -> String {
        // 特殊键优先按键码识别，其余用字符。
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return (event.charactersIgnoringModifiers ?? "").uppercased()
        }
    }
}
