import AppKit

/// 通过系统级 systemDefined 事件发送多媒体按键（播放/暂停等），与具体播放器无关。
enum MediaKey {
    static let playPause: Int32 = 16 // NX_KEYTYPE_PLAY

    static func press(_ key: Int32) {
        postKeyEvent(key, down: true)
        postKeyEvent(key, down: false)
    }

    private static func postKeyEvent(_ key: Int32, down: Bool) {
        let flagsValue = down ? 0xA00 : 0xB00
        let data1 = Int((key << 16) | Int32(down ? 0xA00 : 0xB00))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flagsValue)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
