import Foundation
import SwiftData

@MainActor
final class AnalysisCacheService {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init() {
        let schema = Schema([CachedAnalysis.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [config])
        self.modelContext = ModelContext(modelContainer)
    }

    func cachedAnalysis(for assetID: String) -> CachedAnalysis? {
        let predicate = #Predicate<CachedAnalysis> { $0.assetIdentifier == assetID }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    func cachedAssetIDs(from assetIDs: [String]) -> Set<String> {
        let descriptor = FetchDescriptor<CachedAnalysis>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let allIDs = Set(all.map(\.assetIdentifier))
        return allIDs.intersection(assetIDs)
    }

    func saveWasteResult(assetID: String, isWaste: Bool, reason: WasteReason?) {
        if let existing = cachedAnalysis(for: assetID) {
            existing.isWaste = isWaste
            existing.wasteReason = reason
            existing.analyzedAt = .now
        } else {
            let cached = CachedAnalysis(assetIdentifier: assetID)
            cached.isWaste = isWaste
            cached.wasteReason = reason
            cached.analyzedAt = .now
            modelContext.insert(cached)
        }
        try? modelContext.save()
    }

    func saveFeaturePrint(assetID: String, data: Data) {
        if let existing = cachedAnalysis(for: assetID) {
            existing.featurePrintData = data
            existing.analyzedAt = .now
        } else {
            let cached = CachedAnalysis(assetIdentifier: assetID)
            cached.featurePrintData = data
            cached.analyzedAt = .now
            modelContext.insert(cached)
        }
        try? modelContext.save()
    }

    func featurePrintData(for assetID: String) -> Data? {
        cachedAnalysis(for: assetID)?.featurePrintData
    }

    func allCachedWasteIDs() -> Set<String> {
        let predicate = #Predicate<CachedAnalysis> { $0.isWaste == true }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return Set(results.map(\.assetIdentifier))
    }

    func batchSave() {
        try? modelContext.save()
    }
}
