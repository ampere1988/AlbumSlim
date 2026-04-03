import Foundation
import Photos

@MainActor @Observable
final class CleanupCoordinator {
    private(set) var pendingGroups: [CleanupGroup] = []
    private(set) var totalSavableSize: Int64 = 0

    func addGroups(_ groups: [CleanupGroup]) {
        pendingGroups.append(contentsOf: groups)
        recalculateSavable()
    }

    func removeGroup(_ group: CleanupGroup) {
        pendingGroups.removeAll { $0.id == group.id }
        recalculateSavable()
    }

    func clearAll() {
        pendingGroups.removeAll()
        totalSavableSize = 0
    }

    /// 执行删除，返回实际释放的空间大小
    func executeCleanup(groups: [CleanupGroup]) async throws -> Int64 {
        var freedSize: Int64 = 0

        for group in groups {
            let assetsToDelete: [PHAsset]
            if let bestID = group.bestItemID {
                assetsToDelete = group.items.filter { $0.id != bestID }.map(\.asset)
            } else {
                assetsToDelete = group.items.map(\.asset)
            }

            let itemsInGroup = group.items
            let sizeToFree = assetsToDelete.reduce(Int64(0)) { total, asset in
                let matchingItem = itemsInGroup.first { $0.asset == asset }
                return total + (matchingItem?.fileSize ?? 0)
            }

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSFastEnumeration)
            }

            freedSize += sizeToFree
        }

        // 清理已执行的分组
        let executedIDs = Set(groups.map(\.id))
        pendingGroups.removeAll { executedIDs.contains($0.id) }
        recalculateSavable()

        return freedSize
    }

    // MARK: - 智能扫描

    enum ScanPhase: String {
        case waste = "检测废片..."
        case similar = "查找相似照片..."
        case burst = "分析连拍照片..."
        case largeVideo = "查找大视频..."
        case done = "扫描完成"
    }

    private(set) var scanPhase: ScanPhase = .done
    private(set) var scanProgress: Double = 0

    func smartScan(services: AppServiceContainer) async -> [CleanupGroup] {
        clearAll()
        var allGroups: [CleanupGroup] = []
        let photoLibrary = services.photoLibrary
        let engine = services.aiEngine
        let cache = services.analysisCache

        // 1. 废片检测
        scanPhase = .waste
        scanProgress = 0
        let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
        let photoItems = photoLibrary.buildMediaItems(from: photoFetch)
        let thumbSize = CGSize(width: 300, height: 300)
        var wasteItems: [MediaItem] = []
        let batchSize = AppConstants.Analysis.batchSize

        // 获取已缓存的 asset IDs
        let allAssetIDs = photoItems.map { $0.asset.localIdentifier }
        let cachedIDs = cache.cachedAssetIDs(from: allAssetIDs)

        for batchStart in stride(from: 0, to: photoItems.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, photoItems.count)
            for index in batchStart..<batchEnd {
                let item = photoItems[index]
                let assetID = item.asset.localIdentifier

                // 检查缓存
                if cachedIDs.contains(assetID) {
                    if let cached = cache.cachedAnalysis(for: assetID), cached.isWaste {
                        wasteItems.append(item)
                    }
                    continue
                }

                if let image = await photoLibrary.thumbnail(for: item.asset, size: thumbSize) {
                    let result = autoreleasepool {
                        engine.detectWaste(image: image)
                    }
                    cache.saveWasteResult(assetID: assetID, isWaste: result.isWaste, reason: result.reason)
                    if result.isWaste {
                        wasteItems.append(item)
                    }
                }
            }
            scanProgress = Double(batchEnd) / Double(photoItems.count) * 0.3
        }
        if !wasteItems.isEmpty {
            allGroups.append(CleanupGroup(type: .waste, items: wasteItems, bestItemID: nil))
        }

        // 2. 相似照片检测
        scanPhase = .similar
        let similarGroups = await services.imageSimilarity.findSimilarGroups(
            from: photoItems,
            using: photoLibrary,
            cache: cache,
            onProgress: { [weak self] p in
                self?.scanProgress = 0.3 + p * 0.4
            }
        )
        allGroups.append(contentsOf: similarGroups)

        // 3. 连拍照片检测
        scanPhase = .burst
        scanProgress = 0.7
        let burstFetch = photoLibrary.fetchBurstAssets()
        let burstItems = photoLibrary.buildMediaItems(from: burstFetch)
        var burstMap: [String: [MediaItem]] = [:]
        for item in burstItems {
            if let burstID = item.asset.burstIdentifier {
                burstMap[burstID, default: []].append(item)
            }
        }
        let burstGroups = burstMap.values
            .filter { $0.count > 1 }
            .map { items in
                let best = items.max(by: { $0.fileSize < $1.fileSize })
                return CleanupGroup(type: .burst, items: items, bestItemID: best?.id)
            }
        allGroups.append(contentsOf: burstGroups)

        // 4. 大视频检测 (>100MB)
        scanPhase = .largeVideo
        scanProgress = 0.85
        let videoFetch = photoLibrary.fetchAllAssets(mediaType: .video)
        let videoItems = photoLibrary.buildMediaItems(from: videoFetch)
        let largeVideoThreshold: Int64 = 100 * 1024 * 1024
        let largeVideos = videoItems.filter { $0.fileSize > largeVideoThreshold }
        if !largeVideos.isEmpty {
            allGroups.append(CleanupGroup(type: .largeVideo, items: largeVideos, bestItemID: nil))
        }

        scanPhase = .done
        scanProgress = 1.0
        addGroups(allGroups)
        return allGroups
    }

    private func recalculateSavable() {
        totalSavableSize = pendingGroups.reduce(0) { $0 + $1.savableSize }
    }
}
