import Foundation

struct StorageStats: Codable {
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

    var categories: [(name: String, size: Int64, count: Int)] {
        [
            ("视频", videoSize, totalVideoCount),
            ("照片", photoSize, totalPhotoCount),
            ("截图", screenshotSize, totalScreenshotCount),
        ]
    }

    var isEmpty: Bool {
        totalPhotoCount == 0 && totalVideoCount == 0 && totalScreenshotCount == 0
    }

    // MARK: - 缓存

    static let appGroupID = "group.com.huge.albumslim"
    private static let cacheKey = "StorageStatsCache"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults(suiteName: Self.appGroupID)?.set(data, forKey: Self.cacheKey)
    }

    static func loadCached() -> StorageStats? {
        let data = UserDefaults.standard.data(forKey: cacheKey)
            ?? UserDefaults(suiteName: appGroupID)?.data(forKey: cacheKey)
        guard let data else { return nil }
        return try? JSONDecoder().decode(StorageStats.self, from: data)
    }

    // Codable: 排除计算属性
    private enum CodingKeys: String, CodingKey {
        case totalPhotoCount, totalVideoCount, totalScreenshotCount
        case totalBurstCount, totalLivePhotoCount
        case photoSize, videoSize, screenshotSize
        case estimatedSavable, lastAnalyzedAt
    }
}
