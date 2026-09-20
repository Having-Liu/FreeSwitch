// 分组核心逻辑的测试。直接编译 App 里的 FreeSwitch/Model/SwitchGroups.swift，测的是真代码。
// 运行：./scripts/test-groups.sh
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok { print("  ✓ \(name)") } else { failures += 1; print("  ✗ \(name)  \(detail())") }
}
func ids(_ groups: [SwitchGroup]) -> [[String]] { groups.map(\.items) }

let defaults: [(id: String, name: String)] = [("a", "甲"), ("b", "乙")]
let catalog: [(id: String, group: String)] = [("a1", "a"), ("a2", "a"), ("b1", "b")]

print("【moved：与 SwiftUI 的 move(fromOffsets:toOffset:) 语义一致】")
let letters = ["A", "B", "C", "D"]
check(GroupLayout.moved(letters, fromOffsets: [0], toOffset: 2) == ["B", "A", "C", "D"], "把第一个挪到第三个之前")
check(GroupLayout.moved(letters, fromOffsets: [3], toOffset: 0) == ["D", "A", "B", "C"], "把最后一个挪到最前")
check(GroupLayout.moved(letters, fromOffsets: [1, 2], toOffset: 4) == ["A", "D", "B", "C"], "一次挪两个到末尾")

print("【跨分组拖动】")
let base = GroupLayout.defaultGroups(defaults: defaults, catalog: catalog)
check(ids(base) == [["a1", "a2"], ["b1"]], "默认分组", "\(ids(base))")
// 摊平后：0 甲  1 a1  2 a2  3 乙  4 b1
let crossed = GroupLayout.applyingMove(to: base, from: [1], to: 4)
check(ids(crossed) == [["a2"], ["a1", "b1"]], "a1 拖过「乙」标题 → 进入乙组", "\(ids(crossed))")

// 拖到第一个分组标题之前 = 新建一组。稳的入口是设置里的「新建分组」按钮，
// 这条路成不成立要看 SwiftUI 肯不肯给出 destination 0，逻辑本身先保证对。
let toTop = GroupLayout.applyingMove(to: base, from: [4], to: 0)
check(ids(toTop) == [["b1"], ["a1", "a2"], []], "拖到所有标题之前 → 新建一组", "\(ids(toTop))")
check(toTop.first?.name == "", "新建的分组没有名字", "\(toTop.first?.name ?? "nil")")
check(toTop.first?.id == "group1", "新分组用没被占用的最小编号", "\(toTop.first?.id ?? "nil")")
check(GroupLayout.nextGroupID(taken: ["group1", "group3"]) == "group2",
      "编号跳过已占用的", GroupLayout.nextGroupID(taken: ["group1", "group3"]))

let toEnd = GroupLayout.applyingMove(to: base, from: [1], to: 5)
check(ids(toEnd) == [["a2"], ["b1", "a1"]], "拖到列表末尾 → 进入最后一组末尾", "\(ids(toEnd))")

// 拖分组标题 = 整组搬家。把「乙」拖到最上面。
let groupMoved = GroupLayout.applyingMove(to: base, from: [3], to: 0)
check(groupMoved.map(\.id) == ["b", "a"], "拖分组标题 → 整组搬到前面", "\(groupMoved.map(\.id))")
check(ids(groupMoved) == [["b1"], ["a1", "a2"]], "整组搬家不打散组内开关", "\(ids(groupMoved))")

check(crossed.map(\.name) == ["甲", "乙"], "拖动不影响分组名")

print("【分组上移 / 下移】")
check(GroupLayout.movingGroup(base, id: "b", by: -1).map(\.id) == ["b", "a"], "乙组上移")
check(GroupLayout.movingGroup(base, id: "a", by: -1) == base, "第一组再上移 → 不动")

print("【迁移与对齐】")
let legacy = GroupLayout.defaultGroups(defaults: defaults, catalog: catalog, legacyOrder: ["b1", "a2", "a1"])
check(ids(legacy) == [["a2", "a1"], ["b1"]], "首次迁移沿用旧版组内顺序", "\(ids(legacy))")
let stored = [SwitchGroup(id: "b", name: "我的", items: ["a1", "gone", "a1"]),
              SwitchGroup(id: "a", name: "甲", items: [])]
let merged = GroupLayout.merged(stored, defaults: defaults, catalog: catalog)
check(merged.map(\.id) == ["b", "a"], "保留用户排定的分组顺序")
check(merged[0].name == "我的", "保留用户改过的分组名")
check(merged[0].items.filter { $0 == "a1" }.count == 1 && !merged.flatMap(\.items).contains("gone"),
      "去掉目录里不存在的开关，重复的只留一个", "\(ids(merged))")
check(ids(merged) == [["a1", "b1"], ["a2"]], "b1 还没归属 → 放进它的默认分组「乙」(id b)", "\(ids(merged))")
let missingGroup = GroupLayout.merged([SwitchGroup(id: "a", name: "甲", items: ["a1", "a2", "b1"])],
                                      defaults: defaults, catalog: catalog)
check(missingGroup.map(\.id) == ["a", "b"], "缺失的默认分组补回来")

print("【排版：顺序优先，只拉宽宽磁贴】")
func layout(_ spans: [Int]) -> [[String]] {
    GroupLayout.pack(spans: spans, columns: 5).map { $0.map { "\($0.index):\($0.span)" } }
}
check(layout([1, 1, 1, 2]) == [["0:1", "1:1", "2:1", "3:2"]], "1+1+1+2 正好一行")
check(layout([1, 2, 1]) == [["0:1", "1:3", "2:1"]], "只有 4 格 → 宽磁贴拉宽到 3 列补齐")
check(layout([1, 1, 1, 1, 1, 1]) == [["0:1", "1:1", "2:1", "3:1", "4:1"], ["5:1"]], "六个单列 → 换行，末行留空")
let orderKept = GroupLayout.pack(spans: [1, 1, 1, 1, 2, 1], columns: 5).flatMap { $0.map(\.index) }
check(orderKept == [0, 1, 2, 3, 4, 5], "放不下就换行，绝不把后面的往前挪", "\(orderKept)")
check(layout([1, 1, 1, 1, 2, 1]) == [["0:1", "1:1", "2:1", "3:1"], ["4:4", "5:1"]], "上一行没有宽磁贴就留空；下一行的宽磁贴拉宽", "\(layout([1, 1, 1, 1, 2, 1]))")

print(failures == 0 ? "\n全部通过" : "\n失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
