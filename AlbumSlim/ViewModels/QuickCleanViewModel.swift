import Foundation

@MainActor @Observable
final class QuickCleanViewModel {
    var isScanning = false
    var scanProgress: Double = 0
    var scanPhase: CleanupCoordinator.ScanPhase = .done
    var cleanupGroups: [CleanupGroup] = []
    var isCleaningUp = false
    var cleanupResult: CleanupResult?
    var deselectedGroupIDs: Set<UUID> = []

    struct CleanupResult {
        let deletedCount: Int
        let freedSpace: Int64
        let duration: TimeInterval
    }

    var totalSavableSize: Int64 {
        selectedGroups.reduce(Int64(0)) { $0 + $1.savableSize }
    }

    var groupsByType: [CleanupGroup.GroupType: [CleanupGroup]] {
        Dictionary(grouping: cleanupGroups, by: \.type)
    }

    var selectedGroups: [CleanupGroup] {
        cleanupGroups.filter { !deselectedGroupIDs.contains($0.id) }
    }

    func startScan(services: AppServiceContainer) async {
        isScanning = true
        scanProgress = 0
        cleanupResult = nil
        defer { isScanning = false }

        let coordinator = services.cleanupCoordinator
        cleanupGroups = await coordinator.smartScan(services: services)
        scanPhase = coordinator.scanPhase
        scanProgress = 1.0
    }

    func executeCleanup(services: AppServiceContainer) async {
        let groups = selectedGroups
        guard !groups.isEmpty else { return }

        isCleaningUp = true
        let start = Date()

        do {
            let freedSize = try await services.cleanupCoordinator.executeCleanup(groups: groups)
            let deletedCount = groups.reduce(0) { total, group in
                if group.bestItemID != nil {
                    return total + group.items.count - 1
                }
                return total + group.items.count
            }
            cleanupResult = CleanupResult(
                deletedCount: deletedCount,
                freedSpace: freedSize,
                duration: Date().timeIntervalSince(start)
            )
            let _ = services.achievement.recordCleanup(freedSpace: freedSize, deletedCount: deletedCount)
            cleanupGroups.removeAll { !deselectedGroupIDs.contains($0.id) == false }
            cleanupGroups = services.cleanupCoordinator.pendingGroups
        } catch {
            // 删除被用户取消或失败
        }

        isCleaningUp = false
    }

    func toggleGroup(_ group: CleanupGroup) {
        if deselectedGroupIDs.contains(group.id) {
            deselectedGroupIDs.remove(group.id)
        } else {
            deselectedGroupIDs.insert(group.id)
        }
    }
}
