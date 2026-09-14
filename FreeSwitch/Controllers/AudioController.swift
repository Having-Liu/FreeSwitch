import AppKit
import CoreAudio

/// 声音相关：麦克风静音、播放/暂停、耳机连接。
enum AudioController {

    private static func defaultInputDevice() -> AudioDeviceID? {
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
        return status == noErr ? deviceID : nil
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func setMicMuted(_ muted: Bool) {
        guard let device = defaultInputDevice() else { return }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func micMuted() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value != 0
    }

    /// 把系统默认输出切到名字匹配的设备（连接耳机后自动切声音）。返回是否成功。
    @discardableResult
    static func setDefaultOutput(named target: String) -> Bool {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &dataSize) == noErr else { return false }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &dataSize, &devices) == noErr else { return false }

        for device in devices where deviceHasOutput(device) {
            guard let name = deviceName(device) else { continue }
            if name == target || name.contains(target) || target.contains(name) {
                var defaultAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var target = device
                let status = AudioObjectSetPropertyData(
                    system, &defaultAddress, 0, nil,
                    UInt32(MemoryLayout<AudioDeviceID>.size), &target
                )
                return status == noErr
            }
        }
        return false
    }

    private static func deviceHasOutput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return size > 0
    }

    private static func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (name as String) : nil
    }

    /// 播放/暂停：发送系统多媒体键，兼容 Music/Spotify 等当前播放器。
    static func playPause() {
        MediaKey.press(MediaKey.playPause)
    }

    /// 耳机连接：v1 打开蓝牙设置（连接指定 AirPods 需 IOBluetooth，后续版本增强）。
    static func connectHeadphones() {
        Shell.run("/usr/bin/open", ["x-apple.systempreferences:com.apple.BluetoothSettings"])
    }
}
