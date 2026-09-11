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

    /// 播放/暂停：发送系统多媒体键，兼容 Music/Spotify 等当前播放器。
    static func playPause() {
        MediaKey.press(MediaKey.playPause)
    }

    /// 耳机连接：v1 打开蓝牙设置（连接指定 AirPods 需 IOBluetooth，后续版本增强）。
    static func connectHeadphones() {
        Shell.run("/usr/bin/open", ["x-apple.systempreferences:com.apple.BluetoothSettings"])
    }
}
