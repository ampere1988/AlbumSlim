import Foundation
import Photos

@MainActor @Observable
final class StorageAnalyzer {
    private(set) var stats = StorageStats()
    private(set) var isAnalyzing = false
    private(set) var progress: Double = 0

    /// 上次扫描时的相册版本号，用于判断是否需要重新扫描
    private var lastLibraryVersion: Int = -1

    init() {
        // 启动时立即加载缓存
        if let cached = StorageStats.loadCached() {
            stats = cached
        }
    }

    /// 主入口：有缓存就先展示，后台静默扫描更新
    /// - Returns: true 表示使用了缓存（无需等待扫描），false 表示首次扫描
    @discardableResult
    func analyzeIfNeeded(using photoLibrary: PhotoLibraryService) async -> Bool {
        // 相册未变更，跳过扫描
        if lastLibraryVersion == photoLibrary.libraryVersion && !stats.isEmpty {
            return true
        }

        let hasCachedData = !stats.isEmpty

        if hasCachedData {
            // 有缓存：后台静默扫描，不显示 loading
            lastLibraryVersion = photoLibrary.libraryVersion
            await scanInBackground(using: photoLibrary)
        } else {
            // 首次：需要显示进度
            await analyze(using: photoLibrary)
        }

        return hasCachedData
    }

    /// 强制全量重扫（用于手动刷新按钮）
    func forceRescan(using photoLibrary: PhotoLibraryService) async {
        lastLibraryVersion = -1
        await analyze(using: photoLibrary)
    }

    /// 带进度的全量扫描
    private func analyze(using photoLibrary: PhotoLibraryService) async {
        isAnalyzing = true
        progress = 0
        defer {
            isAnalyzing = false
            lastLibraryVersion = photoLibrary.libraryVersion
        }

        let newStats = await performScan(using: photoLibrary, reportProgress: true)
        stats = newStats
        stats.save()
        progress = 1.0
    }

    /// 后台静默扫描（不更新 isAnalyzing/progress）
    private func scanInBackground(using photoLibrary: PhotoLibraryService) async {
        let newStats = await performScan(using: photoLibrary, reportProgress: false)
        stats = newStats
        stats.save()
    }

    /// 实际扫描逻辑，在后台线程执行重计算
    private func performScan(using photoLibrary: PhotoLibraryService, reportProgress: Bool) async -> StorageStats {
        // PHFetchResult 获取很快（惰性），在主线程执行即可
        let allAssets = photoLibrary.fetchAllAssets()
        let total = allAssets.count

        guard total > 0 else {
            var empty = StorageStats()
            empty.lastAnalyzedAt = .now
            return empty
        }

        // 将重计算移到后台线程：分批遍历 asset 获取 fileSize，用 autoreleasepool 控制内存
        let batchSize = 500
        let reportEvery = max(total / 20, batchSize) // 最多报告 20 次进度

        let result = await Task.detached(priority: .userInitiated) { [reportProgress] () -> StorageStats in
            var stats = StorageStats()

            for batchStart in stride(from: 0, to: total, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, total)
                autoreleasepool {
                    for i in batchStart..<batchEnd {
                        let asset = allAssets.object(at: i)
                        let size = photoLibrary.fileSize(for: asset)

                        switch asset.mediaType {
                        case .video:
                            stats.totalVideoCount += 1
                            stats.videoSize += size
                        case .image:
                            if asset.mediaSubtypes.contains(.photoScreenshot) {
                                stats.totalScreenshotCount += 1
                                stats.screenshotSize += size
                            } else {
                                stats.totalPhotoCount += 1
                                stats.photoSize += size
                                if asset.burstIdentifier != nil {
                                    stats.totalBurstCount += 1
                                }
                                if asset.mediaSubtypes.contains(.photoLive) {
                                    stats.totalLivePhotoCount += 1
                                }
                            }
                        default:
                            break
                        }
                    }
                }

                // 定期让出 CPU，避免完全阻塞
                if batchEnd % reportEvery == 0 || batchEnd == total {
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }

            stats.estimatedSavable = stats.screenshotSize + Int64(Double(stats.photoSize) * 0.1)
            stats.lastAnalyzedAt = .now
            return stats
        }.value

        return result
    }
}
