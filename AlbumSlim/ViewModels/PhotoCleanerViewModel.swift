import Foundation

@MainActor @Observable
final class PhotoCleanerViewModel {
    var similarGroups: [CleanupGroup] = []
    var wasteItems: [MediaItem] = []
    var isScanning = false
    var scanProgress: Double = 0

    func scanSimilarPhotos(services: AppServiceContainer) async {
        isScanning = true
        defer { isScanning = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let items = services.photoLibrary.buildMediaItems(from: fetchResult)

        similarGroups = await services.imageSimilarity.findSimilarGroups(
            from: items,
            using: services.photoLibrary
        )

        services.cleanupCoordinator.addGroups(similarGroups)
    }

    func scanWastePhotos(services: AppServiceContainer) async {
        isScanning = true
        defer { isScanning = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let allItems = services.photoLibrary.buildMediaItems(from: fetchResult)
        let engine = services.aiEngine
        let library = services.photoLibrary
        let size = CGSize(width: 300, height: 300)

        var waste: [MediaItem] = []
        let total = allItems.count

        for (index, item) in allItems.enumerated() {
            if let image = await library.thumbnail(for: item.asset, size: size) {
                let result = engine.detectWaste(image: image)
                if result.isWaste {
                    waste.append(item)
                }
            }
            if index % 50 == 0 {
                scanProgress = Double(index) / Double(total)
            }
        }

        wasteItems = waste
        scanProgress = 1.0

        let wasteGroup = CleanupGroup(type: .waste, items: waste, bestItemID: nil)
        services.cleanupCoordinator.addGroups([wasteGroup])
    }
}
