import IOBluetooth

/// 耳机/AirPods 直连：用 IOBluetooth 连接/断开已配对设备。
/// 首次访问会触发系统蓝牙授权（需 Info.plist 的 NSBluetoothAlwaysUsageDescription）。
enum BluetoothController {
    struct Device: Identifiable, Hashable {
        let id: String   // addressString
        let name: String
    }

    static func pairedDevices() -> [Device] {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return list.compactMap { device in
            guard let address = device.addressString else { return nil }
            return Device(id: address, name: device.name ?? address)
        }
    }

    static func isConnected(_ address: String) -> Bool {
        IOBluetoothDevice(addressString: address)?.isConnected() ?? false
    }

    static func setConnected(_ address: String, _ connected: Bool) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        if connected {
            if !device.isConnected() { device.openConnection() }
        } else {
            if device.isConnected() { device.closeConnection() }
        }
    }
}
