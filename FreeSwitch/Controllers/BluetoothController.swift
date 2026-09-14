import IOBluetooth

/// 耳机/AirPods 直连：用 IOBluetooth 连接/断开已配对设备。
/// 首次访问会触发系统蓝牙授权（需 Info.plist 的 NSBluetoothAlwaysUsageDescription）。
enum BluetoothController {
    struct Device: Identifiable, Hashable {
        let id: String   // addressString
        let name: String
    }

    private static let audioMajorClass: BluetoothDeviceClassMajor = 0x04 // kBluetoothDeviceClassMajorAudio

    static func pairedDevices() -> [Device] {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return list.compactMap { device in
            guard let address = device.addressString else { return nil }
            return Device(id: address, name: device.name ?? address)
        }
    }

    /// 自动挑一个最合适的音频设备（AirPods/耳机）：优先当前已连接的，否则第一个已配对音频设备。
    /// 让「耳机连接」无需预先在设置里选设备也能一键工作。
    static func bestAudioDevice() -> Device? {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let audio = list.filter { $0.deviceClassMajor == audioMajorClass }
        let pick = audio.first(where: { $0.isConnected() }) ?? audio.first
        guard let device = pick, let address = device.addressString else { return nil }
        return Device(id: address, name: device.name ?? address)
    }

    static func isConnected(_ address: String) -> Bool {
        IOBluetoothDevice(addressString: address)?.isConnected() ?? false
    }

    /// 连接/断开设备。openConnection 是同步阻塞调用（设备在盒里时会等到超时），
    /// 因此标记 nonisolated，交给后台线程执行，避免卡住菜单。
    nonisolated static func setConnected(_ address: String, _ connected: Bool) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        if connected {
            if !device.isConnected() { device.openConnection() }
        } else {
            if device.isConnected() { device.closeConnection() }
        }
    }

    static func name(for address: String) -> String? {
        IOBluetoothDevice(addressString: address)?.name
    }

    /// 通过 system_profiler 读取已连接蓝牙设备的电量（较慢，请在后台调用）。
    /// AirPods 取左右耳中较低者；其它设备取主电量。
    nonisolated static func batteryPercent(for address: String) -> Int? {
        let output = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]).output
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        let target = normalize(address)
        for block in blocks {
            guard let connected = block["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (_, value) in entry {
                    guard let info = value as? [String: Any],
                          let deviceAddress = info["device_address"] as? String,
                          normalize(deviceAddress) == target else { continue }
                    let left = percent(info["device_batteryLevelLeft"])
                    let right = percent(info["device_batteryLevelRight"])
                    let main = percent(info["device_batteryLevelMain"])
                    if let left, let right { return min(left, right) }
                    return main ?? left ?? right
                }
            }
        }
        return nil
    }

    nonisolated private static func normalize(_ string: String) -> String {
        string.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    nonisolated private static func percent(_ value: Any?) -> Int? {
        guard let string = value as? String else { return nil }
        return Int(string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }
}
