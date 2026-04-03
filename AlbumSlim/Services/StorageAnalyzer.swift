import Foundation
import Photos

@MainActor @Observable
final class StorageAnalyzer {
    private(set) var stats = StorageStats()
    private(set) var isAnalyzing = false
    private(set) var progress: Double = 0

    func analyze(using photoLibrary: PhotoLibraryService) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        var stats = StorageStats()
        let allAssets = photoLibrary.fetchAllAssets()
        let total = allAssets.count

        allAssets.enumerateObjects { asset, index, _ in
            let size = photoLibrary.fileSize(for: asset)

            switch asset.mediaType {
            case .video:
                stats.totalVideoCount += 1
                stats.videoSize += size
            case .image:
                if asset.mediaSubtypes.contains(.photoScreenshot) {
                    stats.totalScreenshotCount += 1
                    stats.screenshotSize += size
                } else {
                    stats.totalPhotoCount += 1
                    stats.photoSize += size
                    if asset.burstIdentifier != nil {
                        stats.totalBurstCount += 1
                    }
                    if asset.mediaSubtypes.contains(.photoLive) {
                        stats.totalLivePhotoCount += 1
                    }
                }
            default:
                break
            }

            if index % 100 == 0 {
                self.progress = Double(index) / Double(total)
            }
        }

        stats.estimatedSavable = stats.screenshotSize + Int64(Double(stats.photoSize) * 0.1)
        self.stats = stats
        self.progress = 1.0
    }
}
