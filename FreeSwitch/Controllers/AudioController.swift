import AppKit
import CoreAudio

/// 声音相关：输入设备的底层读写、播放 / 暂停。
///
/// 「麦克风静音」这个开关的行为（静音全部真实麦克风、守着不让人解除、出事就发通知）
/// 在 MicGuard 里；这里只放对单个设备的读写，不存任何状态。
enum AudioController {

    // MARK: 设备

    static func defaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// 所有带输入的设备（真实的、虚拟的都在内）。
    static func inputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInput)
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    /// 是不是真实的麦克风。
    ///
    /// 虚拟设备（飞书、Teams 装的那种，连接类型 `virt`）和聚合设备不算：它们本身不收音，
    /// 声音要么来自真实麦克风，要么是电脑自己的声音（会议里「共享电脑声音」就靠它们）。
    /// 真实麦克风都静音了，从它们取声的虚拟设备也只剩静音；反过来静音虚拟设备，
    /// 保护不了什么，还可能把共享声音弄没。读不出类型时按真实的算——宁可多静一个。
    static func isPhysical(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return true }
        return transport != kAudioDeviceTransportTypeVirtual && transport != kAudioDeviceTransportTypeAggregate
    }

    static func name(_ device: AudioDeviceID) -> String {
        stringProperty(device, kAudioObjectPropertyName) ?? L("未知麦克风")
    }

    /// 设备的稳定标识。AudioDeviceID 拔插之后可能变，通知去重要用这个。
    static func uid(_ device: AudioDeviceID) -> String {
        stringProperty(device, kAudioDevicePropertyDeviceUID) ?? "\(device)"
    }

    private static func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: 静音

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func isSettable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// 这个设备有能写的静音开关。iPhone 的连续互通麦克风就没有（音量也没有）。
    static func canMute(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        return isSettable(device, &address)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var address = muteAddress()
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: 输入音量（设备不支持静音时的退路：只能压到 0，不保证完全无声）

    /// 主声道 + 左右声道。有的设备音量挂在主声道上，有的挂在各个声道上。
    static let volumeElements: [UInt32] = [UInt32(kAudioObjectPropertyElementMain), 1, 2]

    private static func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        volumeElements.contains { element in
            var address = volumeAddress(element)
            return isSettable(device, &address)
        }
    }

    static func inputVolume(_ device: AudioDeviceID) -> Float32? {
        for element in volumeElements {
            var address = volumeAddress(element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    static func setInputVolume(_ device: AudioDeviceID, _ volume: Float32) {
        for element in volumeElements {
            var address = volumeAddress(element)
            guard isSettable(device, &address) else { continue }
            var value = volume
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    // MARK: 播放 / 暂停

    /// 发送系统多媒体键，兼容 Music/Spotify 等当前播放器。
    static func playPause() {
        MediaKey.press(MediaKey.playPause)
    }
}
