import Foundation
import Photos
import SwiftUI

@MainActor @Observable
final class ShuffleFeedViewModel {
    private(set) var items: [ShuffleItem] = []
    var authStatus: PHAuthorizationStatus = .notDetermined
    var emptyMessage: String?

    private var fetchResult: PHFetchResult<PHAsset>?
    private var indexQueue = ShuffleIndexQueue(total: 0)
    private let maxItemCount = 80

    private(set) var playedLiveIds: Set<String> = []

    /// thumbnail LRU 缓存（容量 12）
    private var thumbnailCache: [String: UIImage] = [:]
    private var thumbnailCacheOrder: [String] = []

    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    /// 当前正在通过 PHCachingImageManager 预热的 asset IDs
    private var prefetchedFullImageIDs: Set<String> = []

    /// 高清 UIImage 内存缓存（容量 3），命中时 ShufflePhotoView.load() 直接展示高清
    private var fullImageCache: [String: UIImage] = [:]
    private var fullImageCacheOrder: [String] = []
    private var fullImagePrefetchTasks: [String: Task<Void, Never>] = [:]

    func markLivePlayed(_ assetID: String) { playedLiveIds.insert(assetID) }
    func cachedThumbnail(for assetID: String) -> UIImage? { thumbnailCache[assetID] }
    func cachedFullImage(for assetID: String) -> UIImage? { fullImageCache[assetID] }

    func bootstrap(services: AppServiceContainer) async {
        // 幂等：已初始化完成则直接返回，避免切 tab 回来时清空 items 导致 scrolledID 失效
        if fetchResult != nil, !items.isEmpty { return }

        let status = await services.photoLibrary.requestAuthorization()
        authStatus = status
        guard status == .authorized || status == .limited else { return }

        let result = services.photoLibrary.fetchAllAssets(mediaType: nil)
        guard result.count > 0 else {
            emptyMessage = String(localized: "相册为空，去拍几张吧")
            return
        }
        self.fetchResult = result
        self.indexQueue = ShuffleIndexQueue(total: result.count)
        items.removeAll(keepingCapacity: true)
        appendNext(count: 5)
    }

    /// 维护 thumbnail 预热窗口（prev 1 + next 2）+ 下一张全图 PHCachingImageManager 热身 + 当前/下一张 UIImage 内存预加载
    func updatePrefetchWindow(around currentID: ShuffleItem.ID?, services: AppServiceContainer) {
        guard let currentID,
              let currentIdx = items.firstIndex(where: { $0.id == currentID }) else { return }

        // --- thumbnail 预热 ---
        var desiredAssets: [String: PHAsset] = [:]
        for offset in AppConstants.Shuffle.prefetchOffsets {
            let idx = currentIdx + offset
            guard idx >= 0, idx < items.count else { continue }
            let it = items[idx]
            guard it.kind == .photo || it.kind == .livePhoto else { continue }
            desiredAssets[it.asset.localIdentifier] = it.asset
        }

        for (id, task) in prefetchTasks where desiredAssets[id] == nil {
            task.cancel()
            prefetchTasks.removeValue(forKey: id)
        }
        for (id, asset) in desiredAssets
        where thumbnailCache[id] == nil && prefetchTasks[id] == nil {
            prefetchTasks[id] = Task { [weak self] in
                let thumb = await services.photoLibrary.thumbnail(
                    for: asset, size: AppConstants.Shuffle.thumbnailSize, contentMode: .aspectFit
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.prefetchTasks.removeValue(forKey: id)
                    if let thumb { self.storeThumbnail(thumb, for: id) }
                }
            }
        }

        // --- 全图 PHCachingImageManager 热身（仅下一张 photo，只用本地缓存）---
        var newPrefetchIDs: Set<String> = []
        let nextIdx = currentIdx + 1
        if nextIdx < items.count {
            let next = items[nextIdx]
            if next.kind == .photo { newPrefetchIDs.insert(next.asset.localIdentifier) }
        }

        let toStop = prefetchedFullImageIDs.subtracting(newPrefetchIDs)
        let toStart = newPrefetchIDs.subtracting(prefetchedFullImageIDs)
        let targetSize = AppConstants.Shuffle.fullImageTargetSize

        let stopAssets = toStop.compactMap { id in items.first(where: { $0.asset.localIdentifier == id })?.asset }
        if !stopAssets.isEmpty { services.photoLibrary.stopPrefetchingImages(for: stopAssets, targetSize: targetSize) }

        let startAssets = toStart.compactMap { id in items.first(where: { $0.asset.localIdentifier == id })?.asset }
        if !startAssets.isEmpty { services.photoLibrary.startPrefetchingImages(for: startAssets, targetSize: targetSize) }

        prefetchedFullImageIDs = newPrefetchIDs

        // --- 真正预加载 UIImage 到内存（当前 + 下一张 photo）---
        var desiredFullImage: [String: PHAsset] = [:]
        for offset in [0, 1] {
            let idx = currentIdx + offset
            guard idx >= 0, idx < items.count else { continue }
            let it = items[idx]
            guard it.kind == .photo else { continue }
            desiredFullImage[it.asset.localIdentifier] = it.asset
        }

        for (id, task) in fullImagePrefetchTasks where desiredFullImage[id] == nil {
            task.cancel()
            fullImagePrefetchTasks.removeValue(forKey: id)
        }
        for (id, asset) in desiredFullImage
        where fullImageCache[id] == nil && fullImagePrefetchTasks[id] == nil {
            fullImagePrefetchTasks[id] = Task { [weak self] in
                let image = await services.photoLibrary.loadFullImage(
                    for: asset, size: targetSize
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.fullImagePrefetchTasks.removeValue(forKey: id)
                    if let image { self.storeFullImage(image, for: id) }
                }
            }
        }
    }

