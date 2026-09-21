import CoreAudio
import Foundation
import OSLog

/// 「麦克风静音」的守护模式。
///
/// 早先的实现只把**默认**输入设备静音一下就完事，有几个洞（读代码、到真机上逐个设备核对过）：
///  - 会议 App 在自己设置里指定了别的麦克风，照样收音；
///  - 静音之后接上 AirPods / USB 耳机，新设备是开着的；
///  - 谁都能解除静音——改这个属性不需要任何权限，FreeSwitch 自己就没有麦克风权限；
///  - 有的设备既不支持静音也不支持调音量（iPhone 的连续互通麦克风就是），点了没反应，也不说。
///
/// 现在开关打开后进入守护：
///  1. 把所有**真实**麦克风静音（虚拟、聚合设备不碰，理由见 `AudioController.isPhysical`）；
///  2. 守护期间有新麦克风接入、默认麦克风变了，自动把它也静音；
///  3. 守护期间有人解除了静音，立刻静音回去。同一个设备 10 秒内被解除超过 5 次就不再抢：
///     那说明有 App 在持续控制它，继续抢只会来回打架，告诉用户比打架有用；
///  4. 上面每件事都发通知：自动静音了哪个、恢复了哪个、哪个静不了、哪个放弃抢了。
///
/// 全部靠 CoreAudio 的属性监听，**不轮询**：没有插拔、没人改的时候一行代码都不跑。
/// 一次回调要做的事（列出全部设备、读一遍静音状态）实测平均 0.3 毫秒。
///
/// 守护状态存在偏好里：App 重启（更新、重新登录）后接着守——
/// 用户说的是「把麦克风关掉」，不是「在这个进程活着的时候关掉」。
@MainActor
final class MicGuard {
    static let shared = MicGuard()

    /// 守护状态或设备状态变了。SwitchStore 借它刷新开关。
    var onChange: (() -> Void)?

    /// 开关的「开」就是它：FreeSwitch 正守着所有真实麦克风。
    ///
    /// 不再跟着「默认麦克风此刻是不是静音」走。那样别处静的音也会让开关亮起来，
    /// 可开关亮着的意思是「新接入的会被静音、被解除的会被抢回」——这些保证只有守护着才成立。
    /// 隐私开关宁可少亮，不能谎报。
    private(set) var isGuarding = false

    private static let prefKey = "pref.micGuard"
    private static let log = Logger(subsystem: "com.freeswitch.FreeSwitch", category: "mic")

    /// 守护开始时每个设备原来的样子，以及是怎么静住它的——关掉时按这个原样还回去。
    private enum Hold {
        case mute(wasMuted: Bool)
        case volume(saved: Float32)
        case unsupported
    }
    private enum Outcome { case muted, volumeOnly, unsupported, failed }

    private var holds: [AudioDeviceID: Hold] = [:]
    /// 每个设备最近被抢回的时刻，用来判断是不是有 App 在跟我们来回拉扯。
    private var reasserts: [AudioDeviceID: [Date]] = [:]
    private var givenUp: Set<AudioDeviceID> = []
    private var listening: Set<AudioDeviceID> = []

    private static let contestWindow: TimeInterval = 10
    private static let contestLimit = 5

    // MARK: 生命周期

