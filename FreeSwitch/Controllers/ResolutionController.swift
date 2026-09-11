import CoreGraphics

/// 屏幕分辨率：列出主显示器可用分辨率并切换。
enum ResolutionController {
    struct Resolution: Identifiable, Hashable {
        let id: Int32          // ioDisplayModeID
        let width: Int
        let height: Int
        var label: String { "\(width) × \(height)" }
    }

    static func availableResolutions() -> [Resolution] {
        let display = CGMainDisplayID()
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else { return [] }

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

    static func currentResolution() -> Resolution? {
        let display = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(display) else { return nil }
        return Resolution(id: mode.ioDisplayModeID, width: mode.width, height: mode.height)
    }

    static func apply(_ resolution: Resolution) {
        let display = CGMainDisplayID()
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode],
              let target = modes.first(where: { $0.ioDisplayModeID == resolution.id }) else { return }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayWithDisplayMode(config, display, target, nil)
        CGCompleteDisplayConfiguration(config, .permanently)
    }
}
