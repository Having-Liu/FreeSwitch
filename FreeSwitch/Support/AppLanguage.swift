import AppKit

/// 界面语言。
///
/// **为什么切换语言要重启，而不是当场刷新。**
/// 这个 App 的文案有两条取词路径：SwiftUI 的 `Text("中文字面量")` 走 `LocalizedStringKey`，
/// 由系统在 `Bundle.main` 里查；`L()` 走 `String(localized:)`，同样落在 `Bundle.main`。
/// 想当场换语言，只能改成从某个 `.lproj` 子 bundle 取词——但那对第一条路径无效，
/// 结果会是「一半跟着切、一半不动」，比不支持还糟。
/// 所以老老实实走系统那套：把选择写进本 App 域的 `AppleLanguages`，然后重启进程。
enum AppLanguage {

    /// 语言名一律用它自己的语言写——让看不懂当前界面语言的人也能找到自己那一行。
    static let all: [(code: String, name: String)] = [
        ("",        L("跟随系统")),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en",      "English"),
        ("ja",      "日本語"),
        ("ko",      "한국어"),
        ("de",      "Deutsch"),
        ("fr",      "Français"),
        ("es",      "Español"),
        ("ru",      "Русский"),
    ]

    private static let systemKey = "AppleLanguages"
    /// 自己的键才是准绳，**不能**回头读 `AppleLanguages` 来判断当前选了什么。
    ///
    /// `UserDefaults.standard` 读 `AppleLanguages` 会从 NSGlobalDomain 穿透过来，
    /// 拿到的是系统的语言列表（实测是 `["zh-Hans-CN", "en-CN"]`），而不是本 App 的设置——
    /// 那串带地区后缀的值和我们列表里的 `zh-Hans` 对不上，选择器会显示成空白，
    /// 「跟随系统」也永远选不中。所以另存一个只属于本 App 域的键。
    private static let ownKey = "pref.language"

    /// 当前的覆盖设置。空串表示跟随系统。
    static var override: String {
        get { UserDefaults.standard.string(forKey: ownKey) ?? "" }
        set {
            let defaults = UserDefaults.standard
            if newValue.isEmpty {
                defaults.removeObject(forKey: ownKey)
                defaults.removeObject(forKey: systemKey)
            } else {
                defaults.set(newValue, forKey: ownKey)
                defaults.set([newValue], forKey: systemKey)
            }
            defaults.synchronize()
        }
    }

    /// 重启自己。
    ///
    /// 用一个先睡一秒再 `open` 的子进程来拉自己起来：子进程会被 launchd 接管，
    /// 在本进程退出后继续跑（卸载脚本用的是同一招）。直接在退出前 `openApplication`
    /// 有可能在旧实例还没退干净时被系统当成「已经在运行」而忽略。
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
