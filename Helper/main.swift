import Foundation
import Security

// 与 App 端一致的接口（构建脚本会把 HelperProtocol.swift 一起编进来）。

/// 只接受签名满足要求（我们自己的 App、同一开发团队）的调用者，防止任意进程调用 root 助手。
private func callerIsTrusted(pid: pid_t) -> Bool {
    let requirement = """
    identifier "com.freeswitch.FreeSwitch" and anchor apple generic and \
    certificate leaf[subject.OU] = "MXHBUQH27V"
    """
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: pid] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else {
        return false
    }
    var req: SecRequirement?
    guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else {
        return false
    }
    return SecCodeCheckValidity(code, [], req) == errSecSuccess
}

@discardableResult
private func runPmset(_ args: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = args
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard callerIsTrusted(pid: newConnection.processIdentifier) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func setDisableSleep(_ disabled: Bool, reply: @escaping (Bool) -> Void) {
        reply(runPmset(["-a", "disablesleep", disabled ? "1" : "0"]))
    }

    func setLowPowerMode(_ on: Bool, reply: @escaping (Bool) -> Void) {
        reply(runPmset(["-a", "lowpowermode", on ? "1" : "0"]))
    }

    func ping(reply: @escaping (String) -> Void) {
        reply("FreeSwitchHelper \(HelperInfo.version)")
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: HelperInfo.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
