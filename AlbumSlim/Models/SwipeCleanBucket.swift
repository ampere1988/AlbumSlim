import Foundation

/// 卡片滑动时的单次决策
enum SwipeDecision: String, Codable, Sendable {
    /// 右滑：保留，并记入已处理，之后不再出现
    case keep
    /// 左滑：移入垃圾桶（软删除，可在垃圾桶恢复）
    case trash
}

/// 一「堆」待滑动清理的素材。按堆推进，让用户有明确的开始与结束。
struct SwipeCleanBucket: Identifiable, Sendable {
    /// Hashable 是必需的——Task 6 用它作为月份分组的字典键
    enum Kind: Hashable, Sendable {
        case month(year: Int, month: Int)
        case sourceAlbum(localIdentifier: String)
        case screenshots
        case videos
    }

    let id: String
    let kind: Kind
    let title: String
    let assetIDs: [String]
    let totalSize: Int64

    var count: Int { assetIDs.count }
    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
