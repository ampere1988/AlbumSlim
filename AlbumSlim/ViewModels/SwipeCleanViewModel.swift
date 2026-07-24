import Foundation
import Photos
import SwiftUI
import UIKit

@MainActor @Observable
final class SwipeCleanViewModel {

    /// 一次决策的记录，供撤销
    private struct HistoryEntry {
        let item: MediaItem
        let decision: SwipeDecision
        let reclaimedSize: Int64
    }

    private(set) var items: [MediaItem] = []
    private(set) var index: Int = 0
    private(set) var isLoading = false
    private(set) var trashedSizeInSession: Int64 = 0
    private(set) var bucketTitle: String = ""

    private var history: [HistoryEntry] = []
    private var bucket: SwipeCleanBucket?

    /// 缩略图缓存，键为 assetID
    private(set) var thumbnails: [String: UIImage] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]

    /// 预取窗口：当前卡之后再准备 3 张
    private let prefetchWindow = 3

    // MARK: - 派生状态

    var current: MediaItem? { index < items.count ? items[index] : nil }
    var upcoming: MediaItem? { index + 1 < items.count ? items[index + 1] : nil }
    var canUndo: Bool { !history.isEmpty }
    var isFinished: Bool { !items.isEmpty && index >= items.count }
    var processedCount: Int { index }
    var totalCount: Int { items.count }
    var progress: Double {
        items.isEmpty ? 0 : Double(index) / Double(items.count)
    }
    var trashedSizeText: String {
        ByteCountFormatter.string(fromByteCount: trashedSizeInSession, countStyle: .file)
    }

    // MARK: - 加载

    func load(bucket: SwipeCleanBucket, services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        self.bucket = bucket
        bucketTitle = bucket.title
        index = 0
        history = []
        trashedSizeInSession = 0
        thumbnails = [:]

        let pendingIDs = services.swipeProgress.pendingIDs(
            from: bucket.assetIDs,
            excluding: services.trash.trashedAssetIDs
        )
        guard !pendingIDs.isEmpty else {
            items = []
            return
        }

        // fetchAssets 不保证返回顺序，按 pendingIDs 顺序重排
        let fetched = services.trash.fetchAssets(for: Set(pendingIDs))
        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        let ordered = pendingIDs.compactMap { byID[$0] }

        items = ordered.map { asset in
            MediaItem(
                id: asset.localIdentifier,
                asset: asset,
                fileSize: services.photoLibrary.fileSize(for: asset),
                creationDate: asset.creationDate
            )
        }

        prefetchThumbnails(services: services)
    }

    // MARK: - 决策

    /// 调用方必须先过 `ProFeatureGate.canClean(isPro:)` 才允许传入 `.trash`
    func decide(_ decision: SwipeDecision, services: AppServiceContainer) {
        guard let item = current else { return }

        var reclaimed: Int64 = 0
        switch decision {
        case .keep:
            services.swipeProgress.markKept(item.id)
        case .trash:
            let mediaType: TrashedMediaType = {
                if item.mediaType == .video { return .video }
                if item.isScreenshot { return .screenshot }
                if item.isLivePhoto { return .livePhoto }
                return .photo
            }()
            let result = services.trash.moveToTrash(
                assets: [item.asset],
                source: .swipeClean,
                mediaType: mediaType
            )
            reclaimed = result.totalSize
            trashedSizeInSession += reclaimed
        }

        history.append(HistoryEntry(item: item, decision: decision, reclaimedSize: reclaimed))
        index += 1
        thumbnails.removeValue(forKey: item.id)
        prefetchThumbnails(services: services)
        Haptics.light()
    }

    func undo(services: AppServiceContainer) {
        guard let entry = history.popLast() else { return }
        switch entry.decision {
        case .keep:
            services.swipeProgress.unmarkKept(entry.item.id)
        case .trash:
            services.trash.restore([entry.item.id])
            trashedSizeInSession = max(0, trashedSizeInSession - entry.reclaimedSize)
        }
        index = max(0, index - 1)
        prefetchThumbnails(services: services)
        Haptics.light()
    }

    /// 重新清理这一堆
    func restart(services: AppServiceContainer) async {
        guard let bucket else { return }
        services.swipeProgress.resetBucket(assetIDs: bucket.assetIDs)
        await load(bucket: bucket, services: services)
    }

    // MARK: - 缩略图

    func thumbnail(for assetID: String) -> UIImage? { thumbnails[assetID] }

    private func prefetchThumbnails(services: AppServiceContainer) {
        let upperBound = min(index + prefetchWindow, items.count)
        guard index < upperBound else { return }

        // 目标尺寸取屏幕宽度的 2 倍像素，卡片本身不超过屏宽
        let side = UIScreen.main.bounds.width * UIScreen.main.scale
        let size = CGSize(width: side, height: side * 1.6)

        for i in index..<upperBound {
            let item = items[i]
            guard thumbnails[item.id] == nil, thumbnailTasks[item.id] == nil else { continue }
            let task = Task { @MainActor [weak self] in
                let image = await services.photoLibrary.thumbnail(
                    for: item.asset, size: size, contentMode: .aspectFit
                )
                guard let self, !Task.isCancelled else { return }
                if let image { self.thumbnails[item.id] = image }
                self.thumbnailTasks.removeValue(forKey: item.id)
            }
            thumbnailTasks[item.id] = task
        }
    }

    func cancelAllTasks() {
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
        thumbnails.removeAll()
    }
}

#if DEBUG
extension SwipeCleanViewModel {
    var currentIDForTesting: String? { current?.id }
    var upcomingIDForTesting: String? { upcoming?.id }

    /// 用假 id 构造队列，绕开 PHAsset —— 只测队列推进与撤销栈
    func injectQueueForTesting(ids: [String]) {
        items = ids.map { id in
            MediaItem(id: id, asset: PHAsset(), fileSize: 0, creationDate: nil)
        }
        index = 0
        history = []
    }

    func advanceForTesting() {
        guard let item = current else { return }
        history.append(HistoryEntry(item: item, decision: .keep, reclaimedSize: 0))
        index += 1
    }

    func rewindForTesting() {
        guard history.popLast() != nil else { return }
        index = max(0, index - 1)
    }
}
#endif
