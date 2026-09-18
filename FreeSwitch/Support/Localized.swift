import Foundation

/// 取一条本地化文案。
///
/// 全项目的字符串键就是**中文原文**：`Localizable.xcstrings` 的源语言是 zh-Hans，
/// 所以中文那份不用再抄一遍，改中文原文等于改键。
///
/// SwiftUI 的 `Text("中文")`、`Label("中文", systemImage:)`、`.help("中文")` 接的是
/// `LocalizedStringKey`，**字面量会自动查表**，不用套这个函数。需要它的只有两种地方：
///  - AppKit（`NSAlert.messageText` 之类，参数是普通 String，不查表）；
///  - 文案存在变量里再交给界面的（`Text(item.title)` 同样不查表，这是最容易漏的一种）。
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
}

/// 带一个参数的本地化文案。键里用 `%@` 占位。
func L(_ key: String, _ argument: CVarArg) -> String {
    String(format: L(key), argument)
}
