import Foundation
import Vision
import Photos

@MainActor
final class ImageSimilarityService {

    func findSimilarGroups(from items: [MediaItem], using photoLibrary: PhotoLibraryService) async -> [CleanupGroup] {
        // 按时间窗口预分组，减少计算量
        let timeGroups = groupByTimeWindow(items)
        var allGroups: [CleanupGroup] = []

        for group in timeGroups {
            let similar = await findSimilarInGroup(group, using: photoLibrary)
            allGroups.append(contentsOf: similar)
        }

        return allGroups
    }

    // MARK: - Private

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

        return groups
    }

    private func findSimilarInGroup(_ items: [MediaItem], using photoLibrary: PhotoLibraryService) async -> [CleanupGroup] {
        let engine = AIAnalysisEngine()
        let size = CGSize(width: 300, height: 300)

        // 提取特征向量
        var featurePrints: [(item: MediaItem, fp: VNFeaturePrintObservation)] = []

        for item in items {
            if let image = await photoLibrary.thumbnail(for: item.asset, size: size),
               let cgImage = image.cgImage,
               let fp = engine.featurePrint(for: cgImage) {
                featurePrints.append((item: item, fp: fp))
            }
        }

        // 计算相似度，聚类
        var visited = Set<String>()
        var groups: [CleanupGroup] = []

        for i in 0..<featurePrints.count {
            guard !visited.contains(featurePrints[i].item.id) else { continue }
            var similarItems = [featurePrints[i].item]

            for j in (i + 1)..<featurePrints.count {
                guard !visited.contains(featurePrints[j].item.id) else { continue }
                var distance: Float = 0
                try? featurePrints[i].fp.computeDistance(&distance, to: featurePrints[j].fp)
                // distance 越小越相似，转换为相似度
                let similarity = 1.0 - distance
                if similarity >= AppConstants.Similarity.highThreshold {
                    similarItems.append(featurePrints[j].item)
                    visited.insert(featurePrints[j].item.id)
                }
            }

            if similarItems.count > 1 {
                visited.insert(featurePrints[i].item.id)
                // 推荐保留文件最大（通常质量最好）的一张
                let best = similarItems.max(by: { $0.fileSize < $1.fileSize })
                groups.append(CleanupGroup(type: .similar, items: similarItems, bestItemID: best?.id))
            }
        }

        return groups
    }
}
