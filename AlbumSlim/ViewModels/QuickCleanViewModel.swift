import Foundation

@MainActor @Observable
final class QuickCleanViewModel {
    var isScanning = false
    var scanProgress: Double = 0
    var scanPhase: CleanupCoordinator.ScanPhase = .done
    var cleanupGroups: [CleanupGroup] = []

    var groupsByType: [CleanupGroup.GroupType: [CleanupGroup]] {
        Dictionary(grouping: cleanupGroups, by: \.type)
    }

    func startScan(services: AppServiceContainer) async {
        isScanning = true
        scanProgress = 0
        cleanupGroups = []
        defer { isScanning = false }

        let coordinator = services.cleanupCoordinator
        cleanupGroups = await coordinator.smartScan(services: services)
        scanPhase = coordinator.scanPhase
        scanProgress = 1.0
    }
}
