import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = Preferences.shared.launchAtLogin
    @State private var pairedDevices: [BluetoothController.Device] = []
    @State private var dndConfigured = false
    @State private var helperInstalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            List {
                Section("开关（拖动排序，可以拖进其他分组；分组名点一下就能改）") {
                    // 分组标题和开关摊平在同一个 ForEach 里：.onMove 只能在一个 ForEach 内挪动，
                    // 分成多个 Section 就拖不过去了。开关拖过哪个分组标题，就落进哪个分组。
                    ForEach(prefs.groupRows) { entry in
                        switch entry {
                        case .group(let id):
                            if let group = prefs.groups.first(where: { $0.id == id }) {
                                groupHeader(group)
                                    .moveDisabled(true)
                            }
                        case .item(let id):
                            if let item = SwitchCatalog.item(id) {
                                row(for: item)
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        prefs.moveRows(fromOffsets: offsets, toOffset: destination)
                    }
                }

                Section("耳机连接（选择“耳机连接”开关要一键连/断的设备）") {
                    Picker("目标设备", selection: Binding(
                        get: { prefs.headphoneAddress ?? "" },
                        set: { prefs.headphoneAddress = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("未选择（点开关将打开蓝牙设置）").tag("")
                        ForEach(pairedDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                        // 保证已保存但未在列表里的设备也能显示为已选。
                        if let saved = prefs.headphoneAddress,
                           !pairedDevices.contains(where: { $0.id == saved }) {
                            Text(saved).tag(saved)
                        }
                    }
                    Button("加载已配对的蓝牙设备（需授权）") {
                        pairedDevices = BluetoothController.pairedDevices()
                    }
                }

                Section("勿扰 / 专注（需一次性设置）") {
                    Text("macOS 不允许第三方 App 直接切换「专注」。请在「快捷指令」新建一个名为 “FreeSwitch DND” 的快捷指令，加入动作「设定专注 → 勿扰 → 切换」。之后点面板里的「勿扰 / 专注」即可一键切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("打开快捷指令 App") { FocusController.openShortcutsApp() }
                        Button("重新检测") { dndConfigured = FocusController.isConfigured() }
                        Spacer()
                        if dndConfigured {
                            Label("已就绪", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("未检测到快捷指令", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                    }
                }

                Section("免密授权（可选）") {
                    Text("切换「合盖也不休眠 / 低电量模式」默认要输一次管理员密码。安装一个很小的系统助手后即可免密——一次性授权，随时可移除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if helperInstalled {
                            Label("助手已安装（免密）", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("移除助手") {
                                HelperClient.shared.uninstall()
                                helperInstalled = HelperClient.shared.isInstalled
                            }
                        } else {
                            Button("安装免密助手…") {
                                _ = HelperClient.shared.installWithExplanation()
                                helperInstalled = HelperClient.shared.isInstalled
                            }
                            Spacer()
                            Label("未安装（用密码）", systemImage: "lock").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("彻底卸载") {
                    Text("直接把 App 拖进废纸篓是清不干净的：控制中心的控件登记、特权助手、登录项、以及「合盖也不休眠」改过的电源设置都会留在系统里。用下面这个按钮可以一次清完并还原。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("彻底卸载 FreeSwitch…", role: .destructive) {
                            UninstallController.confirmAndUninstall()
                        }
                        Spacer()
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            footer
        }
        .frame(width: 480, height: 600)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            dndConfigured = FocusController.isConfigured()
            helperInstalled = HelperClient.shared.isInstalled
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// 分组标题行：名字直接点开就能改，右侧上下箭头调整分组的先后。标题本身不可拖动。
    private func groupHeader(_ group: SwitchGroup) -> some View {
        let index = prefs.groups.firstIndex(where: { $0.id == group.id }) ?? 0
        return HStack(spacing: 6) {
            TextField("分组名称", text: Binding(
                get: { group.name },
                set: { prefs.renameGroup(group.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .help("点一下就能改名；清空则显示默认名")
            Spacer()
            Button { prefs.moveGroup(group.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("分组上移")
            Button { prefs.moveGroup(group.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(index == prefs.groups.count - 1)
                .help("分组下移")
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func row(for item: SwitchItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            // 和面板用同一个图标组件，两处的图形、颜色、角标保持一致。
            SwitchIcon(item: item, isOn: false, size: 14)
                .frame(width: 22)
            Text(item.title)
                .frame(width: 120, alignment: .leading)

            Spacer()

            if item.kind != .picker {
                HotkeyRecorderView(id: item.id, prefs: prefs)
            }

            Toggle("", isOn: Binding(
                get: { prefs.isVisible(item.id) },
                set: { prefs.setVisible(item.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "switch.2")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("FreeSwitch 设置").font(.headline)
                Text("自定义菜单栏面板与全局快捷键").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Toggle("开机自动启动", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    prefs.launchAtLogin = newValue
                    launchAtLogin = prefs.launchAtLogin
                }
            ))
            .toggleStyle(.checkbox)

            Spacer()

            Button("全部显示") {
                for id in SwitchCatalog.defaultIDs { prefs.setVisible(id, true) }
            }
            Button("恢复默认分组") {
                prefs.resetGroups()
            }
        }
        .padding(16)
    }
}

/// 快捷键录制控件：点击后按下组合键即记录。
struct HotkeyRecorderView: View {
    let id: String
    @ObservedObject var prefs: Preferences
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .font(.system(.caption, design: .rounded))
                .frame(minWidth: 84)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("点击后按下快捷键；Esc 取消，Delete 清除")
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "按下…" }
        return prefs.hotkeys[id]?.display ?? "未设置"
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            if event.keyCode == UInt16(kVK_Delete) { prefs.setHotkey(nil, for: id); stop(); return nil }
            if let hotkey = Hotkey(event: event) { prefs.setHotkey(hotkey, for: id); stop(); return nil }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
