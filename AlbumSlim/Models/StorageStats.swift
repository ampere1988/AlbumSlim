import Foundation
import WidgetKit

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
            (String(localized: "视频"), videoSize, totalVideoCount),
            (String(localized: "照片"), photoSize, totalPhotoCount),
            (String(localized: "截图"), screenshotSize, totalScreenshotCount),
        ]
    }

    var isEmpty: Bool {
        totalPhotoCount == 0 && totalVideoCount == 0 && totalScreenshotCount == 0
    }

    // MARK: - 缓存

    static let appGroupID = "group.com.hao.doushan"
    private static let cacheKey = "StorageStatsCache"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        // Widget 从 App Group 容器读取，写完后刷新 timeline
        UserDefaults(suiteName: Self.appGroupID)?.set(data, forKey: Self.cacheKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadCached() -> StorageStats? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
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
