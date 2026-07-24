import Foundation

/// 记录用户在滑动清理中「保留」过的照片，避免下次重复出现。
///
/// 只持久化 keep 决策——trash 决策由 `TrashService` 自己持久化，
/// 两边合起来构成「已处理」全集，不重复记账。
@MainActor @Observable
final class SwipeCleanProgressStore {

    static let storageKey = "swipeCleanKeptIDs_v1"

    private(set) var keptIDs: Set<String> = []

    init() {
        load()
    }

    // MARK: - 查询

    func isKept(_ assetID: String) -> Bool {
        keptIDs.contains(assetID)
    }

    func keptCount(in assetIDs: [String]) -> Int {
        assetIDs.reduce(0) { $0 + (keptIDs.contains($1) ? 1 : 0) }
    }

    /// 从候选中剔除已保留与已在垃圾桶的，保持原始顺序
    func pendingIDs(from assetIDs: [String], excluding trashedIDs: Set<String>) -> [String] {
        assetIDs.filter { !keptIDs.contains($0) && !trashedIDs.contains($0) }
    }

    // MARK: - 写入

    func markKept(_ assetID: String) {
        guard !keptIDs.contains(assetID) else { return }
        keptIDs.insert(assetID)
        persist()
    }

    /// 撤销用：把一次 keep 决策撤回
    func unmarkKept(_ assetID: String) {
        guard keptIDs.contains(assetID) else { return }
        keptIDs.remove(assetID)
        persist()
    }

    /// 重新清理某一堆：只清掉这堆内的记录
    func resetBucket(assetIDs: [String]) {
        let target = Set(assetIDs)
        let remaining = keptIDs.subtracting(target)
        guard remaining.count != keptIDs.count else { return }
        keptIDs = remaining
        persist()
    }

    // MARK: - 持久化

    private func load() {
        guard let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] else { return }
        keptIDs = Set(stored)
    }

    private func persist() {
        UserDefaults.standard.set(Array(keptIDs), forKey: Self.storageKey)
    }
}
