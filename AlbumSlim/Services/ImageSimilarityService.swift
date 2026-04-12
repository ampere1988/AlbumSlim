import Foundation
import Vision
import Photos

final class ImageSimilarityService: Sendable {

    func findSimilarGroups(from items: [MediaItem], using photoLibrary: PhotoLibraryService, cache: AnalysisCacheService, onProgress: @escaping @MainActor (Double) -> Void) async -> [CleanupGroup] {
        let timeGroups = groupByTimeWindow(items)
        var allGroups: [CleanupGroup] = []
        let totalGroups = timeGroups.count

        for (index, group) in timeGroups.enumerated() {
            let similar = await findSimilarInGroup(group, using: photoLibrary, cache: cache)
            allGroups.append(contentsOf: similar)
            await onProgress(Double(index + 1) / Double(max(totalGroups, 1)))
        }

        return allGroups
    }

    // MARK: - Private

    /// 按时间窗口分组，超大组会拆分为子组避免 O(n²) 爆炸
    private func groupByTimeWindow(_ items: [MediaItem]) -> [[MediaItem]] {
        guard !items.isEmpty else { return [] }

        let sorted = items.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        var groups: [[MediaItem]] = []
        var currentGroup: [MediaItem] = [sorted[0]]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1].creationDate ?? .distantPast
            let curr = sorted[i].creationDate ?? .distantPast
            if curr.timeIntervalSince(prev) <= AppConstants.Similarity.timeWindowSeconds {
                currentGroup.append(sorted[i])
            } else {
                if currentGroup.count > 1 { groups.append(currentGroup) }
                currentGroup = [sorted[i]]
            }
        }
        if currentGroup.count > 1 { groups.append(currentGroup) }

        // 拆分超大组（>200），避免 O(n²) 相似度计算导致卡顿和 OOM
        let maxGroupSize = 200
        var result: [[MediaItem]] = []
        for group in groups {
            if group.count > maxGroupSize {
                for chunkStart in stride(from: 0, to: group.count, by: maxGroupSize) {
                    let chunkEnd = min(chunkStart + maxGroupSize, group.count)
                    let chunk = Array(group[chunkStart..<chunkEnd])
                    if chunk.count > 1 { result.append(chunk) }
                }
            } else {
                result.append(group)
            }
        }

        return result
    }

    private func findSimilarInGroup(_ items: [MediaItem], using photoLibrary: PhotoLibraryService, cache: AnalysisCacheService) async -> [CleanupGroup] {
        let engine = AIAnalysisEngine()
        let size = CGSize(width: 300, height: 300)

        var featurePrints: [(item: MediaItem, fp: VNFeaturePrintObservation)] = []

        // 分批处理，每批后 yield + 批量 save
        let batchSize = AppConstants.Analysis.batchSize
        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let batch = items[batchStart..<batchEnd]
            for item in batch {
                let assetID = item.asset.localIdentifier

                // 尝试从缓存读取特征向量
                let cachedData = await MainActor.run { cache.featurePrintData(for: assetID) }
                if let cachedData,
                   let fp = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: cachedData) {
                    featurePrints.append((item: item, fp: fp))
                    continue
                }

                if let image = await photoLibrary.thumbnail(for: item.asset, size: size) {
                    let fp: VNFeaturePrintObservation? = autoreleasepool {
                        guard let cgImage = image.cgImage else { return nil }
                        return engine.featurePrint(for: cgImage)
                    }
                    if let fp {
                        featurePrints.append((item: item, fp: fp))
                        // 缓存特征向量
                        if let data = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true) {
                            await MainActor.run { cache.saveFeaturePrint(assetID: assetID, data: data) }
                        }
                    }
                }
            }
            await MainActor.run { cache.batchSave() }
            await Task.yield()
        }

        var visited = Set<String>()
        var groups: [CleanupGroup] = []

        for i in 0..<featurePrints.count {
            guard !visited.contains(featurePrints[i].item.id) else { continue }
            var similarItems = [featurePrints[i].item]

            for j in (i + 1)..<featurePrints.count {
                guard !visited.contains(featurePrints[j].item.id) else { continue }
                var distance: Float = 0
                try? featurePrints[i].fp.computeDistance(&distance, to: featurePrints[j].fp)
                let similarity = 1.0 - distance
                if similarity >= AppConstants.Similarity.highThreshold {
                    similarItems.append(featurePrints[j].item)
                    visited.insert(featurePrints[j].item.id)
                }
            }

            if similarItems.count > 1 {
                visited.insert(featurePrints[i].item.id)
                let best = similarItems.max(by: { $0.fileSize < $1.fileSize })
                groups.append(CleanupGroup(type: .similar, items: similarItems, bestItemID: best?.id))
            }
        }

        return groups
    }
}
