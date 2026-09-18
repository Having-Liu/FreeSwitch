import SwiftUI
import Carbon.HIToolbox

// 设置窗口的四页内容。骨架和外壳在 SettingsView.swift。

// MARK: - 开关

struct SwitchesPane: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = Preferences.shared.launchAtLogin

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: L("开关"),
                       subtitle: L("开关（拖动排序，可以拖进其他分组；分组名点一下就能改）"))

            List {
                // 分组标题和开关摊平在同一个 ForEach 里：.onMove 只能在一个 ForEach 内挪动，
                // 分成多个 Section 就拖不过去了。开关拖过哪个分组标题，就落进哪个分组。
                ForEach(prefs.groupRows) { entry in
                    switch entry {
                    case .group(let id):
                        if let group = prefs.groups.first(where: { $0.id == id }) {
                            GroupHeaderRow(prefs: prefs, group: group).moveDisabled(true)
                        }
                    case .item(let id):
                        if let item = SwitchCatalog.item(id) {
                            SwitchRow(prefs: prefs, item: item)
                        }
                    }
                }
                .onMove { offsets, destination in
                    prefs.moveRows(fromOffsets: offsets, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)   // 让卡片自己的底色透出来
            .environment(\.defaultMinListRowHeight, 30)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { prefs.launchAtLogin = $0; launchAtLogin = prefs.launchAtLogin }
                )) {
                    Text("开机自动启动").font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                Spacer()

                Button(L("全部显示")) {
                    for id in SwitchCatalog.defaultIDs { prefs.setVisible(id, true) }
                }
                Button(L("恢复默认分组")) { prefs.resetGroups() }
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
    }
}

/// 分组标题行：名字点开就能改，上下箭头调分组次序——箭头只在鼠标移上来时出现，
/// 平时 24 行里挂着 5 组箭头是纯噪音。
private struct GroupHeaderRow: View {
    @ObservedObject var prefs: Preferences
    let group: SwitchGroup
    @State private var hovering = false

