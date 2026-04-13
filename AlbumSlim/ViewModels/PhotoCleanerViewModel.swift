import Foundation

@MainActor @Observable
final class PhotoCleanerViewModel {
    var similarGroups: [CleanupGroup] = []
    var wasteItems: [MediaItem] = []
    var isScanning = false
    var scanProgress: Double = 0
    var selectedForDeletion: Set<String> = []
    var wasteReasons: [String: WasteReason] = [:]

    func toggleSelection(_ itemID: String) {
        if selectedForDeletion.contains(itemID) {
            selectedForDeletion.remove(itemID)
        } else {
            selectedForDeletion.insert(itemID)
        }
    }

    func selectAllExceptBest(in group: CleanupGroup) {
        for item in group.items {
            if item.id != group.bestItemID {
                selectedForDeletion.insert(item.id)
            } else {
                selectedForDeletion.remove(item.id)
            }
        }
    }

    func deleteSelected(services: AppServiceContainer) async throws -> Int64 {
        let allItems = similarGroups.flatMap(\.items) + wasteItems
        let toDelete = allItems.filter { selectedForDeletion.contains($0.id) }
        guard !toDelete.isEmpty else { return 0 }

        let freedSize = toDelete.reduce(Int64(0)) { $0 + $1.fileSize }
        let assets = toDelete.map(\.asset)
        try await services.photoLibrary.deleteAssets(assets)

        let _ = services.achievement.recordCleanup(freedSpace: freedSize, deletedCount: toDelete.count)
        let deletedIDs = selectedForDeletion
        similarGroups = similarGroups.compactMap { group in
            var g = group
            g.items.removeAll { deletedIDs.contains($0.id) }
            return g.items.count > 1 ? g : nil
        }
        wasteItems.removeAll { deletedIDs.contains($0.id) }
        for id in deletedIDs { wasteReasons.removeValue(forKey: id) }
        selectedForDeletion.removeAll()

        return freedSize
    }

    func scanSimilarPhotos(services: AppServiceContainer) async {
        let coordinator = services.cleanupCoordinator
        if coordinator.isScanFresh {
            let cached = coordinator.groups(ofType: .similar)
            if !cached.isEmpty {
                similarGroups = cached
                return
            }
        }

        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let items = await services.photoLibrary.buildMediaItems(from: fetchResult)

        similarGroups = await services.imageSimilarity.findSimilarGroups(
            from: items,
            using: services.photoLibrary,
            cache: services.analysisCache,
            onProgress: { [weak self] progress in
                self?.scanProgress = progress
            }
        )

        coordinator.addGroups(similarGroups)
        scanProgress = 1.0
    }

    func scanWastePhotos(services: AppServiceContainer) async {
        let coordinator = services.cleanupCoordinator
        if coordinator.isScanFresh {
            let cached = coordinator.groups(ofType: .waste)
            let cachedItems = cached.flatMap(\.items)
            if !cachedItems.isEmpty {
                wasteItems = cachedItems
                wasteReasons = coordinator.wasteReasons
                return
            }
        }

        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let total = fetchResult.count
        guard total > 0 else { return }

        let engine = services.aiEngine
        let library = services.photoLibrary
        let cache = services.analysisCache
        let thumbSize = CGSize(width: 300, height: 300)
        let batchSize = AppConstants.Analysis.batchSize

        var waste: [MediaItem] = []

        // 从 PHFetchResult 分批提取 asset，不一次性创建全部 MediaItem
        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)

            // 当前批次：从 fetchResult 提取 asset，构建轻量 MediaItem
            var batchItems: [MediaItem] = []
            autoreleasepool {
                for i in batchStart..<batchEnd {
                    let asset = fetchResult.object(at: i)
                    let size = library.fileSize(for: asset)
                    batchItems.append(MediaItem(
                        id: asset.localIdentifier,
                        asset: asset,
                        fileSize: size,
                        creationDate: asset.creationDate
                    ))
                }
            }

            // 批量查询缓存
            let batchIDs = batchItems.map(\.id)
            let cachedIDs = cache.cachedAssetIDs(from: batchIDs)

            for item in batchItems {
                let assetID = item.id

                if cachedIDs.contains(assetID) {
                    if let cached = cache.cachedAnalysis(for: assetID), cached.isWaste {
                        waste.append(item)
                        if let reason = cached.wasteReason {
                            wasteReasons[item.id] = reason
                        }
                    }
                    continue
                }

                if let image = await library.thumbnail(for: item.asset, size: thumbSize) {
                    let result = autoreleasepool {
                        engine.detectWaste(image: image)
                    }
                    cache.saveWasteResult(assetID: assetID, isWaste: result.isWaste, reason: result.reason)
                    if result.isWaste {
                        waste.append(item)
                        if let reason = result.reason {
                            wasteReasons[item.id] = reason
                        }
                    }
                }
            }

            cache.batchSave()
            scanProgress = Double(batchEnd) / Double(total)
            await Task.yield()
        }

        wasteItems = waste
        scanProgress = 1.0

        let wasteGroup = CleanupGroup(type: .waste, items: waste, bestItemID: nil)
        services.cleanupCoordinator.addGroups([wasteGroup])
    }
}
