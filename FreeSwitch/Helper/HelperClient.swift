import AppKit
import ServiceManagement

/// 管理特权助手：安装/移除，以及通过 XPC 调用它执行需要 root 的 pmset。
@MainActor
final class HelperClient {
    static let shared = HelperClient()

    private var service: SMAppService {
        SMAppService.daemon(plistName: HelperInfo.daemonPlistName)
    }

    var status: SMAppService.Status { service.status }
    var isInstalled: Bool { service.status == .enabled }

    // MARK: 安装（带弹窗前说明）
    /// 先用一段说明安抚用户，再触发系统的批准流程。返回是否已进入“已启用”。
    @discardableResult
    func installWithExplanation() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("开启“免密”需要装一个小助手（一次性）")
        alert.informativeText = L("""
        「合盖也不休眠 / 低电量模式」要改系统电源设置，默认每次都得输密码。装上这个小助手后就再也不用输了。

        点“继续”后会发生什么：
        1) macOS 弹出授权框，输入一次你的登录密码；
        2) 系统会打开『登录项与扩展』设置页；
        3) 在那页的「后台 App 活动」里，把 FreeSwitch 的开关打开（变蓝）。

        全程只需一次，之后就不再打扰你。随时可在 FreeSwitch 设置里“移除助手”。
        """)
        alert.addButton(withTitle: L("继续"))
        alert.addButton(withTitle: L("取消"))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try service.register()
        } catch {
            NSLog("[FreeSwitch] helper register error: \(error.localizedDescription)")
        }

        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            let note = NSAlert()
            note.messageText = L("最后一步：把 FreeSwitch 的开关打开")
            note.informativeText = L("""
            已帮你打开『系统设置 › 通用 › 登录项与扩展』。

            1) 往下滚到「后台 App 活动」这一区；
            2) 找到列表里的 FreeSwitch；
            3) 把它右边的开关打开（变蓝）。

            这样助手就生效了——之后切「合盖也不休眠 / 低电量模式」就不用再输密码。
            （如果列表里找不到 FreeSwitch：把 FreeSwitch.app 拖进「应用程序」再试一次。）
            """)
            note.addButton(withTitle: L("我知道了"))
            note.runModal()
        }
        return isInstalled
    }

    func uninstall() {
        do { try service.unregister() } catch {
            NSLog("[FreeSwitch] helper unregister error: \(error.localizedDescription)")
        }
    }

    // MARK: 「登记在册，却起不来」

    private var explainedBroken = false

    /// 助手调用失败时解释一次，并给一条修好的路。
    ///
    /// `status == .enabled` 只说明**登记在册**，不说明**起得来**。
    /// launchd 给这条服务记了一份轻量代码要求（LWCR）和宿主 App 的位置；
    /// App 换一次签名（Apple Development → Developer ID）或者删掉重装，
    /// 这份记录就和新的二进制对不上，spawn 以 EX_CONFIG 失败，而 `status` 照旧报 `.enabled`。
    /// 实测过的一台机器上 `launchctl print system/…helper` 写着：
    ///   properties = … needs LWCR update | has LWCR
    ///   last exit code = 78: EX_CONFIG   job state = spawn failed   runs = 770
    /// 从 App 这边看一切正常，用户看到的却是「开关点了没反应」。
    ///
    /// 现在失败会自动退回输密码那条路（见 `SystemController.runPrivileged`），功能不丢；
    /// 但「怎么突然又要密码了」得说清楚。修的办法只有重新登记一遍，
    /// 而 `register()` 对已登记的服务会抛 `kSMErrorAlreadyRegistered`，所以必须先 unregister——
    /// 这意味着要再批准一次，代价不小，所以绝不自作主张，必须用户点头。
    func explainBrokenHelperOnce() {
        guard !explainedBroken, isInstalled else { return }
        explainedBroken = true

        let alert = NSAlert()
        alert.messageText = L("免密助手失效了，这次用密码完成的")
        alert.informativeText = L("""
        系统里还登记着 FreeSwitch 的免密助手，但它已经启动不起来了——通常是因为 App 换了一个版本（重新签名，或者删掉重装），系统为它记下的那份代码要求对不上新的程序了。

        刚才那次改动已经通过输密码完成，功能没有受影响。

        想恢复免密，需要把助手重装一遍：先注销旧的登记，再走一次和第一次安装相同的批准流程。
        """)
        alert.addButton(withTitle: L("重新安装助手…"))
        alert.addButton(withTitle: L("以后再说"))

        // 弹窗结束后把激活策略放回原样。菜单栏 App 平时是 accessory，
        // 变成 regular 就会多出一个程序坞图标，不还回去它会一直挂着。
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let choice = alert.runModal()
        NSApp.setActivationPolicy(policy)

        guard choice == .alertFirstButtonReturn else { return }
        uninstall()
        _ = installWithExplanation()
        NSApp.setActivationPolicy(policy)
    }

    // MARK: XPC 调用
    private func withProxy(_ body: @escaping (HelperProtocol, @escaping (Bool) -> Void) -> Void,
                           completion: @escaping (Bool) -> Void) {
        let connection = NSXPCConnection(machServiceName: HelperInfo.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            DispatchQueue.main.async { completion(false); connection.invalidate() }
        }
        guard let helper = proxy as? HelperProtocol else {
            completion(false); connection.invalidate(); return
        }
        body(helper) { ok in
            DispatchQueue.main.async { completion(ok); connection.invalidate() }
        }
    }

    func setDisableSleep(_ disabled: Bool, completion: @escaping (Bool) -> Void) {
        withProxy({ helper, reply in helper.setDisableSleep(disabled, reply: reply) }, completion: completion)
    }

    func setLowPowerMode(_ on: Bool, completion: @escaping (Bool) -> Void) {
        withProxy({ helper, reply in helper.setLowPowerMode(on, reply: reply) }, completion: completion)
    }
}
