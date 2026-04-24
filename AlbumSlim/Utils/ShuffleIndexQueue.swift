import Foundation

/// 随机浏览索引队列：基于 Fisher–Yates 打乱 `[0..<total]`，
/// 耗尽后对剩余段重新打乱并把最近用过的索引排除，保证短期不重复。
struct ShuffleIndexQueue {
    /// 已打乱好的索引数组，cursor 指向下一个要消费的位置
    private(set) var queue: [Int] = []
    private(set) var cursor: Int = 0

    /// 最近使用过的索引，再次 reshuffle 时排除，避免短时间内重复
    private var recent: [Int] = []
    private let recentCapacity: Int

    private let total: Int

    init(total: Int, recentCapacity: Int = 50) {
        self.total = total
        self.recentCapacity = min(recentCapacity, max(0, total - 1))
        guard total > 0 else { return }
        self.queue = Array(0..<total)
        self.queue.shuffle()
    }

    /// 当前位置的索引（-1 表示队列未开始或已空）
    var current: Int? {
        guard cursor >= 0, cursor < queue.count else { return nil }
        return queue[cursor]
    }

    /// 向前推进一格。若临近末尾则追加一轮新的打乱段。
    mutating func advance() -> Int? {
        guard total > 0 else { return nil }
        cursor += 1
        replenishIfNeeded()
        pushRecent(queue[safe: cursor])
        return queue[safe: cursor]
    }

    /// 后退一格。到头返回 nil。
    mutating func retreat() -> Int? {
        guard cursor > 0 else { return nil }
        cursor -= 1
        return queue[safe: cursor]
    }

    /// 读取队列中某个游标位置的索引（供窗口预加载用）
    func index(at cursor: Int) -> Int? {
        queue[safe: cursor]
    }

    /// 从队列中移除某个 PHFetchResult 索引（删除后使队列不再指向该资源）。
    /// 注意：若删除的索引小于当前 cursor，cursor 自动回退保持指向同一逻辑位置。
    mutating func remove(fetchIndex: Int) {
        queue.removeAll { $0 == fetchIndex }
        // cursor 可能越界或指向被删位置后的元素，不特别处理——由上层调用 advance()/retreat() 恢复
    }

    private mutating func replenishIfNeeded() {
        guard total > 0 else { return }
        let remaining = queue.count - cursor
        guard remaining < 8 else { return }

        // 生成全集排除最近 recent，洗牌后追加到末尾
        let excluded = Set(recent)
        var pool = (0..<total).filter { !excluded.contains($0) }
        if pool.isEmpty {
            // 极小相册（< recentCapacity），退化为全集打乱
            pool = Array(0..<total)
        }
        pool.shuffle()
        queue.append(contentsOf: pool)
    }

    private mutating func pushRecent(_ value: Int?) {
        guard let value else { return }
        recent.append(value)
        if recent.count > recentCapacity {
            recent.removeFirst(recent.count - recentCapacity)
        }
    }
}

