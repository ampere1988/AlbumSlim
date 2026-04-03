import Foundation
import Photos

@MainActor @Observable
final class ScreenshotViewModel {
    var screenshots: [MediaItem] = []
    var ocrResults: [String: OCRResult] = [:]
    var isLoading = false
    var isAnalyzing = false
    var analysisProgress: Double = 0
    var selectedItems: Set<String> = []
    var filterCategory: ScreenshotCategory?
    var isEditing = false
    var showDeleteConfirmation = false

    var filteredScreenshots: [MediaItem] {
        guard let filter = filterCategory else { return screenshots }
        return screenshots.filter { item in
            guard let result = ocrResults[item.id] else { return filter == .other }
            return result.category == filter
        }
    }

    func loadScreenshots(services: AppServiceContainer) {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchScreenshots()
        screenshots = services.photoLibrary.buildMediaItems(from: fetchResult)
    }

    func analyzeScreenshot(_ item: MediaItem, services: AppServiceContainer) async {
        let size = CGSize(width: 1024, height: 1024)
        guard let image = await services.photoLibrary.thumbnail(for: item.asset, size: size),
              let result = await services.ocrService.recognizeText(from: image) else { return }
        ocrResults[item.id] = result
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
    }

    func exportToNotes(_ item: MediaItem, services: AppServiceContainer) {
        guard let result = ocrResults[item.id] else { return }
        let notesService = NotesExportService()
        let (title, content) = notesService.formatScreenshotNote(
            ocrResult: result,
            date: item.creationDate
        )
        notesService.exportToNotes(title: title, content: content)
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

    func deleteSelected(services: AppServiceContainer) async {
        let assets = screenshots.filter { selectedItems.contains($0.id) }.map(\.asset)
        guard !assets.isEmpty else { return }
        do {
            try await services.photoLibrary.deleteAssets(assets)
            screenshots.removeAll { selectedItems.contains($0.id) }
            for id in selectedItems { ocrResults.removeValue(forKey: id) }
            selectedItems.removeAll()
        } catch {}
    }

    func deleteScreenshot(_ item: MediaItem, services: AppServiceContainer) async {
        do {
            try await services.photoLibrary.deleteAssets([item.asset])
            screenshots.removeAll { $0.id == item.id }
            ocrResults.removeValue(forKey: item.id)
        } catch {}
    }

    func exportSelected(services: AppServiceContainer) {
        let notesService = NotesExportService()
        let items = screenshots.filter { selectedItems.contains($0.id) }
        var allText = ""
        for item in items {
            guard let result = ocrResults[item.id] else { continue }
            let (title, content) = notesService.formatScreenshotNote(
                ocrResult: result,
                date: item.creationDate
            )
            allText += "\(title)\n\(content)\n\n---\n\n"
        }
        if !allText.isEmpty {
            notesService.exportToNotes(title: "截图批量导出 (\(items.count)条)", content: allText)
        }
    }
}
