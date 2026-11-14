import Foundation
import Photos

@MainActor @Observable
final class SwipeCleanHomeViewModel {
    private struct CacheSnapshot: Codable {
        let buckets: [SwipeCleanBucket]
        let appBuckets: [SwipeCleanBucket]
        let libraryVersion: Int
        let savedAt: Date
    }

    private(set) var buckets: [SwipeCleanBucket] = []
    /// 第三方 App 相册堆，与月份堆分开展示
    private(set) var appBuckets: [SwipeCleanBucket] = []
    private(set) var isLoading = false
    private var loadTask: Task<Void, Never>?
    private var lastLibraryVersion = Int.min
    private var lastLoadedAt: Date?
    private var hasLoaded = false

    /// 少于这个数量的月份不单独成堆，避免入口页碎片化
    private let minimumBucketCount = 5
    /// 相册内容短时间内通常变化很小。即使版本指纹没有变化，也定期做一次轻量校验。
    private static let cacheLifetime: TimeInterval = 5 * 60
    /// 旧快照只用于刷新期间的占位，超过一天就不再恢复，避免展示过时过多的数据。
    private static let maximumSnapshotAge: TimeInterval = 24 * 60 * 60
    private static let cacheKey = "SwipeCleanHomeViewModel.cache"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let snapshot = try? JSONDecoder().decode(CacheSnapshot.self, from: data),
              Date.now.timeIntervalSince(snapshot.savedAt) < Self.maximumSnapshotAge else {
            return
        }
        buckets = snapshot.buckets
        appBuckets = snapshot.appBuckets
        lastLibraryVersion = snapshot.libraryVersion
        lastLoadedAt = snapshot.savedAt
        hasLoaded = true
    }

    /// 优先复用内存缓存；缓存过期或相册变化时保留旧结果，在后台刷新。
    /// 多次重叠调用共享同一次执行，避免重复遍历整个相册。
    func loadBuckets(services: AppServiceContainer) async {
        let version = services.photoLibrary.libraryVersion
        if isCacheFresh(libraryVersion: version) { return }

        if let task = loadTask {
            await task.value
            return
        }
        let task = Task { @MainActor in
            await self.performLoad(services: services, libraryVersion: version)
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func isCacheFresh(libraryVersion: Int, now: Date = .now) -> Bool {
        guard hasLoaded,
              lastLibraryVersion == libraryVersion,
              let lastLoadedAt else { return false }
        return now.timeIntervalSince(lastLoadedAt) < Self.cacheLifetime
    }

    private func performLoad(services: AppServiceContainer, libraryVersion: Int) async {
        // 已有缓存时继续展示列表，不再用全屏 loading 打断用户。
        let shouldShowLoading = !hasLoaded
        if shouldShowLoading { isLoading = true }
        defer {
            if shouldShowLoading { isLoading = false }
        }

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
            markLoaded(libraryVersion: libraryVersion)
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
            markLoaded(libraryVersion: libraryVersion)
            return
        }

        // 没变化的月份直接复用旧体积；通常只需重算本月新增照片所在的一个桶。
        let cachedByID = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        var reused: [SwipeCleanBucket] = []
        let changed = pending.filter { item in
            guard let cached = cachedByID[item.id],
                  cached.assetIDs == item.assets.map(\.localIdentifier) else { return true }
            reused.append(cached)
            return false
        }

        // 第二步：只对变化的月份在后台汇总 fileSize，用 autoreleasepool 分批。
        let photoLibrary = services.photoLibrary
        let found: [SwipeCleanBucket] = await Task.detached(priority: .utility) { () -> [SwipeCleanBucket] in
            var result: [SwipeCleanBucket] = []
            result.reserveCapacity(changed.count)

            for item in changed {
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

        guard !Task.isCancelled else { return }

        // 新的月份排前面
        buckets = (reused + found).sorted { lhs, rhs in
            guard case let .month(ly, lm) = lhs.kind, case let .month(ry, rm) = rhs.kind else {
                return false
            }
            return (ly, lm) > (ry, rm)
        }

        await loadAppBuckets(services: services)
        markLoaded(libraryVersion: libraryVersion)
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

    private func markLoaded(libraryVersion: Int) {
        let now = Date.now
        hasLoaded = true
        lastLibraryVersion = libraryVersion
        lastLoadedAt = now
        let snapshot = CacheSnapshot(
            buckets: buckets,
            appBuckets: appBuckets,
            libraryVersion: libraryVersion,
            savedAt: now
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
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
