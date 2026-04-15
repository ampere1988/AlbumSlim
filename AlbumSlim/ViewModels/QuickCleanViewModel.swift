import Foundation

@MainActor @Observable
final class QuickCleanViewModel {
    var isScanning = false
    var scanProgress: Double = 0
    var scanPhase: CleanupCoordinator.ScanPhase = .done
    var cleanupGroups: [CleanupGroup] = []
    var hasCompletedScan = false

    var groupsByType: [CleanupGroup.GroupType: [CleanupGroup]] {
        Dictionary(grouping: cleanupGroups, by: \.type)
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
                cleanupGroups = existing
                return
            }
            // 有数据但部分分类过期 → 先展示旧数据，后台增量更新
            cleanupGroups = existing
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
        defer { isScanning = false }

        let coordinator = services.cleanupCoordinator
        cleanupGroups = await coordinator.smartScan(services: services)
        scanPhase = coordinator.scanPhase
        scanProgress = 1.0
        hasCompletedScan = true
    }

    private func incrementalScan(services: AppServiceContainer) async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        let coordinator = services.cleanupCoordinator
        cleanupGroups = await coordinator.incrementalScan(services: services)
        scanPhase = coordinator.scanPhase
        scanProgress = 1.0
        hasCompletedScan = true
    }
}
