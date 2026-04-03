import Foundation
import Photos

enum SortOrder: String, CaseIterable {
    case size = "按大小"
    case duration = "按时长"
    case date = "按日期"
}

@MainActor @Observable
final class VideoManagerViewModel {
    var videos: [MediaItem] = []
    var isLoading = false
    var compressionProgress: Double = 0
    var selectedQuality: CompressionQuality = .high
    var selectedVideos: Set<String> = []
    var sortOrder: SortOrder = .size
    var isEditing = false

    var totalVideoSize: Int64 {
        videos.reduce(0) { $0 + $1.fileSize }
    }

    var sortedVideos: [MediaItem] {
        switch sortOrder {
        case .size:
            videos.sorted { $0.fileSize > $1.fileSize }
        case .duration:
            videos.sorted { $0.duration > $1.duration }
        case .date:
            videos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    func loadVideos(services: AppServiceContainer) {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .video)
        videos = services.photoLibrary.buildMediaItems(from: fetchResult)
    }

    func toggleSelection(_ id: String) {
        if selectedVideos.contains(id) {
            selectedVideos.remove(id)
        } else {
            selectedVideos.insert(id)
        }
    }

    func compressVideo(_ item: MediaItem, services: AppServiceContainer) async throws -> URL {
        let url = try await services.videoCompression.compressVideo(
            asset: item.asset,
            quality: selectedQuality
        )
        compressionProgress = services.videoCompression.progress
        return url
    }

    func compressAndReplace(item: MediaItem, services: AppServiceContainer) async throws {
        let url = try await services.videoCompression.compressVideo(
            asset: item.asset, quality: selectedQuality
        )
        try await services.videoCompression.replaceOriginal(asset: item.asset, with: url)
    }

    func compressAndSaveNew(item: MediaItem, services: AppServiceContainer) async throws {
        let url = try await services.videoCompression.compressVideo(
            asset: item.asset, quality: selectedQuality
        )
        try await services.videoCompression.saveCompressedToLibrary(url: url)
    }

    func compressSelected(services: AppServiceContainer) async throws {
        let items = videos.filter { selectedVideos.contains($0.id) }
        for item in items {
            try await compressAndReplace(item: item, services: services)
        }
        selectedVideos.removeAll()
        loadVideos(services: services)
    }

    func estimatedSize(for item: MediaItem, services: AppServiceContainer) -> Int64 {
        services.videoCompression.estimateCompressedSize(asset: item.asset, quality: selectedQuality)
    }
}
