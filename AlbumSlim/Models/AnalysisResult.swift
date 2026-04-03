import Foundation
import SwiftData

enum WasteReason: String, Codable {
    case pureBlack    // 纯黑
    case pureWhite    // 纯白
    case blurry       // 模糊
    case fingerBlock  // 手指遮挡
    case accidental   // 意外拍摄
}

enum PhotoQuality: String, Codable, Comparable {
    case low, medium, high

    static func < (lhs: PhotoQuality, rhs: PhotoQuality) -> Bool {
        let order: [PhotoQuality] = [.low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

@Model
final class CachedAnalysis {
    @Attribute(.unique) var assetIdentifier: String
    var isWaste: Bool
    var wasteReason: WasteReason?
    var qualityScore: Float
    var featurePrintData: Data?
    var ocrText: String?
    var analyzedAt: Date

    init(assetIdentifier: String) {
        self.assetIdentifier = assetIdentifier
        self.isWaste = false
        self.qualityScore = 0
        self.analyzedAt = .now
    }
}
