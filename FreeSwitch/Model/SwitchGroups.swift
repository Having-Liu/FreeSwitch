import Foundation

// 用户自定义的开关分组。
//
// 分组有稳定的 id（改名不影响归属），名字和组内顺序都归用户所有；
// 目录里的 `defaultGroup` 只决定「第一次」和「恢复默认」时各开关落在哪。
//
// 本文件只依赖 Foundation，不碰 SwiftUI、也不引用 App 里的其它类型，
// 这样核心逻辑能脱离 App 单独编译测试：scripts/test-groups.sh。

struct SwitchGroup: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var items: [String]
}

/// 设置列表里的一行：分组标题，或一个开关。
///
/// 把两者摊平进同一个可拖动列表，是跨分组移动的关键：SwiftUI 的 `.onMove`
/// 只能在同一个 ForEach 内部挪动，分成多个 Section 就拖不过去。摊平之后，
/// 开关拖过哪个分组标题，就落进哪个分组。
enum GroupRow: Hashable, Identifiable {
    case group(String)
    case item(String)

    var id: String {
        switch self {
        case .group(let id): return "group." + id
        case .item(let id):  return "item." + id
        }
    }
}

enum GroupLayout {

    /// 首次使用或「恢复默认」：按目录里的默认分组建组。
    /// 组内顺序优先沿用 `legacyOrder`（旧版保存的全局顺序），其余按目录顺序。
    static func defaultGroups(defaults: [(id: String, name: String)],
                              catalog: [(id: String, group: String)],
                              legacyOrder: [String] = []) -> [SwitchGroup] {
        var rank: [String: Int] = [:]
        for (position, id) in legacyOrder.enumerated() where rank[id] == nil { rank[id] = position }

        return defaults.map { group in
            let members = catalog.enumerated().filter { $0.element.group == group.id }
            let sorted = members.sorted { a, b in
                let ra = rank[a.element.id] ?? Int.max
                let rb = rank[b.element.id] ?? Int.max
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            return SwitchGroup(id: group.id, name: group.name, items: sorted.map { $0.element.id })
        }
    }

    /// 读回已存储的分组后，与当前目录对齐：
    ///  - 去掉目录里已经不存在的开关，同一个开关出现两次只留第一次；
    ///  - 缺失的默认分组补回来；
    ///  - 目录里新增、还没归入任何分组的开关，放进它默认分组的末尾。
    static func merged(_ stored: [SwitchGroup],
                       defaults: [(id: String, name: String)],
                       catalog: [(id: String, group: String)]) -> [SwitchGroup] {
        let known = Set(catalog.map(\.id))
        var seen = Set<String>()
        var result: [SwitchGroup] = stored.map { group in
            var cleaned = group
            cleaned.items = group.items.filter { known.contains($0) && seen.insert($0).inserted }
            return cleaned
        }
        for group in defaults where !result.contains(where: { $0.id == group.id }) {
            result.append(SwitchGroup(id: group.id, name: group.name, items: []))
        }
        for entry in catalog where !seen.contains(entry.id) {
            if let index = result.firstIndex(where: { $0.id == entry.group }) {
                result[index].items.append(entry.id)
            } else if !result.isEmpty {
                result[result.count - 1].items.append(entry.id)
            }
            seen.insert(entry.id)
        }
        return result
    }

    /// 新分组的 id。用「没被占用的最小编号」而不是 UUID：
    /// 这个函数是纯逻辑、有独立测试，随机 id 会让测试不可复现。
    static func nextGroupID(taken: [String]) -> String {
        let used = Set(taken)
        var n = 1
        while used.contains("group\(n)") { n += 1 }
        return "group\(n)"
    }

    static func rows(for groups: [SwitchGroup]) -> [GroupRow] {
        groups.flatMap { [.group($0.id)] + $0.items.map { .item($0) } }
    }

    /// 在摊平的列表里移动开关，再按分组标题重新切分。
    ///  - 落在第一个分组标题之前的开关，归入第一个分组的开头；
    ///  - 分组标题本身不参与拖动：挪动里只要含有标题，整次挪动作废，分组原样返回。
    static func applyingMove(to groups: [SwitchGroup], from source: IndexSet, to destination: Int) -> [SwitchGroup] {
        let original = rows(for: groups)

        // 拖的是分组标题 → 整组搬家。
        // 以前这里直接作废，于是标题只能用上下箭头挪；而标题一旦标成不可移动，
        // 又会让「拖到最顶上」那个落点也一起消失。让它真的能拖，两个问题一起解决。
        if source.count == 1, let index = source.first, original.indices.contains(index),
           case .group(let movingID) = original[index] {
            return movingGroup(groups, id: movingID, toRowDestination: destination, rows: original)
        }
        // 一次拖多行、且其中含分组标题：语义不清，作废。
        if source.contains(where: { original.indices.contains($0) && isGroup(original[$0]) }) {
            return groups
        }
        var result: [SwitchGroup] = []
        var leading: [String] = []
        for row in moved(original, fromOffsets: source, toOffset: destination) {
            switch row {
            case .group(let id):
                guard let group = groups.first(where: { $0.id == id }) else { continue }
                result.append(SwitchGroup(id: id, name: group.name, items: []))
            case .item(let id):
                if result.isEmpty { leading.append(id) } else { result[result.count - 1].items.append(id) }
            }
        }
        // 拖到最顶上（第一个分组标题之前）= 新建一个分组。
        // 这条路能不能走通取决于 SwiftUI 肯不肯把 destination 给成 0，不保证；
        // 稳的入口是设置底部那个「新建分组」按钮。逻辑留着，成立时就是白赚的。
        if !leading.isEmpty {
            result.insert(SwitchGroup(id: nextGroupID(taken: result.map(\.id)),
                                      name: "", items: leading), at: 0)
        }
        return result
    }

    /// 分组整体上移（offset = -1）或下移（+1），越界则不动。
    static func movingGroup(_ groups: [SwitchGroup], id: String, by offset: Int) -> [SwitchGroup] {
        guard let from = groups.firstIndex(where: { $0.id == id }), groups.indices.contains(from + offset) else {
            return groups
        }
        var result = groups
        result.swapAt(from, from + offset)
        return result
    }

    /// 按用户排定的顺序，把一串跨列数排进每行 `columns` 列。
    ///
    /// 顺序优先：放不下就换行，**绝不把后面的开关往前挪去填空**——
    /// 用户自己排出来的顺序比整齐更重要。行尾剩下的空位只分给这一行里的宽磁贴
    /// （跨列 > 1 的，它本来就有弹性）；没有宽磁贴就留空。
    static func pack(spans: [Int], columns: Int) -> [[(index: Int, span: Int)]] {
        var result: [[(index: Int, span: Int)]] = []
        var row: [(index: Int, span: Int)] = []
        var used = 0

        func closeRow() {
            guard !row.isEmpty else { return }
            if used < columns, let wide = row.firstIndex(where: { $0.span > 1 }) {
                row[wide].span += columns - used
            }
            result.append(row)
            row = []
            used = 0
        }

        for (index, raw) in spans.enumerated() {
            let span = min(max(raw, 1), columns)
            if used + span > columns { closeRow() }
            row.append((index: index, span: span))
            used += span
        }
        closeRow()
        return result
    }

    /// 与 SwiftUI 的 `move(fromOffsets:toOffset:)` 语义一致：`destination` 是原数组中的位置，
    /// 被挪动的元素插到它之前。自己实现一份，是为了让本文件不依赖 SwiftUI。
    static func moved<T>(_ array: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        let valid = source.filter { array.indices.contains($0) }
        let moving = valid.map { array[$0] }
        var remaining = array.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let insertAt = min(max(destination - valid.filter { $0 < destination }.count, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertAt)
        return remaining
    }

    /// 把某个分组整体挪到「摊平后的第几行」那个位置。
    /// 目标组序号 = 这一行之前出现过几个分组标题。
    static func movingGroup(_ groups: [SwitchGroup], id: String,
                            toRowDestination destination: Int, rows: [GroupRow]) -> [SwitchGroup] {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return groups }
        let target = rows.prefix(max(0, min(destination, rows.count)))
            .filter { if case .group = $0 { return true } else { return false } }.count
        // 手写而不是用 Array.move(fromOffsets:toOffset:)：那个方法来自 SwiftUI，
        // 而本文件刻意只依赖 Foundation，好让核心逻辑能脱离 App 单独编译测试。
        var result = groups
        let moving = result.remove(at: from)
        result.insert(moving, at: min(max(target - (target > from ? 1 : 0), 0), result.count))
        return result
    }

    private static func isGroup(_ row: GroupRow) -> Bool {
        if case .group = row { return true }
        return false
    }
}
