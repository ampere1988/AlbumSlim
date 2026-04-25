import Foundation
import Photos
import SwiftUI

enum SortOrder: String, CaseIterable {
    case size = "按大小"
    case duration = "按时长"
    case date = "按日期"

    var localizedName: String {
        switch self {
        case .size:     return String(localized: "按大小")
        case .duration: return String(localized: "按时长")
        case .date:     return String(localized: "按日期")
        }
    }
}

@MainActor @Observable
final class VideoManagerViewModel {
    var videos: [MediaItem] = []
    private(set) var sortedVideos: [MediaItem] = []
    var isLoading = false
    var compressionProgress: Double = 0
    var selectedQuality: CompressionQuality = .high
    var selectedVideos: Set<String> = []
    var sortOrder: SortOrder = .size {
        didSet { refreshSortedVideos() }
    }
    var isEditing = false
    var suggestions: [VideoAnalysisService.VideoSuggestion] = []
    var isAnalyzingSuggestions = false

    var totalVideoSize: Int64 {
        sortedVideos.reduce(0) { $0 + $1.fileSize }
    }

    private func refreshSortedVideos() {
        sortedVideos = switch sortOrder {
        case .size: videos.sorted { $0.fileSize > $1.fileSize }
        case .duration: videos.sorted { $0.duration > $1.duration }
        case .date: videos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    private var lastLibraryVersion: Int = -1

    func loadVideos(services: AppServiceContainer) async {
        let currentVersion = services.photoLibrary.libraryVersion
        guard lastLibraryVersion != currentVersion || videos.isEmpty else { return }

        let isFirstLoad = videos.isEmpty
        if isFirstLoad { isLoading = true }
        defer { if isFirstLoad { isLoading = false } }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .video)
        videos = await services.photoLibrary.buildMediaItems(from: fetchResult)
        lastLibraryVersion = currentVersion
        refreshSortedVideos()
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
            services.videoCompression.enqueueCompression(asset: item.asset, quality: selectedQuality)
        }
        selectedVideos.removeAll()
        await services.videoCompression.processQueue()
        let compressed = services.videoCompression.queue.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
        if compressed > 0 {
            services.achievement.recordCompression(count: compressed)
        }
        lastLibraryVersion = -1
        await loadVideos(services: services)
    }

    func deleteVideo(_ item: MediaItem, services: AppServiceContainer) {
        videos.removeAll { $0.id == item.id }
        refreshSortedVideos()
        services.trash.moveToTrash(assets: [item.asset], source: .video, mediaType: .video)
    }

    func deleteSelected(services: AppServiceContainer) {
        let idsToDelete = selectedVideos
        let assets = videos.filter { idsToDelete.contains($0.id) }.map(\.asset)
        guard !assets.isEmpty else { return }

        videos.removeAll { idsToDelete.contains($0.id) }
        refreshSortedVideos()
        selectedVideos.removeAll()
        isEditing = false

        services.trash.moveToTrash(assets: assets, source: .video, mediaType: .video)
    }

    func estimatedSize(for item: MediaItem, services: AppServiceContainer) -> Int64 {
        services.videoCompression.estimateCompressedSize(asset: item.asset, quality: selectedQuality)
    }

    var totalSuggestedSaving: Int64 {
        suggestions.reduce(0) { $0 + $1.estimatedSaving }
    }

    func analyzeSuggestions(services: AppServiceContainer) async {
        isAnalyzingSuggestions = true
        defer { isAnalyzingSuggestions = false }
        suggestions = await services.videoAnalysis.analyzeVideos(videos)
    }
}
