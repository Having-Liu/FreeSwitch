import SwiftUI

// 带参数的开关，点磁贴弹出的选项面板。
//
// 这里刻意不再把所有选项都画成一样的胶囊：时长是单选、合盖是开关、断开是动作，
// 三种语义不同的东西用同一种外观呈现，正是磁贴网格当初的毛病，不该在弹层里重演。

/// 保持亮屏：时长单选 + 合盖开关 + 关闭。
struct KeepAwakeOptions: View {
    @EnvironmentObject private var store: SwitchStore

    /// nil 代表「一直」，-1 代表关闭。
    private var current: Int {
        let power = PowerController.shared
        guard power.keepAwake else { return -1 }
        return power.totalMinutes ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("保持亮屏")
                .font(.system(size: 12, weight: .semibold))

            Picker("", selection: Binding(get: { current }, set: apply)) {
                Text("关闭").tag(-1)
                Text("一直").tag(0)
                Text("30 分").tag(30)
                Text("1 时").tag(60)
                Text("2 时").tag(120)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            Toggle(isOn: Binding(
                get: { PowerController.shared.clamshell },
                set: { want in
                    PowerController.shared.setKeepAwake(true,
                                                        minutes: PowerController.shared.totalMinutes,
                                                        clamshell: want)
                    store.refresh()
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("合盖也不休眠").font(.system(size: 12))
                    Text("合上盖子继续跑，适合把电脑装进包里")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if PowerController.shared.keepAwake, let left = PowerController.shared.remainingMinutes {
                Text("还剩 \(left) 分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 258)
    }

    private func apply(_ value: Int) {
        if value < 0 {
            PowerController.shared.setKeepAwake(false)
        } else {
            PowerController.shared.setKeepAwake(true,
                                                minutes: value == 0 ? nil : value,
                                                clamshell: PowerController.shared.clamshell)
        }
        store.refresh()
    }
}

/// 耳机连接：设备、电量、连接/断开。
struct HeadphoneOptions: View {
    @EnvironmentObject private var store: SwitchStore

    private var item: SwitchItem? { store.items.first { $0.id == "connectHeadphones" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            let connected = item?.isOn ?? false

            HStack(spacing: 9) {
                Image(systemName: "airpods.pro")
                    .font(.system(size: 21))
                    .foregroundStyle(connected ? SwitchHue.cyan : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item?.detail ?? "未选择设备")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(connected ? "已连接" : "未连接")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let gauge = item?.gauge {
                TileGauge(value: gauge, hue: SwitchHue.cyan, isOn: false)
            }

            Divider()

            Button(connected ? "断开连接" : "连接") {
                store.setSwitch("connectHeadphones", on: !connected)
            }
            .controlSize(.small)

            Button("在系统设置里选择设备…") {
                AudioController.connectHeadphones()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
        .frame(width: 236)
    }
}

/// 屏幕分辨率：列表带勾选。分辨率字串长、可选项多，胶囊网格排不整齐，用列表。
struct ResolutionOptions: View {
    @State private var displays: [ResolutionController.Display] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(displays) { display in
                if displays.count > 1 {
                    Text(display.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 1) {
                    ForEach(display.resolutions) { resolution in
                        Button {
                            ResolutionController.apply(resolution, to: display.id)
                            displays = ResolutionController.displays()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .opacity(display.currentID == resolution.id ? 1 : 0)
                                    .frame(width: 11)
                                Text(resolution.label)
                                    .font(.system(size: 12))
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if displays.isEmpty {
                Text("没有检测到可切换的分辨率")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 210)
        .onAppear { displays = ResolutionController.displays() }
    }
}
