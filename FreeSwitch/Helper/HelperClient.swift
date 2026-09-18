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
