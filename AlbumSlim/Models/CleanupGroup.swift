import Foundation

struct CleanupGroup: Identifiable {
    let id = UUID()
    let type: GroupType
    var items: [MediaItem]
    var bestItemID: String? // 推荐保留的项目

    var totalSize: Int64 { items.reduce(0) { $0 + $1.fileSize } }
    var savableSize: Int64 {
        guard let bestID = bestItemID else { return totalSize }
        return items.filter { $0.id != bestID }.reduce(0) { $0 + $1.fileSize }
    }

    enum GroupType: String {
        case similar      // 相似照片
        case burst        // 连拍
        case waste        // 废片
        case screenshot   // 截图
        case largeVideo   // 大视频
    }
}