    func onPageAppeared(itemID: ShuffleItem.ID?) {
        guard let itemID else { return }
        guard let currentIdx = items.firstIndex(where: { $0.id == itemID }) else { return }
        let remainingAhead = items.count - 1 - currentIdx
        if remainingAhead < 3 { appendNext(count: 3) }
        if items.count > maxItemCount {
            let dropCount = items.count - maxItemCount + 20
            if currentIdx > dropCount + 5 {
                let dropped = items[0..<dropCount]
                items.removeFirst(dropCount)
                for it in dropped { evictAll(for: it.asset.localIdentifier) }
            }
        }
    }

    func remove(itemID: ShuffleItem.ID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        let removed = items[idx]
        items.remove(at: idx)
        indexQueue.remove(fetchIndex: removed.fetchIndex)
        evictAll(for: removed.asset.localIdentifier)
        if items.count < 5 { appendNext(count: 5) }
    }

    func refreshAfterLibraryChange(services: AppServiceContainer) async {
        let ids = items.map { $0.asset.localIdentifier }
        guard !ids.isEmpty else { return }
        let existing = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var aliveIDs: Set<String> = []
        existing.enumerateObjects { asset, _, _ in aliveIDs.insert(asset.localIdentifier) }
        let removed = items.filter { !aliveIDs.contains($0.asset.localIdentifier) }
        items.removeAll { !aliveIDs.contains($0.asset.localIdentifier) }
        for it in removed {
            indexQueue.remove(fetchIndex: it.fetchIndex)
            evictAll(for: it.asset.localIdentifier)
        }
        if items.count < 5 { appendNext(count: 5) }
    }

    // MARK: - Private

    private func appendNext(count: Int) {
        guard let fetchResult else { return }
        for _ in 0..<count {
            let next: Int?
            if items.isEmpty { next = indexQueue.current ?? indexQueue.advance() }
            else { next = indexQueue.advance() }
            guard let fetchIndex = next, fetchIndex < fetchResult.count else { break }
            let asset = fetchResult.object(at: fetchIndex)
            items.append(ShuffleItem(asset: asset, fetchIndex: fetchIndex))
        }
    }

    private func storeThumbnail(_ image: UIImage, for id: String) {
        if thumbnailCache[id] == nil { thumbnailCacheOrder.append(id) }
        thumbnailCache[id] = image
        while thumbnailCacheOrder.count > AppConstants.Shuffle.thumbnailCacheCapacity {
            let oldest = thumbnailCacheOrder.removeFirst()
            thumbnailCache.removeValue(forKey: oldest)
        }
    }

    private func storeFullImage(_ image: UIImage, for id: String) {
        if fullImageCache[id] == nil { fullImageCacheOrder.append(id) }
        fullImageCache[id] = image
        while fullImageCacheOrder.count > AppConstants.Shuffle.fullImageCacheCapacity {
            let oldest = fullImageCacheOrder.removeFirst()
            fullImageCache.removeValue(forKey: oldest)
        }
    }

    /// 一次性清理某个 asset 相关的所有缓存与在途任务（thumbnail + full image + prefetch tasks）。
    private func evictAll(for id: String) {
        thumbnailCache.removeValue(forKey: id)
        thumbnailCacheOrder.removeAll { $0 == id }
        prefetchTasks[id]?.cancel()
        prefetchTasks.removeValue(forKey: id)
        fullImageCache.removeValue(forKey: id)
        fullImageCacheOrder.removeAll { $0 == id }
        fullImagePrefetchTasks[id]?.cancel()
        fullImagePrefetchTasks.removeValue(forKey: id)
    }
}
