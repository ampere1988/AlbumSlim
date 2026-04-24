import Foundation
import Photos
import SwiftUI

@MainActor @Observable
final class ShuffleFeedViewModel {
    /// 当前被渲染的媒体序列（单调增长，到达上限后从头截断）
    private(set) var items: [ShuffleItem] = []

    /// 授权状态（用于首屏 overlay 引导）
    var authStatus: PHAuthorizationStatus = .notDetermined

    /// 启动失败时的友好文案（例如相册为空）
    var emptyMessage: String?

    /// 全量 PHFetchResult（按 creationDate 倒序）
    private var fetchResult: PHFetchResult<PHAsset>?

    /// 随机索引队列
    private var indexQueue = ShuffleIndexQueue(total: 0)

    /// items 数组大小保留上限，超出后从头截断以控制内存
    private let maxItemCount = 80

    /// 已自动播放过的 Live Photo asset id —— 回滑不再重播
    private(set) var playedLiveIds: Set<String> = []

    func markLivePlayed(_ assetID: String) {
        playedLiveIds.insert(assetID)
    }

    /// 初次加载（首次进入 Tab 0 或权限变化后）
    func bootstrap(services: AppServiceContainer) async {
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

        // 预铺初始窗口：当前 cursor + 之后 4 个
        items.removeAll(keepingCapacity: true)
        appendNext(count: 5)
    }

    /// 用户滑到新的 page（可能是前进或后退）后回调
    func onPageAppeared(itemID: ShuffleItem.ID?) {
        guard let itemID else { return }
        guard let currentIdx = items.firstIndex(where: { $0.id == itemID }) else { return }
        // 距离尾部不足 3 项时继续追加
        let remainingAhead = items.count - 1 - currentIdx
        if remainingAhead < 3 {
            appendNext(count: 3)
        }
        // 头部积累过多时截断，保持内存可控
        if items.count > maxItemCount {
            let dropCount = items.count - maxItemCount + 20
            // 仅在当前 page 前方还有大量缓冲时才 drop，避免滚动跳动
            if currentIdx > dropCount + 5 {
                items.removeFirst(dropCount)
            }
        }
    }

    /// 从 items 中移除某一项（被用户删除的 asset）
    func remove(itemID: ShuffleItem.ID) {
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            let fetchIndex = items[idx].fetchIndex
            items.remove(at: idx)
            indexQueue.remove(fetchIndex: fetchIndex)
        }
    }

    /// 相册在应用外发生变化（系统相册删除、iCloud 同步）后，剔除不存在的 items
    func refreshAfterLibraryChange(services: AppServiceContainer) async {
        let ids = items.map { $0.asset.localIdentifier }
        guard !ids.isEmpty else { return }
        let existing = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var aliveIDs: Set<String> = []
        existing.enumerateObjects { asset, _, _ in aliveIDs.insert(asset.localIdentifier) }
        items.removeAll { !aliveIDs.contains($0.asset.localIdentifier) }
    }

    /// 向 items 尾部追加 n 个新 page
    private func appendNext(count: Int) {
        guard let fetchResult else { return }
        for _ in 0..<count {
            let next: Int?
            if items.isEmpty {
                next = indexQueue.current ?? indexQueue.advance()
            } else {
                next = indexQueue.advance()
            }
            guard let fetchIndex = next, fetchIndex < fetchResult.count else { break }
            let asset = fetchResult.object(at: fetchIndex)
            items.append(ShuffleItem(asset: asset, fetchIndex: fetchIndex))
        }
    }
}
