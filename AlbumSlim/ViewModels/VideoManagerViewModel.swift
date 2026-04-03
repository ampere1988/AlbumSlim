import Foundation
import Photos

@MainActor @Observable
final class VideoManagerViewModel {
    var videos: [MediaItem] = []
    var isLoading = false
    var compressionProgress: Double = 0
    var selectedQuality: CompressionQuality = .high

    func loadVideos(services: AppServiceContainer) {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .video)
        videos = services.photoLibrary.buildMediaItems(from: fetchResult)
            .sorted { $0.fileSize > $1.fileSize }
    }

    func compressVideo(_ item: MediaItem, services: AppServiceContainer) async throws -> URL {
        let url = try await services.videoCompression.compressVideo(
            asset: item.asset,
            quality: selectedQuality
        )
        compressionProgress = services.videoCompression.progress
        return url
    }

    func estimatedSize(for item: MediaItem, services: AppServiceContainer) -> Int64 {
        services.videoCompression.estimateCompressedSize(asset: item.asset, quality: selectedQuality)
    }
}
