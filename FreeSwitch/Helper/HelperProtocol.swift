import Foundation

/// 主 App 与特权助手之间的 XPC 接口。两边编译同一份定义。
@objc public protocol HelperProtocol {
    /// 禁用/恢复“合盖即休眠”（pmset -a disablesleep）。
    func setDisableSleep(_ disabled: Bool, reply: @escaping (Bool) -> Void)
    /// 切换低电量模式（pmset -a lowpowermode）。
    func setLowPowerMode(_ on: Bool, reply: @escaping (Bool) -> Void)
    /// 连通性 / 版本探测。
    func ping(reply: @escaping (String) -> Void)
}

/// 共享常量。
public enum HelperInfo {
    public static let machServiceName = "com.freeswitch.FreeSwitch.helper"
    public static let daemonPlistName = "com.freeswitch.FreeSwitch.helper.plist"
    public static let version = "1"
}
