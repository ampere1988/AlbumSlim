import Testing
import Foundation
@testable import AlbumSlim

@Suite("TrashService 旧数据迁移")
@MainActor
struct TrashServiceMigrationTests {

    private func resetUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "trashedScreenshotItems")
        UserDefaults.standard.removeObject(forKey: "trashedItems_v2")
        UserDefaults.standard.removeObject(forKey: "trashItemsMigrated_v2")
    }

    @Test("旧 key 中的截图数据迁移到新 key 并标记为 .screenshot 来源")
    func migrateScreenshotKey() throws {
        resetUserDefaults()
        struct LegacyItem: Codable {
            let id: String
            let fileSize: Int64
            let creationDate: Date?
            let trashedDate: Date
        }
        let legacy = [
            LegacyItem(id: "asset-1", fileSize: 1024, creationDate: Date(), trashedDate: Date()),
            LegacyItem(id: "asset-2", fileSize: 2048, creationDate: nil, trashedDate: Date())
        ]
        let data = try JSONEncoder().encode(legacy)
        UserDefaults.standard.set(data, forKey: "trashedScreenshotItems")

        let service = TrashService()

        #expect(service.trashedItems.count == 2)
        #expect(service.trashedItems.allSatisfy { $0.sourceModule == .screenshot })
        #expect(service.trashedItems.allSatisfy { $0.mediaType == .screenshot })
        #expect(UserDefaults.standard.bool(forKey: "trashItemsMigrated_v2"))
        #expect(UserDefaults.standard.data(forKey: "trashedScreenshotItems") == nil)
    }

    @Test("迁移幂等：第二次启动不重复迁移")
    func migrateIdempotent() throws {
        resetUserDefaults()
        UserDefaults.standard.set(true, forKey: "trashItemsMigrated_v2")
        let dummy = "x".data(using: .utf8)!
        UserDefaults.standard.set(dummy, forKey: "trashedScreenshotItems")

        let service = TrashService()
        #expect(service.trashedItems.isEmpty)
    }

    @Test("旧 key 中数据损坏时仍标记迁移完成且 trashedItems 为空")
    func migrateCorruptLegacyData() throws {
        resetUserDefaults()
        // 写入无法解码为 [LegacyItem] 的损坏数据
        UserDefaults.standard.set("not a valid json".data(using: .utf8)!, forKey: "trashedScreenshotItems")

        let service = TrashService()

        #expect(service.trashedItems.isEmpty)
        #expect(UserDefaults.standard.bool(forKey: "trashItemsMigrated_v2"))
        #expect(UserDefaults.standard.data(forKey: "trashedScreenshotItems") == nil)
    }

    @Test("无遗留数据时也正确标记迁移完成")
    func migrateNoLegacyData() throws {
        resetUserDefaults()
        // 不写入任何 legacy 数据

        let service = TrashService()

        #expect(service.trashedItems.isEmpty)
        #expect(UserDefaults.standard.bool(forKey: "trashItemsMigrated_v2"))
    }
}
