import Foundation
import Testing
@testable import AlbumSlim

@Suite("StorageStats 测试")
struct StorageStatsTests {

    @Test("totalSize 应为三类大小之和")
    func totalSizeCalculation() {
        var stats = StorageStats()
        stats.photoSize = 1000
        stats.videoSize = 2000
        stats.screenshotSize = 500
        #expect(stats.totalSize == 3500)
    }

    @Test("空状态判断")
    func isEmpty() {
        let empty = StorageStats()
        #expect(empty.isEmpty)

        var nonEmpty = StorageStats()
        nonEmpty.totalPhotoCount = 1
        #expect(!nonEmpty.isEmpty)
    }

    @Test("categories 返回三个分类且顺序正确")
    func categoriesOrder() {
        var stats = StorageStats()
        stats.videoSize = 100; stats.totalVideoCount = 1
        stats.photoSize = 200; stats.totalPhotoCount = 2
        stats.screenshotSize = 50; stats.totalScreenshotCount = 3

        let cats = stats.categories
        #expect(cats.count == 3)
        #expect(cats[0].name == "视频")
        #expect(cats[1].name == "照片")
        #expect(cats[2].name == "截图")
        #expect(cats[0].size == 100)
        #expect(cats[1].count == 2)
    }

    @Test("Codable 编解码一致")
    func codableRoundTrip() throws {
        var stats = StorageStats()
        stats.totalPhotoCount = 42
        stats.videoSize = 9999
        stats.estimatedSavable = 500
        stats.lastAnalyzedAt = Date(timeIntervalSince1970: 1700000000)

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(StorageStats.self, from: data)

        #expect(decoded.totalPhotoCount == 42)
        #expect(decoded.videoSize == 9999)
        #expect(decoded.estimatedSavable == 500)
        #expect(decoded.lastAnalyzedAt == stats.lastAnalyzedAt)
    }
}
