import AppKit
import OSLog
import UserNotifications

/// 本地通知。目前只有「麦克风静音」在用。
///
/// 授权同样是**用到了才请求**：用户第一次打开麦克风静音时才问（见 `MicGuard.start`），
/// 不在启动时、也不在引导页里自动弹。没给授权就不发——功能照常工作，只是不再告诉你。
@MainActor
enum Notifier {

    enum Level {
        /// 例行的「已经替你处理好了」：不响铃。
        case info
        /// 隐私没保住：静不了音、放弃抢回了。响铃。
        case warning
    }

    /// 同一类事件、同一个设备，这么久之内只报一次。
    /// 某个 App 反复解除静音时，不能每抢回一次就弹一条。
    private static let throttle: TimeInterval = 10
    private static var lastPosted: [String: Date] = [:]

    private static let log = Logger(subsystem: "com.freeswitch.FreeSwitch", category: "notify")

    /// 发一条通知。`key` 同时是通知的 identifier：同一个 key 的新通知会顶掉旧的，不会堆一串。
    static func post(key: String, title: String, body: String, level: Level = .info) {
        let now = Date()
        if let last = lastPosted[key], now.timeIntervalSince(last) < throttle {
            log.debug("throttled \(key, privacy: .public)")
            return
        }
        lastPosted[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "mic"          // 通知中心里归成一叠
        if level == .warning { content.sound = .default }
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)

        installPresenter()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch status {
                    case .authorized, .provisional, .ephemeral:
                        add(request)
                    case .notDetermined:
                        enqueue(request)
                        ask()
                    default:
                        // 授权提示可能还挂着：刚发出请求、用户还没点，这时系统报的就是「未授权」
                        // （实测：开关一打开就先请求授权，紧跟着的那条汇总通知就这样被丢了）。
                        // 那就先排着等回答；没有在等回答、确实被拒了，才丢。
                        if asking { enqueue(request) }
                        else { log.debug("not authorized (status \(status.rawValue)), dropped \(key, privacy: .public)") }
                    }
                }
            }
        }
    }

    /// 还没问过就问一次。用户打开「麦克风静音」时调用：那一刻用户知道这个功能要发通知。
    static func requestAuthorizationIfNeeded() {
        installPresenter()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { ask() } }
        }
    }

    // MARK: 等授权期间排队

    /// 授权提示还等着用户回答时发的通知。按 identifier 存，同一件事只留最新一条，不会无限变长。
    private static var queued: [String: (request: UNNotificationRequest, at: Date)] = [:]
    private static var asking = false
    /// 用户隔了很久才去点授权时，太旧的就别补发了——那时候已经不是那回事了。
    private static let queueTTL: TimeInterval = 600

    private static func enqueue(_ request: UNNotificationRequest) {
        queued[request.identifier] = (request, Date())
        log.debug("queued \(request.identifier, privacy: .public) while waiting for authorization")
    }

    private static func ask() {
        guard !asking else { return }
        asking = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    asking = false
                    let now = Date()
                    let pending = queued.values.filter { now.timeIntervalSince($0.at) < queueTTL }.map(\.request)
                    queued.removeAll()
                    log.debug("authorization answered: granted=\(granted), flushing \(pending.count)")
                    if granted { pending.forEach(add) }
                }
            }
        }
    }

    private static func add(_ request: UNNotificationRequest) {
        let key = request.identifier
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log.error("post \(key, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
            else { log.debug("posted \(key, privacy: .public)") }
        }
    }

    /// 权限页用：只读，不弹窗。
    static func authorization(_ completion: @escaping @MainActor (Permission.State) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: Permission.State
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: state = .granted
            case .denied:                               state = .denied
            default:                                    state = .notDetermined
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(state) } }
        }
    }

    /// 权限页的「请求授权」。
    static func requestAuthorization(_ completion: @escaping @MainActor (Permission.State) -> Void) {
        installPresenter()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(granted ? .granted : .denied) } }
        }
    }

    static func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.freeswitch.FreeSwitch"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 前台也要弹

    /// 菜单栏面板开着的时候，本 App 算「当前 App」，系统默认不弹横幅——
    /// 可用户恰恰是在面板里打开开关的那一刻最该看到「有个麦克风静不了」。
    private static var presenter: Presenter?

    private static func installPresenter() {
        guard presenter == nil else { return }
        let p = Presenter()
        presenter = p
        UNUserNotificationCenter.current().delegate = p
    }

    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                                willPresent notification: UNNotification,
                                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }
    }
}
