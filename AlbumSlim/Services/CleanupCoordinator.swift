import Foundation
import Photos

@MainActor @Observable
final class CleanupCoordinator {
    private(set) var pendingGroups: [CleanupGroup] = []
    private(set) var totalSavableSize: Int64 = 0

    func addGroups(_ groups: [CleanupGroup]) {
        pendingGroups.append(contentsOf: groups)
        recalculateSavable()
    }

    func removeGroup(_ group: CleanupGroup) {
        pendingGroups.removeAll { $0.id == group.id }
        recalculateSavable()
    }

    func clearAll() {
        pendingGroups.removeAll()
        totalSavableSize = 0
    }

    /// 执行删除，返回实际释放的空间大小
    func executeCleanup(groups: [CleanupGroup]) async throws -> Int64 {
        var freedSize: Int64 = 0

        for group in groups {
            let assetsToDelete: [PHAsset]
            if let bestID = group.bestItemID {
                assetsToDelete = group.items.filter { $0.id != bestID }.map(\.asset)
            } else {
                assetsToDelete = group.items.map(\.asset)
            }

            let itemsInGroup = group.items
            let sizeToFree = assetsToDelete.reduce(Int64(0)) { total, asset in
                let matchingItem = itemsInGroup.first { $0.asset == asset }
                return total + (matchingItem?.fileSize ?? 0)
            }

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSFastEnumeration)
            }

            freedSize += sizeToFree
        }

        // 清理已执行的分组
        let executedIDs = Set(groups.map(\.id))
        pendingGroups.removeAll { executedIDs.contains($0.id) }
        recalculateSavable()

        return freedSize
    }

    private func recalculateSavable() {
        totalSavableSize = pendingGroups.reduce(0) { $0 + $1.savableSize }
    }
}
