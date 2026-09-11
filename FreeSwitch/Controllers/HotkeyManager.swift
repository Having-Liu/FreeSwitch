import AppKit
import Carbon.HIToolbox

// Carbon 事件处理回调必须是 C 约定函数，这里用闭包字面量并把工作派发回主线程。
private let fsHotkeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr {
        let id = hotKeyID.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                HotkeyManager.shared.handle(hotKeyID: id)
            }
        }
    }
    return noErr
}

/// 用 Carbon RegisterEventHotKey 实现系统级全局快捷键（无需辅助功能授权）。
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// 触发时回调对应开关 id。
    var onTrigger: ((String) -> Void)?

    private var installed = false
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var idToSwitch: [UInt32: String] = [:]
    private var nextID: UInt32 = 1

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), fsHotkeyHandler, 1, &spec, nil, nil)
        installed = true
    }

    /// 根据偏好里的快捷键映射重新注册全部热键。
    func reload(from hotkeys: [String: Hotkey]) {
        installHandlerIfNeeded()
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        idToSwitch.removeAll()

        for (switchID, hotkey) in hotkeys {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x46535731), id: id) // 'FSW1'
            let status = RegisterEventHotKey(
                hotkey.keyCode,
                hotkey.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs[id] = ref
                idToSwitch[id] = switchID
            }
        }
    }

    func handle(hotKeyID: UInt32) {
        guard let switchID = idToSwitch[hotKeyID] else { return }
        onTrigger?(switchID)
    }
}
