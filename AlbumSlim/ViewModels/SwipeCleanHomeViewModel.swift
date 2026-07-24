import Foundation
import Photos

@MainActor @Observable
final class SwipeCleanHomeViewModel {
    private(set) var buckets: [SwipeCleanBucket] = []
    /// 第三方 App 相册堆，与月份堆分开展示
    private(set) var appBuckets: [SwipeCleanBucket] = []
    private(set) var isLoading = false

    /// 少于这个数量的月份不单独成堆，避免入口页碎片化
    private let minimumBucketCount = 5

    func loadBuckets(services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets()
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else {
            buckets = []
            return
        }

        let calendar = Calendar.current
        var grouped: [SwipeCleanBucket.Kind: [PHAsset]] = [:]

        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { continue }
            grouped[.month(year: year, month: month), default: []].append(asset)
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")

        var result: [SwipeCleanBucket] = []
        for (kind, groupAssets) in grouped {
            guard groupAssets.count >= minimumBucketCount,
                  case let .month(year, month) = kind else { continue }

            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = month
            let title = calendar.date(from: dateComponents).map { formatter.string(from: $0) }
                ?? "\(year)-\(month)"

            let totalSize = groupAssets.reduce(Int64(0)) {
                $0 + services.photoLibrary.fileSize(for: $1)
            }

            result.append(SwipeCleanBucket(
                id: "month-\(year)-\(month)",
                kind: kind,
                title: title,
                assetIDs: groupAssets.map(\.localIdentifier),
                totalSize: totalSize
            ))
        }

        // 新的月份排前面
        buckets = result.sorted { lhs, rhs in
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