    var body: some View {
        let index = prefs.groups.firstIndex(where: { $0.id == group.id }) ?? 0
        HStack(spacing: 4) {
            TextField(L("分组名称"), text: Binding(
                get: { prefs.displayName(of: group) },
                set: { prefs.renameGroup(group.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .help(L("点一下就能改名；清空则显示默认名"))

            Spacer(minLength: 0)

            if hovering {
                Button { prefs.moveGroup(group.id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .help(L("分组上移"))
                Button { prefs.moveGroup(group.id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == prefs.groups.count - 1)
                    .help(L("分组下移"))
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.top, 14)
        .padding(.bottom, 3)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

/// 一行开关。
///
/// 旧版这一行是五个等权重的元素平铺：把手、图标、名字、快捷键药丸、开关。
/// 其中「未设置」那颗灰药丸出现 24 次，成了整页视觉重量最大的东西，
/// 可它表达的是「什么都没有」——层级完全反了。
/// 现在把手和未设置的快捷键都只在悬停时露出来，静止时一行只剩图标、名字、开关。
private struct SwitchRow: View {
    @ObservedObject var prefs: Preferences
    let item: SwitchItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
                .frame(width: 11)

            // 和面板用同一个图标组件，两处的图形、颜色、角标保持一致。
            SwitchIcon(item: item, isOn: false, size: 14)
                .frame(width: 20)

            Text(item.localizedTitle)
                .font(.system(size: 12.5))

            Spacer(minLength: 8)

            // 快捷键固定占一列（右对齐），右半边才有骨架。
            // 不定宽的话名字贴最左、开关贴最右，中间几百像素全是空的，一行读起来是断的。
            Group {
                if item.kind != .picker {
                    HotkeyRecorderView(id: item.id, prefs: prefs, rowHovering: hovering)
                }
            }
            .frame(width: 104, alignment: .trailing)

            Toggle("", isOn: Binding(
                get: { prefs.isVisible(item.id) },
                set: { prefs.setVisible(item.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

// MARK: - 权限

/// 权限页。
///
/// 只**显示**状态，不在打开页面时请求任何东西——读状态的那几个 API 都不会弹窗
/// （见 Permission）。弹窗只在用户自己按下「请求授权」时出现。
struct PermissionsPane: View {
    @State private var systemEvents: Permission.State = .notDetermined
    @State private var finder: Permission.State = .notDetermined
    @State private var accessibility: Permission.State = .notDetermined
    @State private var helperInstalled = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: L("权限"), subtitle: L("用到哪项才需要哪项，没用到可以一直空着"))
            Form {
                Section {
                    PermissionRow(
                        symbol: "gearshape.2",
                        title: L("自动化 · 系统事件"),
                        detail: L("「黑暗模式」「自动隐藏程序坞」要通过系统事件来切换"),
                        state: systemEvents,
                        request: { Permission.requestAutomation(of: "com.apple.systemevents") { systemEvents = $0 } },
                        openSettings: { Permission.openSettings("Privacy_Automation") })

                    PermissionRow(
                        symbol: "folder",
                        title: L("自动化 · 访达"),
                        detail: L("「清空废纸篓」，以及「隐藏所有窗口」时折叠访达的窗口"),
                        state: finder,
                        request: { Permission.requestAutomation(of: "com.apple.finder") { finder = $0 } },
                        openSettings: { Permission.openSettings("Privacy_Automation") })

                    PermissionRow(
                        symbol: "keyboard",
                        title: L("辅助功能"),
                        detail: L("「锁定键盘」要用它来拦截键盘事件"),
                        state: accessibility,
                        request: {
                            Permission.requestAccessibility()
                            // 授权后系统会重启本 App 的辅助功能信任状态，隔一会儿再回读。
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                MainActor.assumeIsolated { accessibility = Permission.accessibility }
                            }
                        },
                        openSettings: { Permission.openSettings("Privacy_Accessibility") })
                }

                Section(L("免密授权（可选）")) {
                    Text("切换「合盖也不休眠 / 低电量模式」默认要输一次管理员密码。安装一个很小的系统助手后即可免密——一次性授权，随时可移除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if helperInstalled {
                            Button(L("移除助手")) {
                                HelperClient.shared.uninstall()
                                helperInstalled = HelperClient.shared.isInstalled
                            }
                            Spacer()
                            StatusChip(ok: true, okText: L("助手已安装（免密）"), failText: "")
                        } else {
                            Button(L("安装免密助手…")) {
                                _ = HelperClient.shared.installWithExplanation()
                                helperInstalled = HelperClient.shared.isInstalled
                            }
                            Spacer()
                            StatusChip(ok: false, okText: "", failText: L("未安装（用密码）"), neutral: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        systemEvents = Permission.automation(of: "com.apple.systemevents")
        finder = Permission.automation(of: "com.apple.finder")
        accessibility = Permission.accessibility
        helperInstalled = HelperClient.shared.isInstalled
    }
}

/// 一条权限：名字、用来干什么、当前状态，以及**只在用户点击时**才会动的那个按钮。
///
/// 「还没问过」给「请求授权」，「问过被拒」只能给「打开系统设置」——
/// 被拒之后再调请求 API 系统不会再弹，按钮留着只会让人以为坏了。
private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let state: Permission.State
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(state.isGranted ? SwitchHue.green : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            switch state {
            case .granted:
                StatusChip(ok: true, okText: L("已授权"), failText: "")
            case .notDetermined:
                Button(L("请求授权"), action: request).controlSize(.small)
            case .denied:
                Button(L("打开系统设置"), action: openSettings).controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }
}

/// 状态小药丸。旧版这里是一行光秃秃的 Label，绿的和橙的混在按钮堆里分不出主次；
/// 现在给它一个浅色底，让「状态」和「操作」在形状上就不是一类东西。
private struct StatusChip: View {
    let ok: Bool
    let okText: String
    let failText: String
    var neutral: Bool = false

    private var tint: Color { ok ? SwitchHue.green : (neutral ? .secondary : SwitchHue.amber) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : (neutral ? "lock" : "exclamationmark.circle.fill"))
                .font(.system(size: 10))
            Text(ok ? okText : failText)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
    }
}

// MARK: - 彻底卸载

struct UninstallPane: View {
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: L("彻底卸载"),
                       subtitle: L("拖进废纸篓清不干净，这里能一次清完并还原"))
            Form {
                Section {
                    Text("直接把 App 拖进废纸篓是清不干净的：控制中心的控件登记、特权助手、登录项、以及「合盖也不休眠」改过的电源设置都会留在系统里。用下面这个按钮可以一次清完并还原。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(L("彻底卸载 FreeSwitch…"), role: .destructive) {
                            UninstallController.confirmAndUninstall()
                        }
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - 快捷键录制

/// 点一下开始录，按下组合键即记录；Esc 取消，Delete 清除。
///
/// 没设过快捷键时**什么都不画**，只有鼠标移到这一行才浮出一个很淡的「设置快捷键」。
/// 旧版在每行都摆一颗写着「未设置」的灰药丸，24 颗排成一列，
/// 是整页最抢眼的东西，而它表达的是「这里没有内容」。
struct HotkeyRecorderView: View {
    let id: String
    @ObservedObject var prefs: Preferences
    var rowHovering: Bool = true

    @State private var recording = false
    @State private var monitor: Any?

    private var hotkey: Hotkey? { prefs.hotkeys[id] }

    var body: some View {
        Group {
            if recording {
                chip(L("按下…"), filled: true)
            } else if let display = hotkey?.display {
                chip(display, filled: false)
            } else if rowHovering {
                chip(L("设置快捷键"), filled: false, ghost: true)
            } else {
                Color.clear.frame(width: 1, height: 20)
            }
        }
        .animation(.easeOut(duration: 0.12), value: rowHovering)
        .onDisappear(perform: stop)
    }

    private func chip(_ text: String, filled: Bool, ghost: Bool = false) -> some View {
        Button(action: toggle) {
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(ghost ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(filled ? Color.accentColor.opacity(0.22)
                                     : Color.primary.opacity(ghost ? 0.03 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(filled ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(L("点击后按下快捷键；Esc 取消，Delete 清除"))
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
