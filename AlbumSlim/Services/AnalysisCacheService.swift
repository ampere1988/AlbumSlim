import Foundation

@MainActor
final class AnalysisCacheService {
    /// 可重建的分析结果只写入系统可随时回收的 Caches 目录，并严格限制文件体积。
    /// Vision feature print 体积远大于分类结果，因此只保留在本次运行的内存 LRU 中。
    private struct StoredAnalysis: Codable {
        let assetIdentifier: String
        let isWaste: Bool
        let wasteReason: WasteReason?
        let analyzedAt: Date

        init(_ analysis: CachedAnalysis) {
            assetIdentifier = analysis.assetIdentifier
            isWaste = analysis.isWaste
            wasteReason = analysis.wasteReason
            analyzedAt = analysis.analyzedAt
        }

        func makeAnalysis() -> CachedAnalysis {
            let analysis = CachedAnalysis(assetIdentifier: assetIdentifier)
            analysis.isWaste = isWaste
            analysis.wasteReason = wasteReason
            analysis.analyzedAt = analyzedAt
            return analysis
        }
    }

    private static let cacheFileName = "analysis-results-v2.plist"
    private static let maximumDiskBytes = 768 * 1024
    private static let maximumStoredEntries = 8_000
    private static let maximumFeaturePrintEntries = 256

    private let cacheURL: URL?
    private var analyses: [String: CachedAnalysis] = [:]
    private var featurePrints: [String: Data] = [:]
    private var featurePrintOrder: [String] = []
    private var pendingChanges = 0
    private let autoSaveThreshold = 500

    init() {
        let fileManager = FileManager.default
        if let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.cacheURL = directory.appendingPathComponent(Self.cacheFileName)
        } else {
            self.cacheURL = nil
        }

        Self.removeLegacySwiftDataStore(using: fileManager)
        load()
        // 结果文件有硬上限，不能把上次的“全库已完成”进度带到新进程。
        // 重置后仍会跳过已缓存项，并补齐因空间预算未落盘的照片。
        ScanProgress.clear()
    }

    func cachedAnalysis(for assetID: String) -> CachedAnalysis? {
        analyses[assetID]
    }

    func cachedAssetIDs(from assetIDs: [String]) -> Set<String> {
        Set(assetIDs.filter { analyses[$0] != nil })
    }

    func saveWasteResult(assetID: String, isWaste: Bool, reason: WasteReason?) {
        let cached = analyses[assetID] ?? CachedAnalysis(assetIdentifier: assetID)
        cached.isWaste = isWaste
        cached.wasteReason = reason
        cached.analyzedAt = .now
        analyses[assetID] = cached
        pendingChanges += 1
        autoSaveIfNeeded()
    }

    func saveFeaturePrint(assetID: String, data: Data) {
        if featurePrints[assetID] == nil {
            featurePrintOrder.append(assetID)
        } else {
            featurePrintOrder.removeAll { $0 == assetID }
            featurePrintOrder.append(assetID)
        }
        featurePrints[assetID] = data

        while featurePrintOrder.count > Self.maximumFeaturePrintEntries {
            let oldest = featurePrintOrder.removeFirst()
            featurePrints.removeValue(forKey: oldest)
        }
    }

    func featurePrintData(for assetID: String) -> Data? {
        guard let data = featurePrints[assetID] else { return nil }
        featurePrintOrder.removeAll { $0 == assetID }
        featurePrintOrder.append(assetID)
        return data
    }

    func allCachedWasteIDs() -> Set<String> {
        Set(analyses.values.lazy.filter(\.isWaste).map(\.assetIdentifier))
    }

    func allWasteReasons() -> [String: WasteReason] {
        var reasons: [String: WasteReason] = [:]
        for analysis in analyses.values where analysis.isWaste {
            if let reason = analysis.wasteReason {
                reasons[analysis.assetIdentifier] = reason
            }
        }
        return reasons
    }

    func clearAllCache() {
        analyses.removeAll()
        featurePrints.removeAll()
        featurePrintOrder.removeAll()
        pendingChanges = 0
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        Self.removeLegacySwiftDataStore(using: .default)
    }

    func batchSave() {
        guard pendingChanges > 0 else { return }
        persist()
    }

    private func autoSaveIfNeeded() {
        if pendingChanges >= autoSaveThreshold {
            persist()
        }
    }

    private func load() {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              data.count <= Self.maximumDiskBytes,
              let stored = try? PropertyListDecoder().decode([StoredAnalysis].self, from: data)
        else {
            if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
            return
        }

        analyses = Dictionary(
            uniqueKeysWithValues: stored.map { ($0.assetIdentifier, $0.makeAnalysis()) }
        )
    }

    private func persist() {
        guard let cacheURL else {
            pendingChanges = 0
            return
        }

        var stored = analyses.values
            .sorted { $0.analyzedAt < $1.analyzedAt }
            .suffix(Self.maximumStoredEntries)
            .map(StoredAnalysis.init)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard var data = try? encoder.encode(stored) else { return }

        // 数据预算优先于命中率；超限时按最旧优先继续淘汰。
        while data.count > Self.maximumDiskBytes, stored.count > 1 {
            stored.removeFirst(max(1, stored.count / 5))
            guard let reduced = try? encoder.encode(stored) else { return }
            data = reduced
        }

        do {
            try data.write(to: cacheURL, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = cacheURL
            try? mutableURL.setResourceValues(values)
            pendingChanges = 0
        } catch {
            // 缓存写入失败不影响功能，下次保存继续重试。
        }
    }

    /// 旧版本把大型 Vision feature print 写在默认 SwiftData 数据库。
    /// 当前项目没有其他 SwiftData 用户，因此只清理这些精确命名的旧文件。
    private static func removeLegacySwiftDataStore(using fileManager: FileManager) {
        guard let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
