import Foundation
import SwiftData

@MainActor
final class AnalysisCacheService {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private var pendingChanges = 0
    private let autoSaveThreshold = 50

    init() {
        let schema = Schema([CachedAnalysis.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法初始化 ModelContainer: \(error)")
        }
        self.modelContext = ModelContext(modelContainer)
    }

    func cachedAnalysis(for assetID: String) -> CachedAnalysis? {
        let predicate = #Predicate<CachedAnalysis> { $0.assetIdentifier == assetID }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    func cachedAssetIDs(from assetIDs: [String]) -> Set<String> {
        // 分批查询避免 predicate 过大，每批 500 个
        var result = Set<String>()
        let batchSize = 500
        for batchStart in stride(from: 0, to: assetIDs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, assetIDs.count)
            let batch = Set(assetIDs[batchStart..<batchEnd])
            let predicate = #Predicate<CachedAnalysis> { batch.contains($0.assetIdentifier) }
            let descriptor = FetchDescriptor(predicate: predicate)
            if let fetched = try? modelContext.fetch(descriptor) {
                for item in fetched {
                    result.insert(item.assetIdentifier)
                }
            }
        }
        return result
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
        pendingChanges += 1
        autoSaveIfNeeded()
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
        pendingChanges += 1
        autoSaveIfNeeded()
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

    func allWasteReasons() -> [String: WasteReason] {
        let predicate = #Predicate<CachedAnalysis> { $0.isWaste == true }
        let descriptor = FetchDescriptor(predicate: predicate)
        let results = (try? modelContext.fetch(descriptor)) ?? []
        var reasons: [String: WasteReason] = [:]
        for item in results {
            if let reason = item.wasteReason {
                reasons[item.assetIdentifier] = reason
            }
        }
        return reasons
    }

    func batchSave() {
        guard pendingChanges > 0 else { return }
        do {
            try modelContext.save()
        } catch {
            print("[AnalysisCacheService] 保存失败: \(error)")
        }
        pendingChanges = 0
    }

    private func autoSaveIfNeeded() {
        if pendingChanges >= autoSaveThreshold {
            batchSave()
        }
    }
}
