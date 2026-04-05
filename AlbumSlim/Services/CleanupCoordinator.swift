import Foundation
import Photos
import Vision

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

    /// 执行删除，分批进行避免卡死
    func executeCleanup(groups: [CleanupGroup]) async throws -> Int64 {
        var freedSize: Int64 = 0

        // 收集所有要删除的 asset
        var allAssetsToDelete: [(asset: PHAsset, size: Int64)] = []
        for group in groups {
            let itemsInGroup = group.items
            if let bestID = group.bestItemID {
                for item in itemsInGroup where item.id != bestID {
                    allAssetsToDelete.append((asset: item.asset, size: item.fileSize))
                }
            } else {
                for item in itemsInGroup {
                    allAssetsToDelete.append((asset: item.asset, size: item.fileSize))
                }
            }
        }

        // 分批删除，每批 50 个
        let deleteBatchSize = 50
        for batchStart in stride(from: 0, to: allAssetsToDelete.count, by: deleteBatchSize) {
            let batchEnd = min(batchStart + deleteBatchSize, allAssetsToDelete.count)
            let batch = allAssetsToDelete[batchStart..<batchEnd]
            let batchAssets = batch.map(\.asset)
            let batchSize = batch.reduce(Int64(0)) { $0 + $1.size }

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(batchAssets as NSFastEnumeration)
            }
            freedSize += batchSize
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

    /// 纯分析：废片检测 + 特征向量提取，写入 SwiftData 缓存，支持断点续传
    /// 后台安全：不持有 CleanupGroup / PHAsset 引用
    /// - Parameter cancelFlag: 外部可设为 true 以请求停止
    func backgroundAnalyze(services: AppServiceContainer, cancelFlag: UnsafeMutablePointer<Bool>? = nil) async {
        let photoLibrary = services.photoLibrary
        let engine = services.aiEngine
        let cache = services.analysisCache
        let batchSize = AppConstants.Analysis.batchSize
        let thumbSize = CGSize(width: 300, height: 300)

        // 加载或创建进度
        var progress = ScanProgress.load() ?? ScanProgress()

        // 相册版本变了，重置进度
        if progress.libraryVersion != photoLibrary.libraryVersion {
            progress = ScanProgress()
            progress.libraryVersion = photoLibrary.libraryVersion
        }

        guard progress.phase != .done else { return }

        // Phase 1: 废片检测
        if progress.phase == .waste {
            scanPhase = .waste
            scanProgress = 0

            let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
            let photoTotal = photoFetch.count

            for batchStart in stride(from: 0, to: photoTotal, by: batchSize) {
                if cancelFlag?.pointee == true { progress.save(); return }

                let batchEnd = min(batchStart + batchSize, photoTotal)
                var batchIDs: [String] = []

                autoreleasepool {
                    for i in batchStart..<batchEnd {
                        let asset = photoFetch.object(at: i)
                        let assetID = asset.localIdentifier
                        batchIDs.append(assetID)
                    }
                }

                // 跳过已处理的
                let cachedIDs = cache.cachedAssetIDs(from: batchIDs)
                for i in batchStart..<batchEnd {
                    if cancelFlag?.pointee == true { progress.save(); return }

                    let asset = photoFetch.object(at: i)
                    let assetID = asset.localIdentifier
                    if cachedIDs.contains(assetID) || progress.processedAssetIDs.contains(assetID) {
                        continue
                    }

                    if let image = await photoLibrary.thumbnail(for: asset, size: thumbSize) {
                        let result = autoreleasepool { engine.detectWaste(image: image) }
                        cache.saveWasteResult(assetID: assetID, isWaste: result.isWaste, reason: result.reason)
                    }
                    progress.processedAssetIDs.insert(assetID)
                }
                cache.batchSave()
                scanProgress = Double(batchEnd) / Double(photoTotal) * 0.5
                progress.lastUpdatedAt = .now
                progress.save()
                await Task.yield()
            }

            // 进入下一阶段
            progress.phase = .similar
            progress.processedAssetIDs.removeAll()
            progress.save()
        }

        // Phase 2: 特征向量提取
        if progress.phase == .similar {
            scanPhase = .similar
            let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
            let photoTotal = photoFetch.count

            for batchStart in stride(from: 0, to: photoTotal, by: batchSize) {
                if cancelFlag?.pointee == true { progress.save(); return }

                let batchEnd = min(batchStart + batchSize, photoTotal)

                for i in batchStart..<batchEnd {
                    if cancelFlag?.pointee == true { progress.save(); return }

                    let asset = photoFetch.object(at: i)
                    let assetID = asset.localIdentifier

                    if progress.processedAssetIDs.contains(assetID) { continue }
                    if cache.featurePrintData(for: assetID) != nil {
                        progress.processedAssetIDs.insert(assetID)
                        continue
                    }

                    if let image = await photoLibrary.thumbnail(for: asset, size: thumbSize) {
                        if let cgImage = image.cgImage {
                            let fp: VNFeaturePrintObservation? = autoreleasepool {
                                engine.featurePrint(for: cgImage)
                            }
                            if let fp, let data = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true) {
                                cache.saveFeaturePrint(assetID: assetID, data: data)
                            }
                        }
                    }
                    progress.processedAssetIDs.insert(assetID)
                }
                cache.batchSave()
                scanProgress = 0.5 + Double(batchEnd) / Double(photoTotal) * 0.5
                progress.lastUpdatedAt = .now
                progress.save()
                await Task.yield()
            }

            progress.phase = .done
            progress.save()
        }

        scanPhase = .done
        scanProgress = 1.0
    }

    /// 从缓存构建清理分组（前台使用，读取 backgroundAnalyze 的缓存结果）
    func buildCleanupGroups(services: AppServiceContainer) async -> [CleanupGroup] {
        var allGroups: [CleanupGroup] = []
        let photoLibrary = services.photoLibrary
        let cache = services.analysisCache

        // 1. 废片（从缓存读取）
        let wasteIDs = cache.allCachedWasteIDs()
        if !wasteIDs.isEmpty {
            let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
            var wasteItems: [MediaItem] = []
            let batchSize = AppConstants.Analysis.batchSize
            for batchStart in stride(from: 0, to: photoFetch.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, photoFetch.count)
                autoreleasepool {
                    for i in batchStart..<batchEnd {
                        let asset = photoFetch.object(at: i)
                        if wasteIDs.contains(asset.localIdentifier) {
                            let size = photoLibrary.fileSize(for: asset)
                            wasteItems.append(MediaItem(
                                id: asset.localIdentifier,
                                asset: asset,
                                fileSize: size,
                                creationDate: asset.creationDate
                            ))
                        }
                    }
                }
            }
            if !wasteItems.isEmpty {
                allGroups.append(CleanupGroup(type: .waste, items: wasteItems, bestItemID: nil))
            }
        }

        // 2. 相似照片（利用缓存的特征向量，计算极快）
        let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
        let allPhotoItems = await photoLibrary.buildMediaItems(from: photoFetch)
        let similarGroups = await services.imageSimilarity.findSimilarGroups(
            from: allPhotoItems,
            using: photoLibrary,
            cache: cache,
            onProgress: { _ in }
        )
        allGroups.append(contentsOf: similarGroups)

        // 3. 连拍
        let burstFetch = photoLibrary.fetchBurstAssets()
        let burstItems = await photoLibrary.buildMediaItems(from: burstFetch)
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

        // 4. 大视频 (>100MB)
        let videoFetch = photoLibrary.fetchAllAssets(mediaType: .video)
        let largeVideoThreshold: Int64 = 100 * 1024 * 1024
        var largeVideos: [MediaItem] = []
        let batchSize = AppConstants.Analysis.batchSize
        for batchStart in stride(from: 0, to: videoFetch.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, videoFetch.count)
            autoreleasepool {
                for i in batchStart..<batchEnd {
                    let asset = videoFetch.object(at: i)
                    let size = photoLibrary.fileSize(for: asset)
                    if size > largeVideoThreshold {
                        largeVideos.append(MediaItem(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: size,
                            creationDate: asset.creationDate
                        ))
                    }
                }
            }
        }
        if !largeVideos.isEmpty {
            allGroups.append(CleanupGroup(type: .largeVideo, items: largeVideos, bestItemID: nil))
        }

        return allGroups
    }

    func smartScan(services: AppServiceContainer) async -> [CleanupGroup] {
        clearAll()

        // Phase 1: 分析（写缓存，支持断点续传）
        await backgroundAnalyze(services: services)

        // Phase 2: 组装结果（读缓存，构建 CleanupGroup）
        let allGroups = await buildCleanupGroups(services: services)

        addGroups(allGroups)
        return allGroups
    }

    private func recalculateSavable() {
        totalSavableSize = pendingGroups.reduce(0) { $0 + $1.savableSize }
    }
}
