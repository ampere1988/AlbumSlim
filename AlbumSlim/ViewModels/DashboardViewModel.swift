import Foundation

@MainActor @Observable
final class DashboardViewModel {
    var stats = StorageStats()
    var isLoading = false
    var errorMessage: String?

    func loadStats(services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        let status = await services.photoLibrary.requestAuthorization()
        guard status == .authorized || status == .limited else {
            errorMessage = "需要相册访问权限才能分析存储空间"
            return
        }

        await services.storageAnalyzer.analyze(using: services.photoLibrary)
        stats = services.storageAnalyzer.stats
    }
}
