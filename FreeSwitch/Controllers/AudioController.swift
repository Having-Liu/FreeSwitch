import AppKit
import CoreAudio

/// 声音相关：麦克风静音、播放 / 暂停。
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

    private static var savedInputVolume: Float32?

    static func setMicMuted(_ muted: Bool) {
        guard let device = defaultInputDevice() else { return }
        var address = muteAddress()
        if AudioObjectHasProperty(device, &address) {
            var value: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            return
        }
        // 回退：设备不支持 mute（如 AirPods 麦克风）时，把输入音量设为 0。
        if muted {
            savedInputVolume = inputVolume(device) ?? 1.0
            setInputVolume(device, 0)
        } else {
            setInputVolume(device, savedInputVolume ?? 1.0)
        }
    }

    static func micMuted() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        var address = muteAddress()
        if AudioObjectHasProperty(device, &address) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return value != 0
        }
        if let volume = inputVolume(device) { return volume < 0.01 }
        return false
    }

    private static func volumeElements() -> [UInt32] {
        [UInt32(kAudioObjectPropertyElementMain), 1, 2] // 主 + 左右声道
    }

    private static func inputVolume(_ device: AudioDeviceID) -> Float32? {
        for element in volumeElements() {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address) {
                var value: Float32 = 0
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                    return value
                }
            }
        }
        return nil
    }

    private static func setInputVolume(_ device: AudioDeviceID, _ volume: Float32) {
        for element in volumeElements() {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = volume
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
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

    // MARK: 监听外部改动
    // 麦克风静音不只有我们会改：会议 App、键盘上的硬件静音键都会改，
    // 而切换默认输入设备（连上 AirPods）更是直接换了一个“静音状态”。
    // 不监听的话，控制中心里显示的就一直是我们上次自己操作时的旧值。

    private static var micHandler: (@MainActor () -> Void)?
    private static var listenedDevice: AudioDeviceID?

    /// 注册回调：麦克风静音状态被任何一方改变时触发（含默认输入设备本身被换掉）。
    static func observeMicChanges(_ handler: @escaping @MainActor () -> Void) {
        micHandler = handler
        attachMicListener()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { _, _ in
            MainActor.assumeIsolated {
                attachMicListener()   // 换设备了，监听要跟着挪过去
                micHandler?()
            }
        }
    }

    private static func attachMicListener() {
        guard let device = defaultInputDevice(), listenedDevice != device else { return }
        listenedDevice = device
        // mute 和 volume 都要听：不支持 mute 的设备（如 AirPods）走的是音量置 0 那条回退路径。
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main) { _, _ in
                MainActor.assumeIsolated { micHandler?() }
            }
        }
        // 旧设备上的监听不特意摘除：回调只是让上层重读“当前默认设备”的状态，
        // 多触发一次无害，而设备真被拔掉时监听本就随之消失。
    }

    /// 播放/暂停：发送系统多媒体键，兼容 Music/Spotify 等当前播放器。
    static func playPause() {
        MediaKey.press(MediaKey.playPause)
    }

}
