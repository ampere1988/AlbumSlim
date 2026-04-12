import Foundation
import Photos

@MainActor @Observable
final class ScreenshotViewModel {
    var screenshots: [MediaItem] = []
    var ocrResults: [String: OCRResult] = [:]
    var exportedIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "exportedScreenshotIDs") ?? [])
    }()
    var isLoading = false
    var isAnalyzing = false
    var analysisProgress: Double = 0
    var selectedItems: Set<String> = []
    var filterCategory: ScreenshotCategory?
    var filterExported: Bool = false
    var isEditing = false
    var showDeleteConfirmation = false
    var showDeleteExportedConfirmation = false

    var filteredScreenshots: [MediaItem] {
        screenshots.filter { item in
            if filterExported { return exportedIDs.contains(item.id) }
            guard let filter = filterCategory else { return true }
            guard let result = ocrResults[item.id] else { return filter == .other }
            return result.category == filter
        }
    }

    var exportedCount: Int { screenshots.filter { exportedIDs.contains($0.id) }.count }

    private var lastLibraryVersion: Int = -1

    func loadScreenshots(services: AppServiceContainer) async {
        let currentVersion = services.photoLibrary.libraryVersion
        guard lastLibraryVersion != currentVersion || screenshots.isEmpty else { return }

        let isFirstLoad = screenshots.isEmpty
        if isFirstLoad { isLoading = true }
        defer { if isFirstLoad { isLoading = false } }

        let fetchResult = services.photoLibrary.fetchScreenshots()
        screenshots = await services.photoLibrary.buildMediaItems(from: fetchResult)
        lastLibraryVersion = currentVersion
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

    // 批量：识别未识别的 → 存储到文件 → 返回成功数量
    func analyzeAndExportSelected(services: AppServiceContainer) async -> Int {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let items = screenshots.filter { selectedItems.contains($0.id) }
        let unanalyzed = items.filter { ocrResults[$0.id] == nil }
        let total = unanalyzed.count
        for (index, item) in unanalyzed.enumerated() {
            await analyzeScreenshot(item, services: services)
            analysisProgress = Double(index + 1) / Double(max(total, 1))
        }

        let notesService = NotesExportService()
        var count = 0
        for item in items {
            guard let result = ocrResults[item.id] else { continue }
            let (title, content) = notesService.formatScreenshotNote(ocrResult: result, date: item.creationDate)
            if (try? notesService.saveNote(title: title, content: content)) != nil {
                markExported(item.id)
                count += 1
            }
        }
        return count
    }

    func markExported(_ id: String) {
        exportedIDs.insert(id)
        persistExportedIDs()
    }

    func unmarkExported(_ id: String) {
        exportedIDs.remove(id)
        persistExportedIDs()
    }

    private func persistExportedIDs() {
        UserDefaults.standard.set(Array(exportedIDs), forKey: "exportedScreenshotIDs")
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
        let idsToDelete = selectedItems
        let assets = screenshots.filter { idsToDelete.contains($0.id) }.map(\.asset)
        guard !assets.isEmpty else { return }
        do {
            try await services.photoLibrary.deleteAssets(assets)
            screenshots.removeAll { idsToDelete.contains($0.id) }
            for id in idsToDelete {
                ocrResults.removeValue(forKey: id)
                exportedIDs.remove(id)
            }
            persistExportedIDs()
            selectedItems.removeAll()
            lastLibraryVersion = services.photoLibrary.libraryVersion
        } catch {
            print("批量删除截图失败: \(error)")
        }
    }

    func deleteExported(services: AppServiceContainer) async {
        let idsToDelete = exportedIDs.filter { id in screenshots.contains { $0.id == id } }
        let assets = screenshots.filter { idsToDelete.contains($0.id) }.map(\.asset)
        guard !assets.isEmpty else { return }
        do {
            try await services.photoLibrary.deleteAssets(assets)
            screenshots.removeAll { idsToDelete.contains($0.id) }
            for id in idsToDelete {
                ocrResults.removeValue(forKey: id)
                exportedIDs.remove(id)
            }
            persistExportedIDs()
            selectedItems = selectedItems.subtracting(idsToDelete)
            lastLibraryVersion = services.photoLibrary.libraryVersion
        } catch {
            print("删除已存储截图失败: \(error)")
        }
    }

    /// 从 UI 数据源移除截图（不操作 Photos 库）
    func removeScreenshotFromUI(_ id: String) {
        screenshots.removeAll { $0.id == id }
        ocrResults.removeValue(forKey: id)
        exportedIDs.remove(id)
        persistExportedIDs()
    }

    func deleteScreenshot(_ item: MediaItem, services: AppServiceContainer) async {
        do {
            try await services.photoLibrary.deleteAssets([item.asset])
            screenshots.removeAll { $0.id == item.id }
            ocrResults.removeValue(forKey: item.id)
            exportedIDs.remove(item.id)
            persistExportedIDs()
            lastLibraryVersion = services.photoLibrary.libraryVersion
        } catch {
            print("删除截图失败: \(error)")
        }
    }

    func exportSelected(services: AppServiceContainer) {
        let notesService = NotesExportService()
        let items = screenshots.filter { selectedItems.contains($0.id) }
        var notes: [(title: String, content: String)] = []
        for item in items {
            guard let result = ocrResults[item.id] else { continue }
            notes.append(notesService.formatScreenshotNote(ocrResult: result, date: item.creationDate))
        }
        guard !notes.isEmpty else { return }
        if let _ = try? notesService.saveBatch(notes) {
            for item in items where ocrResults[item.id] != nil {
                markExported(item.id)
            }
        }
    }
}
