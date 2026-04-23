import Foundation
import Photos
import UIKit

@MainActor @Observable
final class PhotoLibraryService: NSObject {
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined

    /// 相册指纹：基于照片/视频总数 + 最新修改时间计算，跨重启稳定
    private(set) var libraryVersion: Int = 0

    /// 缩略图并发限制，防止同时发起过多图片请求导致内存暴涨
    private let thumbnailSemaphore = AsyncSemaphore(limit: 6)

    /// 防抖：批量删除时多次 photoLibraryDidChange 合并为一次指纹刷新
    private var versionBumpTask: Task<Void, Never>?

    private static let libraryVersionKey = "PhotoLibraryVersion"

    override init() {
        super.init()
        // 恢复上次保存的指纹，避免首次 computeLibraryFingerprint 前为 0
        libraryVersion = UserDefaults.standard.integer(forKey: Self.libraryVersionKey)
        PHPhotoLibrary.shared().register(self)
    }

    /// 计算相册指纹并更新 libraryVersion（授权后首次调用 + 相册变更时调用）
    func refreshLibraryVersion() {
        let newVersion = computeLibraryFingerprint()
        if newVersion != libraryVersion {
            libraryVersion = newVersion
            UserDefaults.standard.set(newVersion, forKey: Self.libraryVersionKey)
        }
    }

    /// 基于相册内容计算稳定指纹（跨进程确定性，不使用 Hasher）
    private func computeLibraryFingerprint() -> Int {
        let allFetch = PHAsset.fetchAssets(with: nil)
        let count = allFetch.count
        guard count > 0 else { return 0 }

        // 取最新一张的修改日期作为时间戳因子
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        options.fetchLimit = 1
        let latestFetch = PHAsset.fetchAssets(with: options)
        let latestTimestamp = Int(latestFetch.firstObject?.modificationDate?.timeIntervalSince1970 ?? 0)

        // 使用确定性算法替代 Hasher（Hasher 每次进程启动种子不同）
        return count &* 31 &+ latestTimestamp
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            refreshLibraryVersion()
        }
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
        guard !resources.isEmpty else { return 0 }
        return resources.reduce(Int64(0)) { total, resource in
            total + (resource.value(forKey: "fileSize") as? Int64 ?? 0)
        }
    }

    // MARK: - 缩略图

    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await thumbnailSemaphore.wait()
        defer { thumbnailSemaphore.signal() }

        // 在后台线程同步请求，避免 withCheckedContinuation + PHImageManager 回调多次导致 EXC_BREAKPOINT
        return await Task.detached(priority: .userInitiated) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true
            options.resizeMode = .fast
            var result: UIImage?
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: options
            ) { image, _ in
                result = image
            }
            return result
        }.value
    }

    /// 加载原图并上报下载进度。允许 iCloud 下载,progressHandler 在 iCloud 场景会多次回调 0~1;
    /// 本地图片瞬间完成,progress 可能不触发或只触发一次 1.0
    func loadFullImage(
        for asset: PHAsset,
        size: CGSize,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async -> UIImage? {
        await thumbnailSemaphore.wait()
        defer { thumbnailSemaphore.signal() }

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.resizeMode = .fast
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in onProgress(progress) }
            }

            let once = OnceResume()
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: options
            ) { image, info in
                // deliveryMode=.highQualityFormat 下理论上只回调一次,但 iCloud 取消/错误场景仍可能多次触发,加锁保护
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                once.fire { continuation.resume(returning: image) }
            }
        }
    }

    // MARK: - 删除（分批，每批最多 50 个，避免系统弹窗超大列表卡死）

    nonisolated func deleteAssets(_ assets: [PHAsset]) async throws {
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

    func buildMediaItems(from fetchResult: PHFetchResult<PHAsset>, onProgress: (@MainActor (Double) -> Void)? = nil) async -> [MediaItem] {
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
                if let onProgress {
                    await onProgress(Double(batchEnd) / Double(count))
                }
                // 每批让出 CPU，避免长时间占用
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            return items
        }.value
    }
}

// MARK: - 一次性 continuation 保护(防止 PHImageManager 回调多次 resume 崩溃)

private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire(_ block: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        block()
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            // 防抖：批量删除产生多次回调时，合并为一次指纹刷新，
            // 避免中间状态触发视图重载导致 UICollectionView diff 不一致
            self.versionBumpTask?.cancel()
            self.versionBumpTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self.refreshLibraryVersion()
            }
        }
    }
}
