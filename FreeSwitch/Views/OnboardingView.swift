import SwiftUI

/// 四页引导。
///
/// 做法上有一条贯穿的主张：**能给真东西就不要给插图**。
/// 第二页右边嵌的就是设置里那张「开关」页，第四页右边嵌的就是「权限」页——
/// 用户在引导里拖的那一下、授的那一次权，都是真的生效的，
/// 而且等他以后打开设置，看到的还是同一张脸，不用重新认一遍。
struct OnboardingView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var page = 0
    @State private var language = AppLanguage.override

    private let pageCount = 4
    /// 嵌进来的那张设置页的尺寸。按真实设置窗口的内容区取，看着才像同一个东西。
    private let embedSize = CGSize(width: 640, height: 520)

    var body: some View {
        ZStack {
            SettingsGlassShell(primaryHalo: SwitchHue.indigo, secondaryHalo: SwitchHue.blue)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                content
                    .frame(maxWidth: 1180)
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
        .ignoresSafeArea()
    }

    // MARK: 头尾

    private var header: some View {
        HStack(spacing: 9) {
            Image("handle")
                .font(.system(size: 17))
                .foregroundStyle(SwitchHue.indigo)
            Text("FreeSwitch").font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(L("第 %lld 步，共 %lld 步", page + 1, pageCount))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            // 圆点既是进度也是导航：看到第四页想回头看第二页，不用连点两次「上一步」。
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { page = index } }
                }
            }

            Spacer()

            Button(L("跳过")) { OnboardingWindow.close() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            if page > 0 {
                Button(L("上一步")) { withAnimation(.easeOut(duration: 0.18)) { page -= 1 } }
            }

            if page < pageCount - 1 {
                Button(L("下一步")) { withAnimation(.easeOut(duration: 0.18)) { page += 1 } }
                    .keyboardShortcut(.defaultAction)
            } else {
                // 本来想在这里直接把面板弹出来，但 MenuBarExtra 没有公开的程序化打开接口，
                // 唯一的办法是去 NSApp.windows 里翻状态栏窗口再 performClick——
                // 那是依赖私有结构的写法，为这点便利不值得。改成在第四页末尾直接告诉用户图标在哪。
                Button(L("开始使用")) { OnboardingWindow.finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: 四页

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0: welcome
        case 1: sortingAndHotkeys
        case 2: controlCenter
        default: permissions
        }
    }

    /// 第一页：欢迎 + 隐私。
    ///
    /// 隐私这段给的是**可核对的依据**，不是「我们承诺」。
    /// 一个要辅助功能和自动化授权的 App，光靠承诺是不够的。
    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text(L("欢迎使用 FreeSwitch"))
                .font(.system(size: 34, weight: .semibold))

            Text(L("把散落在系统各处的开关收进菜单栏，一次点击就能切换。免费、开源。"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            VStack(alignment: .leading, spacing: 10) {
                Bullet(symbol: "wifi.slash", title: L("它不联网"),
                       detail: L("源码里没有任何一处网络调用，二进制也没有链接网络框架"))
                Bullet(symbol: "externaldrive.badge.xmark", title: L("它不收集任何数据"),
                       detail: L("你的设置只存在这台 Mac 的偏好文件里，不会离开你的电脑"))
                Bullet(symbol: "chevron.left.forwardslash.chevron.right", title: L("以上都可以自己查"),
                       detail: L("代码全部公开，上面两条不是承诺，是可以核对的事实"))
            }
            .padding(26)
            .frame(width: 620)
            .settingsContentCard(fills: false)

            languageSwitcher
                .padding(.top, 4)
        }
    }

    /// 语言切换放在第一页。
    ///
    /// **它的读者恰恰是看不懂当前这套界面文字的人**——系统语言匹配错了的那位。
    /// 所以：用地球图标（不靠文字就能认出这是语言）、菜单里每种语言都用它自己的语言写，
    /// 并且不加任何说明文字（写了他也读不懂）。
    ///
    /// 选完立刻重启：引导还没走完，`hasCompleted` 还是假，重启后会用新语言从第一页重来——
    /// 正是这个人想要的结果。不像设置里那样先提示「重启后生效」再等他点，
    /// 那个提示对读不懂的人毫无意义。
    private var languageSwitcher: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Picker("", selection: $language) {
                ForEach(AppLanguage.all, id: \.code) { item in
                    Text(item.name).tag(item.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .onChange(of: language) { _, newValue in
            guard newValue != AppLanguage.override else { return }
            AppLanguage.override = newValue
            AppLanguage.relaunch()
        }
    }

    /// 第二页：排序和快捷键——右边嵌的就是真的设置页，拖动和录快捷键当场生效。
    private var sortingAndHotkeys: some View {
        Spread(
            title: L("它长什么样，你说了算"),
            subtitle: L("右边就是设置里的「开关」页，现在动它，改动立刻生效。"),
            bullets: [
                (symbol: "arrow.up.arrow.down", title: L("拖动排序"),
                 detail: L("按住任意一行上下拖；拖过分组标题就换到那个分组")),
                (symbol: "pencil", title: L("分组随你安排"),
                 detail: L("拖到最上面能新建一组；分组名点一下就能改，清空则只当分隔")),
                (symbol: "command", title: L("绑全局快捷键"),
                 detail: L("鼠标移到某一行，右边会浮出「设置快捷键」，按下组合键即可")),
                (symbol: "eye.slash", title: L("用不上的就关掉"),
                 detail: L("最右边的开关控制它出不出现在菜单栏面板里")),
            ],
            right: AnyView(SwitchesPane(prefs: prefs, embedded: true)),
            size: embedSize)
    }

    /// 第三页：控制中心。这一步 App 代劳不了，只能讲清楚。
    ///
    /// 右边原来有一张控制中心的示意图，去掉了：那张图既不是真的、也代替不了真的，
    /// 占着半页却什么都没多说。这一页就把话说清楚。
    private var controlCenter: some View {
        Spread(
            title: L("也可以放进 Mac 控制中心"),
            subtitle: L("你甚至不需要感受到 FreeSwitch 的存在，就像在用系统自带的功能。"),
            bullets: [
                (symbol: "1.circle", title: L("拉开控制中心"),
                 detail: L("点菜单栏右上角那两个开关样子的图标")),
                (symbol: "2.circle", title: L("进入「编辑控件」"),
                 detail: L("在控制中心里往下滚到底，点「编辑控件」")),
                (symbol: "3.circle", title: L("找到 FreeSwitch"),
                 detail: L("左侧列表里选 FreeSwitch，把想要的控件拖进去")),
                (symbol: "info.circle", title: L("控件只放系统没有的"),
                 detail: L("深色模式、低电量、锁定屏幕这些系统自己就有，不重复占位")),
            ])
    }

    /// 第四页：权限。右边嵌的就是真的权限页，用户直接在这儿授权。
    ///
    /// 这也是整个窗口层级只能用 `.normal` 的原因——授权会拉起系统设置，
    /// 引导窗口不能压在它上面。
    private var permissions: some View {
        Spread(
            title: L("按需授权就好"),
            subtitle: L("用到哪项才需要哪项。现在全部跳过也完全可以用。"),
            bullets: [
                (symbol: "gearshape.2", title: L("自动化 · 系统事件"),
                 detail: L("给「黑暗模式」和「自动隐藏程序坞」用")),
                (symbol: "folder", title: L("自动化 · 访达"),
                 detail: L("给「清空废纸篓」，以及「隐藏所有窗口」时折叠访达的窗口用")),
                (symbol: "keyboard", title: L("辅助功能"),
                 detail: L("给「锁定键盘」用——擦屏幕时不怕误触")),
                (symbol: "hand.raised", title: L("不给也不影响其它开关"),
                 detail: L("没授权的开关会明说原因，不会默默失败")),
                (symbol: "menubar.arrow.up.rectangle", title: L("关掉这个窗口之后"),
                 detail: L("点菜单栏右上角那个拨杆图标，就能打开面板")),
            ],
            right: AnyView(PermissionsPane()),
            size: embedSize)
    }
}

// MARK: - 版式

/// 左边讲，右边给真东西。
private struct Spread: View {
    let title: String
    let subtitle: String
    let bullets: [(symbol: String, title: String, detail: String)]
    /// 没有右边内容时整块居中、文案栏放宽——与其塞一张凑数的示意图，不如把话说清楚。
    var right: AnyView? = nil
    var size: CGSize = .zero

    var body: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 30, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bullets, id: \.title) { b in
                        Bullet(symbol: b.symbol, title: b.title, detail: b.detail)
                    }
                }
                .padding(.top, 4)
            }
            .frame(width: right == nil ? 620 : 400, alignment: .topLeading)

            // 尺寸加在卡片**外面**：卡片内部会把内容撑满给定的框，
            // 反过来先定尺寸再套卡片，卡片的 maxWidth/.infinity 会和固定尺寸打架。
            if let right {
                right
                    .settingsContentCard()
                    .frame(width: size.width, height: size.height)
            }
        }
    }
}

private struct Bullet: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(SwitchHue.indigo)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
