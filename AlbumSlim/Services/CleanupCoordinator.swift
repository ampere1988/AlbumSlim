import Foundation
import Photos
import Vision

@MainActor @Observable
final class CleanupCoordinator {
    private(set) var pendingGroups: [CleanupGroup] = []
    private(set) var totalSavableSize: Int64 = 0
    private(set) var wasteReasons: [String: WasteReason] = [:]

    /// 按分类记录上次扫描时的相册版本号，相册未变则缓存有效（持久化到 UserDefaults）
    private var scannedVersions: [CleanupGroup.GroupType: Int] = [:] {
        didSet { persistScannedVersions() }
    }

    private static let scannedVersionsKey = "CleanupCoordinator.scannedVersions"

    func isCategoryFresh(_ type: CleanupGroup.GroupType, libraryVersion: Int) -> Bool {
        scannedVersions[type] == libraryVersion
    }

    /// 所有分类是否都与当前相册版本一致
    func isAllCategoriesFresh(libraryVersion: Int) -> Bool {
        let allTypes: [CleanupGroup.GroupType] = [.waste, .similar, .burst, .largePhoto, .largeVideo]
        return allTypes.allSatisfy { isCategoryFresh($0, libraryVersion: libraryVersion) }
    }

    /// 返回相册版本变更后需要重扫的分类列表
    func staleCategoryTypes(libraryVersion: Int) -> [CleanupGroup.GroupType] {
        let allTypes: [CleanupGroup.GroupType] = [.waste, .similar, .burst, .largePhoto, .largeVideo]
        return allTypes.filter { !isCategoryFresh($0, libraryVersion: libraryVersion) }
    }

    func markCategoryScanned(_ type: CleanupGroup.GroupType, libraryVersion: Int) {
        scannedVersions[type] = libraryVersion
    }

