import Foundation
import Photos
import UIKit

@MainActor @Observable
final class PhotoLibraryService: NSObject {
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined

    /// 相册变更版本号，每次相册发生增删改时自增
    private(set) var libraryVersion: Int = 0

    /// 缩略图并发限制，防止同时发起过多图片请求导致内存暴涨
    private let thumbnailSemaphore = AsyncSemaphore(limit: 6)

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    // MARK: - 获取资源

    func fetchAllAssets(mediaType: PHAssetMediaType? = nil) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let mediaType {
            options.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
        }
        return PHAsset.fetchAssets(with: options)
    }

    func fetchScreenshots() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaSubtype & %d != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    func fetchBurstAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "burstIdentifier != nil")
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    // MARK: - 文件大小

    nonisolated func fileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else { return 0 }
        let sizeValue = resource.value(forKey: "fileSize") as? Int64
        return sizeValue ?? 0
    }

    // MARK: - 缩略图

    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await thumbnailSemaphore.wait()
        defer { thumbnailSemaphore.signal() }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - 删除（分批，每批最多 50 个，避免系统弹窗超大列表卡死）

    func deleteAssets(_ assets: [PHAsset]) async throws {
        let batchSize = 50
        for batchStart in stride(from: 0, to: assets.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, assets.count)
            let batch = Array(assets[batchStart..<batchEnd])
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(batch as NSFastEnumeration)
            }
        }
    }

    // MARK: - 构建 MediaItem（异步，后台线程执行 fileSize 获取）

    func buildMediaItems(from fetchResult: PHFetchResult<PHAsset>) async -> [MediaItem] {
        let count = fetchResult.count
        guard count > 0 else { return [] }

        // 先在主线程提取所有 asset 引用（PHFetchResult 访问必须在创建它的线程）
        var assets: [PHAsset] = []
        assets.reserveCapacity(count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        // 在后台线程分批获取 fileSize，避免阻塞主线程
        let batchSize = 200
        return await Task.detached(priority: .utility) {
            var items: [MediaItem] = []
            items.reserveCapacity(count)

            for batchStart in stride(from: 0, to: count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, count)
                autoreleasepool {
                    for i in batchStart..<batchEnd {
                        let asset = assets[i]
                        let size = self.fileSize(for: asset)
                        items.append(MediaItem(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: size,
                            creationDate: asset.creationDate
                        ))
                    }
                }
                // 每批让出 CPU，避免长时间占用
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            return items
        }.value
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.libraryVersion += 1
        }
    }
}
