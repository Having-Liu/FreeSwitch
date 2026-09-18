import CoreGraphics
import AppKit

/// 屏幕分辨率：列出每一块显示器的可用分辨率并切换（支持多显示器）。
enum ResolutionController {
    struct Resolution: Identifiable, Hashable {
        let id: Int32          // ioDisplayModeID
        let width: Int
        let height: Int
        var label: String { "\(width) × \(height)" }
    }

    struct Display: Identifiable {
        let id: CGDirectDisplayID
        let name: String
        let resolutions: [Resolution]
        let currentID: Int32
    }

    /// 所有在用的显示器。
    static func displays() -> [Display] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { id in
            Display(id: id, name: name(for: id), resolutions: resolutions(for: id), currentID: currentModeID(for: id))
        }
    }

    static func apply(_ resolution: Resolution, to displayID: CGDirectDisplayID) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              let target = modes.first(where: { $0.ioDisplayModeID == resolution.id }) else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayWithDisplayMode(config, displayID, target, nil)
        CGCompleteDisplayConfiguration(config, .permanently)
    }

    // MARK: 内部
    private static func resolutions(for displayID: CGDirectDisplayID) -> [Resolution] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else { return [] }
        var seen = Set<String>()
        var results: [Resolution] = []
        for mode in modes where mode.isUsableForDesktopGUI() {
            let key = "\(mode.width)x\(mode.height)"
            if seen.contains(key) { continue }
            seen.insert(key)
            results.append(Resolution(id: mode.ioDisplayModeID, width: mode.width, height: mode.height))
        }
        return results.sorted { ($0.width, $0.height) > ($1.width, $1.height) }
    }

    private static func currentModeID(for displayID: CGDirectDisplayID) -> Int32 {
        CGDisplayCopyDisplayMode(displayID)?.ioDisplayModeID ?? -1
    }

    private static func name(for displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? CGDirectDisplayID, number == displayID {
                return screen.localizedName
            }
        }
        return L("显示器")
    }
}
