import Foundation
import Photos

@MainActor @Observable
final class SwipeCleanHomeViewModel {
    private(set) var buckets: [SwipeCleanBucket] = []
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
    }

    /// 某一堆还剩多少张没处理
    func remainingCount(for bucket: SwipeCleanBucket, services: AppServiceContainer) -> Int {
        services.swipeProgress.pendingIDs(
            from: bucket.assetIDs,
            excluding: services.trash.trashedAssetIDs
        ).count
    }
}