    /// 挂上监听；上次退出时还在守护就接着守。App 启动时调一次。
    func startObserving() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let isDefault = selector == kAudioHardwarePropertyDefaultInputDevice
            AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.devicesChanged(defaultChanged: isDefault) }
            }
        }
        for device in AudioController.inputDevices() { listen(to: device) }
        if UserDefaults.standard.bool(forKey: Self.prefKey) { start(resuming: true) }
    }

    /// 打开开关。`resuming` 为真表示 App 重启后接着守，这时不重复报「哪些没静住」。
    func start(resuming: Bool = false) {
        isGuarding = true
        UserDefaults.standard.set(true, forKey: Self.prefKey)
        holds.removeAll(); reasserts.removeAll(); givenUp.removeAll()
        if !resuming { Notifier.requestAuthorizationIfNeeded() }

        var problems: [String] = []
        var mutedCount = 0
        for device in AudioController.inputDevices() where AudioController.isPhysical(device) {
            listen(to: device)
            let name = AudioController.name(device)
            switch take(device) {
            case .muted:       mutedCount += 1
            case .volumeOnly:  problems.append(L("「%@」只能调低音量，不保证完全无声", name))
            case .unsupported: problems.append(L("「%@」不支持静音", name))
            case .failed:      problems.append(L("「%@」静音失败", name))
            }
        }
        Self.log.debug("guard on: muted=\(mutedCount) problems=\(problems.count) resuming=\(resuming)")

        // 汇总成一条，别一个设备弹一条。全都静住了就不打扰——开关亮起来就是反馈。
        // 从重启里接着守的那一次也不报：用户打开开关的那一刻已经被告知过了。
        if !problems.isEmpty && !resuming {
            var lines = problems
            if mutedCount > 0 { lines.append(L("其余麦克风都已静音。")) }
            Notifier.post(key: "mic.start",
                          title: mutedCount > 0 ? L("有些麦克风没能完全静音") : L("麦克风没能静音"),
                          body: lines.joined(separator: "\n"),
                          level: .warning)
        }
        onChange?()
    }

    /// 关掉开关。
    func stop() {
        // 先放下守护：下面自己解除静音也会触发回调，守护还开着的话会被自己抢回去。
        isGuarding = false
        UserDefaults.standard.set(false, forKey: Self.prefKey)
        for (device, hold) in holds {
            switch hold {
            case .mute(let wasMuted) where !wasMuted: AudioController.setMuted(device, false)
            case .volume(let saved):                  AudioController.setInputVolume(device, saved)
            default:                                  break
            }
        }
        // 关掉开关的意思是「我要用麦克风了」：默认麦克风哪怕在守护之前就是静音的，也把它打开。
        if let device = AudioController.defaultInputDevice(), AudioController.isMuted(device) {
            AudioController.setMuted(device, false)
        }
        holds.removeAll(); reasserts.removeAll(); givenUp.removeAll()
        Self.log.debug("guard off")
        onChange?()
    }

    // MARK: 静住一个设备

    private func take(_ device: AudioDeviceID) -> Outcome {
        if AudioController.canMute(device) {
            if holds[device] == nil { holds[device] = .mute(wasMuted: AudioController.isMuted(device)) }
            AudioController.setMuted(device, true)
            // 写成功不算数，读回来是静音才算。
            return AudioController.isMuted(device) ? .muted : .failed
        }
        if AudioController.canSetVolume(device) {
            if holds[device] == nil { holds[device] = .volume(saved: AudioController.inputVolume(device) ?? 1) }
            AudioController.setInputVolume(device, 0)
            return (AudioController.inputVolume(device) ?? 1) < 0.01 ? .volumeOnly : .failed
        }
        holds[device] = .unsupported
        return .unsupported
    }

    // MARK: 监听回调

    /// 插拔了设备，或者默认麦克风换了。
    private func devicesChanged(defaultChanged: Bool) {
        let present = Set(AudioController.inputDevices())
        // 拔掉的设备不再记着：它的 id 以后可能被别的设备重用，得重新挂监听、重新静音。
        holds = holds.filter { present.contains($0.key) }
        givenUp.formIntersection(present)
        listening.formIntersection(present)
        for device in present { listen(to: device) }
        guard isGuarding else { onChange?(); return }

        var justTaken: Set<AudioDeviceID> = []
        for device in present where holds[device] == nil && AudioController.isPhysical(device) {
            justTaken.insert(device)
            let name = AudioController.name(device)
            let key = "mic.new.\(AudioController.uid(device))"
            switch take(device) {
            case .muted:
                Notifier.post(key: key, title: L("麦克风已自动静音"), body: L("新接入的「%@」已被静音。", name))
            case .volumeOnly:
                Notifier.post(key: key, title: L("麦克风只能调低音量"),
                              body: L("「%@」不支持静音，已把输入音量降到 0，但不保证完全无声。", name), level: .warning)
            case .unsupported:
                Notifier.post(key: key, title: L("有一个麦克风无法静音"),
                              body: L("「%@」不支持静音，用它的 App 仍然能收到声音。", name), level: .warning)
            case .failed:
                Notifier.post(key: key, title: L("静音失败"),
                              body: L("没能把「%@」静音，用它的 App 仍然能收到声音。", name), level: .warning)
            }
        }
        Self.log.debug("devices changed: new=\(justTaken.count) defaultChanged=\(defaultChanged)")

        // 默认麦克风换成了一个静不住的：这比「有个设备静不住」要紧——大多数 App 用的就是默认那个。
        // 刚接入、上面已经报过一次的就不再重复。
        if defaultChanged, let device = AudioController.defaultInputDevice(),
           !justTaken.contains(device), case .unsupported? = holds[device] {
            Notifier.post(key: "mic.default.\(AudioController.uid(device))", title: L("默认麦克风无法静音"),
                          body: L("默认麦克风换成了「%@」，它不支持静音，而大多数 App 用的就是默认麦克风。",
                                  AudioController.name(device)),
                          level: .warning)
        }
        onChange?()
    }

    /// 某个设备的静音或音量被改了（也可能是我们自己改的那一下）。
    private func deviceStateChanged(_ device: AudioDeviceID) {
        defer { onChange?() }
        guard isGuarding, let hold = holds[device], !givenUp.contains(device) else { return }
        switch hold {
        case .mute:
            guard !AudioController.isMuted(device) else { return }     // 还是静音的：是我们自己写的那一下
            reassert(device) { AudioController.setMuted(device, true); return AudioController.isMuted(device) }
        case .volume:
            guard (AudioController.inputVolume(device) ?? 0) >= 0.01 else { return }
            reassert(device) { AudioController.setInputVolume(device, 0); return (AudioController.inputVolume(device) ?? 1) < 0.01 }
        case .unsupported:
            return
        }
    }

    /// 抢回来。短时间里被反复解除就放弃，并且明说。
    private func reassert(_ device: AudioDeviceID, _ action: () -> Bool) {
        let now = Date()
        var times = (reasserts[device] ?? []).filter { now.timeIntervalSince($0) < Self.contestWindow }
        times.append(now)
        reasserts[device] = times
        let name = AudioController.name(device), uid = AudioController.uid(device)

        if times.count > Self.contestLimit {
            givenUp.insert(device)
            Self.log.debug("gave up on \(uid, privacy: .public)")
            Notifier.post(key: "mic.contested.\(uid)", title: L("麦克风一直被解除静音"),
                          body: L("「%@」在 10 秒内被反复解除静音，可能有 App 在控制它。FreeSwitch 已停止抢回，请检查正在用麦克风的 App。", name),
                          level: .warning)
            return
        }
        if action() {
            Self.log.debug("reasserted \(uid, privacy: .public) (\(times.count) in window)")
            Notifier.post(key: "mic.restored.\(uid)", title: L("已重新静音"),
                          body: L("「%@」被解除了静音，FreeSwitch 已把它恢复成静音。", name))
        } else {
            Notifier.post(key: "mic.failed.\(uid)", title: L("静音失败"),
                          body: L("没能把「%@」静音，用它的 App 仍然能收到声音。", name), level: .warning)
        }
    }

    private func listen(to device: AudioDeviceID) {
        guard listening.insert(device).inserted else { return }
        var targets: [(AudioObjectPropertySelector, UInt32)] = [(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)]
        for element in AudioController.volumeElements { targets.append((kAudioDevicePropertyVolumeScalar, element)) }
        for (selector, element) in targets {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.deviceStateChanged(device) }
            }
        }
    }
}
