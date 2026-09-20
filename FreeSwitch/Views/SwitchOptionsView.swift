import SwiftUI

// 带参数的开关，点磁贴弹出的选项面板。
//
// 这里刻意不再把所有选项都画成一样的胶囊：时长是单选、合盖是开关、断开是动作，
// 三种语义不同的东西用同一种外观呈现，正是磁贴网格当初的毛病，不该在弹层里重演。
//
// **弹层的内容高度不能随状态变化。** popover 一弹出就按当时的内容定死尺寸，
// 之后内容变高不会跟着长，只会被裁掉——这正是「有时候显示不全、有时候又正常」的来历。
// 所以：条件出现的那一行要常驻（不适用时留空占位），需要异步/延迟才能拿到的数据
// 要在视图创建时就取好，不能等到 onAppear。
// 宽度同理用 minWidth 而不是定死：德语、俄语的分段选择器比中文宽得多。

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

            // 这一行常驻：不适用时画一个空字符串占住同样的高度。
            // 条件渲染会让 popover 弹出后内容变高，而 popover 不会跟着长，只会裁。
            Text(remainingText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 258, alignment: .leading)
        .fixedSize()
    }

    private var remainingText: String {
        let power = PowerController.shared
        guard power.keepAwake, let left = power.remainingMinutes else { return " " }
        return L("还剩 %lld 分钟", left)
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

struct ResolutionOptions: View {
    /// 在视图创建时就读，**不要**放到 onAppear 里。
    /// 放 onAppear 的话，popover 弹出那一刻内容只有「没有检测到可切换的分辨率」一行，
    /// 尺寸就按这一行定死了；随后列表填进来，多出来的部分直接被裁掉。
    @State private var displays: [ResolutionController.Display] = ResolutionController.displays()

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
        .frame(minWidth: 210, alignment: .leading)
        .fixedSize()
    }
}
