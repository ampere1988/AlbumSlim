import Foundation
import Photos

enum ScreenshotSortOrder: String, CaseIterable {
    case date = "按日期"
    case size = "按大小"

    var localizedName: String { rawValue }
}

@MainActor @Observable
final class ScreenshotViewModel {
    var screenshots: [MediaItem] = []
    var ocrResults: [String: OCRResult] = [:]
    var isLoading = false
    var isAnalyzing = false
    var analysisProgress: Double = 0
    var selectedItems: Set<String> = []
    var filterCategory: ScreenshotCategory? {
        didSet {
            selectedItems.removeAll()
            refreshFilteredScreenshots()
        }
    }
    var isEditing = false
    var sortOrder: ScreenshotSortOrder = .date {
        didSet { refreshFilteredScreenshots() }
    }

    private(set) var filteredScreenshots: [MediaItem] = []
    private var lastLibraryVersion: Int = -1

    private func refreshFilteredScreenshots() {
        let filtered = screenshots.filter { item in
            guard let filter = filterCategory else { return true }
            guard let result = ocrResults[item.id] else { return filter == .other }
            return result.category == filter
        }
        filteredScreenshots = switch sortOrder {
        case .date:
            filtered.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .size:
            filtered.sorted { $0.fileSize > $1.fileSize }
        }
    }

    func invalidateCache() {
        lastLibraryVersion = -1
    }

    func loadScreenshots(services: AppServiceContainer) async {
        let trashedIDs = services.trash.trashedAssetIDs
        let currentVersion = services.photoLibrary.libraryVersion
        guard lastLibraryVersion != currentVersion || screenshots.isEmpty else { return }

        let isFirstLoad = screenshots.isEmpty
        if isFirstLoad { isLoading = true }
        defer { if isFirstLoad { isLoading = false } }

        let fetchResult = services.photoLibrary.fetchScreenshots()
        let allItems = await services.photoLibrary.buildMediaItems(from: fetchResult)
        screenshots = allItems.filter { !trashedIDs.contains($0.id) }
        lastLibraryVersion = currentVersion
        refreshFilteredScreenshots()
    }

    func analyzeScreenshot(_ item: MediaItem, services: AppServiceContainer) async {
        let size = CGSize(width: 1024, height: 1024)
        guard let image = await services.photoLibrary.thumbnail(for: item.asset, size: size),
              let result = await services.ocrService.recognizeText(from: image) else { return }
        ocrResults[item.id] = result
        refreshFilteredScreenshots()
    }

    func analyzeAllScreenshots(services: AppServiceContainer) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let items = filteredScreenshots.filter { ocrResults[$0.id] == nil }
        let total = items.count
        guard total > 0 else { return }
        for (index, item) in items.enumerated() {
            await analyzeScreenshot(item, services: services)
            analysisProgress = Double(index + 1) / Double(total)
        }
        services.achievement.recordScan()
    }

    func toggleSelection(_ id: String) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    func selectAll() {
        selectedItems = Set(filteredScreenshots.map(\.id))
    }

    func deselectAll() {
        selectedItems.removeAll()
    }

    func trashSelected(services: AppServiceContainer) {
        let items = screenshots.filter { selectedItems.contains($0.id) }
        guard !items.isEmpty else { return }
        let assets = services.trash.fetchAssets(for: Set(items.map(\.id)))
        services.trash.moveToTrash(assets: assets, source: .screenshot, mediaType: .screenshot)
        let ids = Set(items.map(\.id))
        screenshots.removeAll { ids.contains($0.id) }
        for id in ids { ocrResults.removeValue(forKey: id) }
        selectedItems.removeAll()
        refreshFilteredScreenshots()
    }

    func trashScreenshot(_ item: MediaItem, services: AppServiceContainer) {
        let assets = services.trash.fetchAssets(for: [item.id])
        services.trash.moveToTrash(assets: assets, source: .screenshot, mediaType: .screenshot)
        screenshots.removeAll { $0.id == item.id }
        ocrResults.removeValue(forKey: item.id)
        selectedItems.remove(item.id)
        refreshFilteredScreenshots()
    }

    func removeScreenshotFromUI(_ id: String) {
        screenshots.removeAll { $0.id == id }
        ocrResults.removeValue(forKey: id)
        selectedItems.remove(id)
        refreshFilteredScreenshots()
    }
}
