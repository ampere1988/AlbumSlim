import Foundation
import Photos

/// 沉浸式浏览的单条媒体项
struct ShuffleItem: Identifiable, Hashable {
    enum Kind {
        case photo
        case livePhoto
        case video
    }

    /// 流中唯一 id（同一 asset 被二次洗到队列里时是不同的 ShuffleItem）
    let id: UUID
    let asset: PHAsset
    let kind: Kind
    /// 在 PHFetchResult 中的下标，用于删除时从 ShuffleIndexQueue 中剔除
    let fetchIndex: Int

    init(asset: PHAsset, fetchIndex: Int) {
        self.id = UUID()
        self.asset = asset
        self.fetchIndex = fetchIndex
        if asset.mediaType == .video {
            self.kind = .video
        } else if asset.mediaSubtypes.contains(.photoLive) {
            self.kind = .livePhoto
        } else {
            self.kind = .photo
        }
    }

    static func == (lhs: ShuffleItem, rhs: ShuffleItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
