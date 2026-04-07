import Foundation

enum SharedConstants {
    static let appGroupID = "group.com.hao.doushan"
    static let cacheKey = "StorageStatsCache"
}

struct WidgetStorageStats: Codable {
    var totalPhotoCount: Int = 0
    var totalVideoCount: Int = 0
    var totalScreenshotCount: Int = 0
    var totalBurstCount: Int = 0
    var totalLivePhotoCount: Int = 0
    var photoSize: Int64 = 0
    var videoSize: Int64 = 0
    var screenshotSize: Int64 = 0
    var totalSize: Int64 { photoSize + videoSize + screenshotSize }
    var estimatedSavable: Int64 = 0
    var lastAnalyzedAt: Date?

    var isEmpty: Bool { totalPhotoCount == 0 && totalVideoCount == 0 && totalScreenshotCount == 0 }

    private enum CodingKeys: String, CodingKey {
        case totalPhotoCount, totalVideoCount, totalScreenshotCount
        case totalBurstCount, totalLivePhotoCount
        case photoSize, videoSize, screenshotSize
        case estimatedSavable, lastAnalyzedAt
    }

    static func loadFromAppGroup() -> WidgetStorageStats? {
        guard let data = UserDefaults(suiteName: SharedConstants.appGroupID)?.data(forKey: SharedConstants.cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetStorageStats.self, from: data)
    }
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
