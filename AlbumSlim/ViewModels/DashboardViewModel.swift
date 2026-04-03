import Foundation

@MainActor @Observable
final class DashboardViewModel {
    var stats = StorageStats()
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    func loadStats(services: AppServiceContainer) async {
        let status = await services.photoLibrary.requestAuthorization()
        guard status == .authorized || status == .limited else {
            errorMessage = "需要相册访问权限才能分析存储空间"
            return
        }

        let analyzer = services.storageAnalyzer

        // 有缓存就立即展示，无缓存才显示 loading
        if analyzer.stats.isEmpty {
            isLoading = true
        } else {
            stats = analyzer.stats
            isRefreshing = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        await analyzer.analyzeIfNeeded(using: services.photoLibrary)
        stats = analyzer.stats
    }

    func forceRescan(services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        await services.storageAnalyzer.forceRescan(using: services.photoLibrary)
        stats = services.storageAnalyzer.stats
    }
}
