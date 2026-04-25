import Testing
import Foundation
@testable import AlbumSlim

@Suite("TrashService 去重与过滤")
@MainActor
struct TrashServiceFilterTests {

    private func resetUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "trashedScreenshotItems")
        UserDefaults.standard.removeObject(forKey: "trashedItems_v2")
        UserDefaults.standard.set(true, forKey: "trashItemsMigrated_v2")
    }

    private func makeItem(id: String, source: TrashSource = .other) -> TrashedItem {
        TrashedItem(id: id, fileSize: 100, creationDate: nil, trashedDate: Date(),
                    sourceModule: source, mediaType: .photo)
    }

    @Test("trashedAssetIDs 反映当前所有软删除项 ID")
    func assetIDsReflectsItems() {
        resetUserDefaults()
        let service = TrashService()
        UserDefaults.standard.set(try! JSONEncoder().encode([makeItem(id: "a"), makeItem(id: "b")]),
                                  forKey: "trashedItems_v2")
        let s2 = TrashService()
        #expect(s2.trashedAssetIDs == Set(["a", "b"]))
        #expect(s2.contains("a"))
        #expect(!s2.contains("z"))
    }

    @Test("restore 后从 trashedAssetIDs 移除")
    func restoreRemovesFromIDs() {
        resetUserDefaults()
        UserDefaults.standard.set(try! JSONEncoder().encode([makeItem(id: "a"), makeItem(id: "b")]),
                                  forKey: "trashedItems_v2")
        let service = TrashService()
        service.restore(["a"])
        #expect(service.trashedAssetIDs == Set(["b"]))
    }
}
