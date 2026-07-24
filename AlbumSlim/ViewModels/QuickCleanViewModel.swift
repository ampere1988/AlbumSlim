import Foundation

@MainActor @Observable
final class QuickCleanViewModel {
    var isScanning = false
    var scanProgress: Double = 0
    var scanPhase: CleanupCoordinator.ScanPhase = .done
    var cleanupGroups: [CleanupGroup] = []
    var hasCompletedScan = false

    /// 当前扫描 Task 引用，用于支持取消
    private var scanTask: Task<[CleanupGroup], Never>?

    var groupsByType: [CleanupGroup.GroupType: [CleanupGroup]] {
        Dictionary(grouping: cleanupGroups, by: \.type)
    }

    /// 取消当前扫描：底层 ScanProgress 已在检查点持久化，再次进入可续传
    func cancelScan() {
        scanTask?.cancel()
    }

    /// 进入页面时调用：优先从 coordinator 恢复，仅在必要时扫描
    func loadOrScan(services: AppServiceContainer) async {
        guard !isScanning else { return }
        let coordinator = services.cleanupCoordinator
        let version = services.photoLibrary.libraryVersion

        // 1. coordinator 内存中已有分组（App 启动时从骨架恢复）
        let existing = coordinator.pendingGroups
        if !existing.isEmpty {
            if coordinator.isAllCategoriesFresh(libraryVersion: version) {
                // 缓存全部有效，直接展示
                cleanupGroups = filterTrash(existing, services: services)
                return
            }
            // 有数据但部分分类过期 → 先展示旧数据，后台增量更新
            cleanupGroups = filterTrash(existing, services: services)
            await incrementalScan(services: services)
            return
        }

        // 2. 无任何数据 → 全量扫描
        await fullScan(services: services)
    }

    /// 用户手动点"重新扫描"
    func forceRescan(services: AppServiceContainer) async {
        await fullScan(services: services)
    }

    private func fullScan(services: AppServiceContainer) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        defer { isScanning = false; scanTask = nil }

        let coordinator = services.cleanupCoordinator
        let task = Task { await coordinator.smartScan(services: services) }
        scanTask = task
        let raw = await task.value
        guard !task.isCancelled else { return }

        cleanupGroups = filterTrash(raw, services: services)
        scanPhase = coordinator.scanPhase
        scanProgress = 1.0
        hasCompletedScan = true
    }

    private func incrementalScan(services: AppServiceContainer) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        defer { isScanning = false; scanTask = nil }

        let coordinator = services.cleanupCoordinator
        let task = Task { await coordinator.incrementalScan(services: services) }
        scanTask = task
        let raw = await task.value
        guard !task.isCancelled else { return }

        cleanupGroups = filterTrash(raw, services: services)
        scanPhase = coordinator.scanPhase
        scanProgress = 1.0
        hasCompletedScan = true
    }

    private func filterTrash(_ groups: [CleanupGroup], services: AppServiceContainer) -> [CleanupGroup] {
        let trashedIDs = services.trash.trashedAssetIDs
        guard !trashedIDs.isEmpty else { return groups }
        return groups.compactMap { group in
            var g = group
            g.items = g.items.filter { !trashedIDs.contains($0.id) }
            let minItems = (g.type == .similar || g.type == .burst) ? 2 : 1
            return g.items.count >= minItems ? g : nil
        }
    }
}