    func restoreScannedVersions() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.scannedVersionsKey) as? [String: Int] else { return }
        var restored: [CleanupGroup.GroupType: Int] = [:]
        for (key, value) in dict {
            if let type = CleanupGroup.GroupType(rawValue: key) {
                restored[type] = value
            }
        }
        scannedVersions = restored
    }

    private func persistScannedVersions() {
        let dict = Dictionary(uniqueKeysWithValues: scannedVersions.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(dict, forKey: Self.scannedVersionsKey)
    }

    func groups(ofType type: CleanupGroup.GroupType) -> [CleanupGroup] {
        pendingGroups.filter { $0.type == type }
    }

    func addGroups(_ groups: [CleanupGroup]) {
        // 按类型去重：先移除同类型旧组，再追加新组
        let incomingTypes = Set(groups.map(\.type))
        pendingGroups.removeAll { incomingTypes.contains($0.type) }
        pendingGroups.append(contentsOf: groups)
        recalculateSavable()
        persistGroupSkeletons()
    }

    func removeGroup(_ group: CleanupGroup) {
        pendingGroups.removeAll { $0.id == group.id }
        recalculateSavable()
        persistGroupSkeletons()
    }

    func clearAll() {
        pendingGroups.removeAll()
        totalSavableSize = 0
        scannedVersions.removeAll()
        persistGroupSkeletons()
    }

    // MARK: - 分组骨架持久化

    /// 轻量骨架：存 asset ID、分组类型、文件大小和日期，恢复时不再重新计算
    private struct GroupSkeleton: Codable {
        let type: String
        let assetIDs: [String]
        let bestItemID: String?
        let fileSizes: [Int64]?
        let creationDates: [Date?]?
    }

    private static let groupSkeletonsKey = "CleanupCoordinator.groupSkeletons"

    private func persistGroupSkeletons() {
        let skeletons = pendingGroups.map { group in
            GroupSkeleton(
                type: group.type.rawValue,
                assetIDs: group.items.map(\.id),
                bestItemID: group.bestItemID,
                fileSizes: group.items.map(\.fileSize),
                creationDates: group.items.map(\.creationDate)
            )
        }
        guard let data = try? JSONEncoder().encode(skeletons) else { return }
        UserDefaults.standard.set(data, forKey: Self.groupSkeletonsKey)
    }

    /// 从持久化骨架恢复分组，通过 PHAsset.localIdentifier 重建完整对象
    /// 使用缓存的文件大小避免重新计算，异步执行不阻塞主线程
    func restoreGroups(using photoLibrary: PhotoLibraryService) async {
        guard let data = UserDefaults.standard.data(forKey: Self.groupSkeletonsKey),
              let skeletons = try? JSONDecoder().decode([GroupSkeleton].self, from: data),
              !skeletons.isEmpty else { return }

        // 收集所有需要的 asset ID，批量 fetch
        let allIDs = skeletons.flatMap(\.assetIDs)
        guard !allIDs.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)
        var assetMap: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }

        var restored: [CleanupGroup] = []
        for skeleton in skeletons {
            guard let type = CleanupGroup.GroupType(rawValue: skeleton.type) else { continue }
            var items: [MediaItem] = []
            let cachedSizes = skeleton.fileSizes
            let cachedDates = skeleton.creationDates
            for (index, assetID) in skeleton.assetIDs.enumerated() {
                guard let asset = assetMap[assetID] else { continue }
                let size = cachedSizes?[safe: index] ?? photoLibrary.fileSize(for: asset)
                let date = cachedDates?[safe: index] ?? asset.creationDate
                items.append(MediaItem(
                    id: assetID,
                    asset: asset,
                    fileSize: size,
                    creationDate: date
                ))
            }
            // 跳过因删除导致不足 2 项的相似/连拍组
            if (type == .similar || type == .burst) && items.count < 2 { continue }
            if items.isEmpty { continue }
            restored.append(CleanupGroup(type: type, items: items, bestItemID: skeleton.bestItemID))
        }

        if !restored.isEmpty {
            pendingGroups = restored
            recalculateSavable()
        }
    }

    /// 执行删除，分批进行避免卡死
    func executeCleanup(groups: [CleanupGroup], photoLibrary: PhotoLibraryService) async throws -> Int64 {
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

            // 走 photoLibrary.deleteAssets（已经标 nonisolated），避免 @MainActor 类的
            // performChanges 闭包隐式隔离到主线程触发 _dispatch_assert_queue_fail
            try await photoLibrary.deleteAssets(batchAssets)
            freedSize += batchSize
        }

        // 清理已执行的分组
        let executedIDs = Set(groups.map(\.id))
        pendingGroups.removeAll { executedIDs.contains($0.id) }
        recalculateSavable()
        persistGroupSkeletons()

        return freedSize
    }

    // MARK: - 智能扫描

    enum ScanPhase: String {
        case waste = "检测废片..."
        case similar = "查找相似照片..."
        case burst = "分析连拍照片..."
        case largeVideo = "查找大视频..."
        case building = "正在整理结果..."
        case done = "扫描完成"

        var localizedName: String {
            switch self {
            case .waste:      return String(localized: "检测废片...")
            case .similar:    return String(localized: "查找相似照片...")
            case .burst:      return String(localized: "分析连拍照片...")
            case .largeVideo: return String(localized: "查找大视频...")
            case .building:   return String(localized: "正在整理结果...")
            case .done:       return String(localized: "扫描完成")
            }
        }
    }

    private(set) var scanPhase: ScanPhase = .done
    private(set) var scanProgress: Double = 0

    /// 纯分析：废片检测 + 特征向量提取，写入 SwiftData 缓存，支持断点续传
    /// 后台安全：不持有 CleanupGroup / PHAsset 引用
    func backgroundAnalyze(services: AppServiceContainer) async {
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
                if Task.isCancelled { progress.save(); return }

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
                    if Task.isCancelled { progress.save(); return }

                    let asset = photoFetch.object(at: i)
                    let assetID = asset.localIdentifier
                    if cachedIDs.contains(assetID) {
                        continue
                    }

                    if let image = await photoLibrary.thumbnail(for: asset, size: thumbSize) {
                        let result = await Task.detached {
                            autoreleasepool { engine.detectWaste(image: image) }
                        }.value
                        cache.saveWasteResult(assetID: assetID, isWaste: result.isWaste, reason: result.reason)
                    }
                }
                cache.batchSave()
                scanProgress = Double(batchEnd) / Double(photoTotal) * 0.5
                progress.lastUpdatedAt = .now
                progress.save()
                await Task.yield()
            }

            // 进入下一阶段
            progress.phase = .similar
            progress.save()
        }

        // Phase 2: 特征向量提取
        if progress.phase == .similar {
            scanPhase = .similar
            let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
            let photoTotal = photoFetch.count

            for batchStart in stride(from: 0, to: photoTotal, by: batchSize) {
                if Task.isCancelled { progress.save(); return }

                let batchEnd = min(batchStart + batchSize, photoTotal)

                for i in batchStart..<batchEnd {
                    if Task.isCancelled { progress.save(); return }

                    let asset = photoFetch.object(at: i)
                    let assetID = asset.localIdentifier

                    if cache.featurePrintData(for: assetID) != nil { continue }

                    if let image = await photoLibrary.thumbnail(for: asset, size: thumbSize) {
                        if let cgImage = image.cgImage {
                            let fpData: Data? = await Task.detached {
                                autoreleasepool {
                                    guard let fp = engine.featurePrint(for: cgImage) else { return nil as Data? }
                                    return try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
                                }
                            }.value
                            if let fpData {
                                cache.saveFeaturePrint(assetID: assetID, data: fpData)
                            }
                        }
                    }
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

    // MARK: - 按分类构建清理分组

    /// 废片（从 SwiftData 缓存读取）
    private func buildWasteGroups(services: AppServiceContainer) async -> [CleanupGroup] {
        let cache = services.analysisCache
        let photoLibrary = services.photoLibrary
        let batchSize = AppConstants.Analysis.batchSize
        let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)

        wasteReasons = cache.allWasteReasons()
        let wasteIDs = Set(wasteReasons.keys).union(cache.allCachedWasteIDs())
        guard !wasteIDs.isEmpty else { return [] }

        var wasteItems: [MediaItem] = []
        for batchStart in stride(from: 0, to: photoFetch.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, photoFetch.count)
            autoreleasepool {
                for i in batchStart..<batchEnd {
                    let asset = photoFetch.object(at: i)
                    if wasteIDs.contains(asset.localIdentifier) {
                        let size = photoLibrary.fileSize(for: asset)
                        wasteItems.append(MediaItem(
                            id: asset.localIdentifier, asset: asset,
                            fileSize: size, creationDate: asset.creationDate
                        ))
                    }
                }
            }
        }
        guard !wasteItems.isEmpty else { return [] }
        return [CleanupGroup(type: .waste, items: wasteItems, bestItemID: nil)]
    }

    /// 相似照片（利用缓存的特征向量）
    private func buildSimilarGroups(services: AppServiceContainer, photoItems: [MediaItem]? = nil) async -> [CleanupGroup] {
        let photoLibrary = services.photoLibrary
        let items: [MediaItem]
        if let photoItems {
            items = photoItems
        } else {
            let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
            items = await photoLibrary.buildMediaItems(from: photoFetch)
        }
        return await services.imageSimilarity.findSimilarGroups(
            from: items, using: photoLibrary,
            cache: services.analysisCache,
            onProgress: { [weak self] p in self?.scanProgress = 0.2 + p * 0.5 }
        )
    }

    /// 连拍
    private func buildBurstGroups(services: AppServiceContainer) async -> [CleanupGroup] {
        let burstFetch = services.photoLibrary.fetchBurstAssets()
        let burstItems = await services.photoLibrary.buildMediaItems(from: burstFetch)
        var burstMap: [String: [MediaItem]] = [:]
        for item in burstItems {
            if let burstID = item.asset.burstIdentifier {
                burstMap[burstID, default: []].append(item)
            }
        }
        return burstMap.values
            .filter { $0.count > 1 }
            .map { items in
                let best = items.max(by: { $0.fileSize < $1.fileSize })
                return CleanupGroup(type: .burst, items: items, bestItemID: best?.id)
            }
    }

    /// 超大照片 (>10MB)
    private func buildLargePhotoGroups(services: AppServiceContainer, photoItems: [MediaItem]? = nil) async -> [CleanupGroup] {
        let items: [MediaItem]
        if let photoItems {
            items = photoItems
        } else {
            let photoFetch = services.photoLibrary.fetchAllAssets(mediaType: .image)
            items = await services.photoLibrary.buildMediaItems(from: photoFetch)
        }
        let threshold: Int64 = 10 * 1024 * 1024
        let largePhotos = items.filter { $0.fileSize >= threshold }
            .sorted { $0.fileSize > $1.fileSize }
        guard !largePhotos.isEmpty else { return [] }
        return [CleanupGroup(type: .largePhoto, items: largePhotos, bestItemID: nil)]
    }

    /// 大视频 (>100MB)
    private func buildLargeVideoGroups(services: AppServiceContainer) async -> [CleanupGroup] {
        let videoFetch = services.photoLibrary.fetchAllAssets(mediaType: .video)
        let batchSize = AppConstants.Analysis.batchSize
        let threshold: Int64 = 100 * 1024 * 1024
        var largeVideos: [MediaItem] = []
        for batchStart in stride(from: 0, to: videoFetch.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, videoFetch.count)
            autoreleasepool {
                for i in batchStart..<batchEnd {
                    let asset = videoFetch.object(at: i)
                    let size = services.photoLibrary.fileSize(for: asset)
                    if size > threshold {
                        largeVideos.append(MediaItem(
                            id: asset.localIdentifier, asset: asset,
                            fileSize: size, creationDate: asset.creationDate
                        ))
                    }
                }
            }
        }
        guard !largeVideos.isEmpty else { return [] }
        return [CleanupGroup(type: .largeVideo, items: largeVideos, bestItemID: nil)]
    }

    /// 从缓存构建所有分类的清理分组（聚合调用）
    func buildCleanupGroups(services: AppServiceContainer) async -> [CleanupGroup] {
        var allGroups: [CleanupGroup] = []

        // 构建 allPhotoItems 复用，避免 similar 和 largePhoto 重复 fetch
        let photoFetch = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let allPhotoItems = await services.photoLibrary.buildMediaItems(from: photoFetch)

        allGroups.append(contentsOf: await buildWasteGroups(services: services))
        scanProgress = 0.2

        allGroups.append(contentsOf: await buildSimilarGroups(services: services, photoItems: allPhotoItems))
        scanProgress = 0.7

        allGroups.append(contentsOf: await buildBurstGroups(services: services))
        scanProgress = 0.85

        allGroups.append(contentsOf: await buildLargePhotoGroups(services: services, photoItems: allPhotoItems))
        scanProgress = 0.9

        allGroups.append(contentsOf: await buildLargeVideoGroups(services: services))

        return allGroups
    }

    // MARK: - 扫描入口

    /// 全量扫描（不再调用 clearAll，通过 addGroups 按类型去重替换）
    func smartScan(services: AppServiceContainer) async -> [CleanupGroup] {
        // Phase 1: 分析（写缓存，支持断点续传）
        await backgroundAnalyze(services: services)

        // Phase 2: 组装结果（读缓存，构建 CleanupGroup）
        scanPhase = .building
        scanProgress = 0
        let allGroups = await buildCleanupGroups(services: services)

        scanPhase = .done
        scanProgress = 1.0
        addGroups(allGroups)

        // 标记所有分类已扫描到当前相册版本
        let version = services.photoLibrary.libraryVersion
        for type: CleanupGroup.GroupType in [.waste, .similar, .burst, .largePhoto, .largeVideo] {
            markCategoryScanned(type, libraryVersion: version)
        }

        return pendingGroups
    }

    /// 增量扫描：只重扫相册版本变更后"脏"的分类，保留有效缓存
    func incrementalScan(services: AppServiceContainer) async -> [CleanupGroup] {
        let version = services.photoLibrary.libraryVersion
        let staleTypes = staleCategoryTypes(libraryVersion: version)
        guard !staleTypes.isEmpty else { return pendingGroups }

        // 废片/相似需要先执行后台分析
        let needsAnalyze = staleTypes.contains(.waste) || staleTypes.contains(.similar)
        if needsAnalyze {
            await backgroundAnalyze(services: services)
        }

        scanPhase = .building
        scanProgress = 0

        // 复用 photoItems（similar 和 largePhoto 都需要）
        var sharedPhotoItems: [MediaItem]?
        if staleTypes.contains(.similar) || staleTypes.contains(.largePhoto) {
            let photoFetch = services.photoLibrary.fetchAllAssets(mediaType: .image)
            sharedPhotoItems = await services.photoLibrary.buildMediaItems(from: photoFetch)
        }

        var newGroups: [CleanupGroup] = []
        var scannedTypes: [CleanupGroup.GroupType] = []

        if staleTypes.contains(.waste) {
            newGroups.append(contentsOf: await buildWasteGroups(services: services))
            scannedTypes.append(.waste)
        }
        if staleTypes.contains(.similar) {
            newGroups.append(contentsOf: await buildSimilarGroups(services: services, photoItems: sharedPhotoItems))
            scannedTypes.append(.similar)
        }
        if staleTypes.contains(.burst) {
            newGroups.append(contentsOf: await buildBurstGroups(services: services))
            scannedTypes.append(.burst)
        }
        if staleTypes.contains(.largePhoto) {
            newGroups.append(contentsOf: await buildLargePhotoGroups(services: services, photoItems: sharedPhotoItems))
            scannedTypes.append(.largePhoto)
        }
        if staleTypes.contains(.largeVideo) {
            newGroups.append(contentsOf: await buildLargeVideoGroups(services: services))
            scannedTypes.append(.largeVideo)
        }

        // 对扫描后无结果的脏分类，移除旧组
        for type in staleTypes {
            if !newGroups.contains(where: { $0.type == type }) {
                pendingGroups.removeAll { $0.type == type }
            }
        }

        if !newGroups.isEmpty {
            addGroups(newGroups)
        }

        for type in scannedTypes {
            markCategoryScanned(type, libraryVersion: version)
        }

        scanPhase = .done
        scanProgress = 1.0
        persistGroupSkeletons()
        return pendingGroups
    }

    private func recalculateSavable() {
        totalSavableSize = pendingGroups.reduce(0) { $0 + $1.savableSize }
    }
}
