import Foundation

@MainActor @Observable
final class ScreenshotViewModel {
    var screenshots: [MediaItem] = []
    var ocrResults: [String: OCRResult] = [:] // assetID -> OCRResult
    var isLoading = false
    var isAnalyzing = false
    var analysisProgress: Double = 0

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

        let total = screenshots.count
        for (index, item) in screenshots.enumerated() {
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
}
