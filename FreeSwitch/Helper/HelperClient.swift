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
        alert.messageText = "启用免密授权（一次性）"
        alert.informativeText = """
        为了让「合盖也不休眠 / 低电量模式」这类需要系统权限的开关不用每次都输密码，\
        FreeSwitch 想安装一个很小的系统助手。

        点“继续”后，macOS 会请你允许它——可能是在『系统设置 › 通用 › 登录项与扩展』里\
        打开 FreeSwitch 的开关，或输入一次你的登录密码。这是**一次性**的，之后就不再打扰你。

        你随时可以在 FreeSwitch 设置里“移除助手”把它卸载。
        """
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
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
            note.messageText = "还差一步：在系统设置里允许"
            note.informativeText = "已为你打开『登录项与扩展』。请把 FreeSwitch 对应的开关打开，助手即生效。"
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
