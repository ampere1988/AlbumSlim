import Foundation

struct StorageStats {
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

    var categories: [(name: String, size: Int64, count: Int)] {
        [
            ("视频", videoSize, totalVideoCount),
            ("照片", photoSize, totalPhotoCount),
            ("截图", screenshotSize, totalScreenshotCount),
        ]
    }
}
