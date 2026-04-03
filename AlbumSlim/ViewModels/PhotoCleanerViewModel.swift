import Foundation

@MainActor @Observable
final class PhotoCleanerViewModel {
    var similarGroups: [CleanupGroup] = []
    var wasteItems: [MediaItem] = []
    var isScanning = false
    var scanProgress: Double = 0
    var selectedForDeletion: Set<String> = []
    var wasteReasons: [String: WasteReason] = [:]

    func toggleSelection(_ itemID: String) {
        if selectedForDeletion.contains(itemID) {
            selectedForDeletion.remove(itemID)
        } else {
            selectedForDeletion.insert(itemID)
        }
    }

    func selectAllExceptBest(in group: CleanupGroup) {
        for item in group.items {
            if item.id != group.bestItemID {
                selectedForDeletion.insert(item.id)
            } else {
                selectedForDeletion.remove(item.id)
            }
        }
    }

    func deleteSelected(services: AppServiceContainer) async throws -> Int64 {
        let allItems = similarGroups.flatMap(\.items) + wasteItems
        let toDelete = allItems.filter { selectedForDeletion.contains($0.id) }
        guard !toDelete.isEmpty else { return 0 }

        let freedSize = toDelete.reduce(Int64(0)) { $0 + $1.fileSize }
        let assets = toDelete.map(\.asset)
        try await services.photoLibrary.deleteAssets(assets)

        let deletedIDs = selectedForDeletion
        similarGroups = similarGroups.compactMap { group in
            var g = group
            g.items.removeAll { deletedIDs.contains($0.id) }
            return g.items.count > 1 ? g : nil
        }
        wasteItems.removeAll { deletedIDs.contains($0.id) }
        for id in deletedIDs { wasteReasons.removeValue(forKey: id) }
        selectedForDeletion.removeAll()

        return freedSize
    }

    func scanSimilarPhotos(services: AppServiceContainer) async {
        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let items = services.photoLibrary.buildMediaItems(from: fetchResult)

        similarGroups = await services.imageSimilarity.findSimilarGroups(
            from: items,
            using: services.photoLibrary,
            onProgress: { [weak self] progress in
                self?.scanProgress = progress
            }
        )

        services.cleanupCoordinator.addGroups(similarGroups)
        scanProgress = 1.0
    }

    func scanWastePhotos(services: AppServiceContainer) async {
        isScanning = true
        scanProgress = 0
        defer { isScanning = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let allItems = services.photoLibrary.buildMediaItems(from: fetchResult)
        let engine = services.aiEngine
        let library = services.photoLibrary
        let size = CGSize(width: 300, height: 300)

        var waste: [MediaItem] = []
        let total = allItems.count
        let batchSize = AppConstants.Analysis.batchSize

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            for index in batchStart..<batchEnd {
                let item = allItems[index]
                if let image = await library.thumbnail(for: item.asset, size: size) {
                    let result = engine.detectWaste(image: image)
                    if result.isWaste {
                        waste.append(item)
                        if let reason = result.reason {
                            wasteReasons[item.id] = reason
                        }
                    }
                }
            }
            scanProgress = Double(batchEnd) / Double(total)
        }

        wasteItems = waste
        scanProgress = 1.0

        let wasteGroup = CleanupGroup(type: .waste, items: waste, bestItemID: nil)
        services.cleanupCoordinator.addGroups([wasteGroup])
    }
}
