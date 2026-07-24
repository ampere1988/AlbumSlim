import Foundation
import Photos

@MainActor @Observable
final class SwipeCleanHomeViewModel {
    private(set) var buckets: [SwipeCleanBucket] = []
    /// 第三方 App 相册堆，与月份堆分开展示
    private(set) var appBuckets: [SwipeCleanBucket] = []
    private(set) var isLoading = false
    private var loadTask: Task<Void, Never>?

    /// 少于这个数量的月份不单独成堆，避免入口页碎片化
    private let minimumBucketCount = 5

    /// 并发去重：多次重叠调用共享同一次执行，避免慢的早期调用在后完成时用过期结果覆盖新结果。
    /// 每次执行完成后清空 `loadTask`，因此这不是一次性的记忆化——上一次完成后再调用会重新扫描。
    /// 做法与 `SourceAlbumService.loadAlbums` 一致。
    func loadBuckets(services: AppServiceContainer) async {
        if let task = loadTask {
            await task.value
            return
        }
        let task = Task { @MainActor in
            await self.performLoad(services: services)
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad(services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets()

        // 第一步（主线程，仅做轻量的 Photos 框架枚举）：
        // 按月分组、收集 assetID 列表，fileSize 汇总留到后台线程再做。
        let calendar = Calendar.current
        var grouped: [SwipeCleanBucket.Kind: [PHAsset]] = [:]

        fetchResult.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { return }
            grouped[.month(year: year, month: month), default: []].append(asset)
        }

        guard !grouped.isEmpty else {
            buckets = []
            await loadAppBuckets(services: services)
            return
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")

        struct PendingBucket {
            let id: String
            let kind: SwipeCleanBucket.Kind
            let title: String
            let assets: [PHAsset]
        }

        var pending: [PendingBucket] = []
        for (kind, groupAssets) in grouped {
            guard groupAssets.count >= minimumBucketCount,
                  case let .month(year, month) = kind else { continue }

            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = month
            let title = calendar.date(from: dateComponents).map { formatter.string(from: $0) }
                ?? "\(year)-\(month)"

            pending.append(PendingBucket(
                id: "month-\(year)-\(month)",
                kind: kind,
                title: title,
                assets: groupAssets
            ))
        }

        guard !pending.isEmpty else {
            buckets = []
            await loadAppBuckets(services: services)
            return
        }

        // 第二步：把 fileSize 汇总挪到后台线程，用 autoreleasepool 分批，
        // 做法与 `SourceAlbumService.performLoad` 一致。
        let photoLibrary = services.photoLibrary
        let found: [SwipeCleanBucket] = await Task.detached(priority: .utility) { () -> [SwipeCleanBucket] in
            var result: [SwipeCleanBucket] = []
            result.reserveCapacity(pending.count)

            for item in pending {
                var size: Int64 = 0
                let total = item.assets.count
                let batchSize = 500
                for batchStart in stride(from: 0, to: total, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, total)
                    autoreleasepool {
                        for i in batchStart..<batchEnd {
                            size += photoLibrary.fileSize(for: item.assets[i])
                        }
                    }
                }

                result.append(SwipeCleanBucket(
                    id: item.id,
                    kind: item.kind,
                    title: item.title,
                    assetIDs: item.assets.map(\.localIdentifier),
                    totalSize: size
                ))
            }

            return result
        }.value

        // 新的月份排前面
        buckets = found.sorted { lhs, rhs in
            guard case let .month(ly, lm) = lhs.kind, case let .month(ry, rm) = rhs.kind else {
                return false
            }
            return (ly, lm) > (ry, rm)
        }

        await loadAppBuckets(services: services)
    }

    private func loadAppBuckets(services: AppServiceContainer) async {
        await services.sourceAlbum.loadAlbums(photoLibrary: services.photoLibrary)
        appBuckets = services.sourceAlbum.albums.map { album in
            SwipeCleanBucket(
                id: "album-\(album.id)",
                kind: .sourceAlbum(localIdentifier: album.id),
                title: album.app.displayName,
                assetIDs: album.assetIDs,
                totalSize: album.totalSize
            )
        }
    }

    /// 第三方相册对应的图标，未知时回退到通用图标
    func iconName(for bucket: SwipeCleanBucket) -> String {
        switch bucket.kind {
        case .month:
            return "calendar"
        case .sourceAlbum:
            return SourceApp.known.first { $0.displayName == bucket.title }?.iconName
                ?? "square.stack.3d.up"
        case .screenshots:
            return "camera.viewfinder"
        case .videos:
            return "video"
        }
    }

    /// 某一堆还剩多少张没处理
    func remainingCount(for bucket: SwipeCleanBucket, services: AppServiceContainer) -> Int {
        services.swipeProgress.pendingIDs(
            from: bucket.assetIDs,
            excluding: services.trash.trashedAssetIDs
        ).count
    }
}
