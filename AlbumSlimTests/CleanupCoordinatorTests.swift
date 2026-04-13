import Testing
@testable import AlbumSlim

@Suite("CleanupCoordinator 测试")
@MainActor
struct CleanupCoordinatorTests {

    @Test("初始状态为空")
    func initialState() {
        let coordinator = CleanupCoordinator()
        #expect(coordinator.pendingGroups.isEmpty)
        #expect(coordinator.totalSavableSize == 0)
        #expect(coordinator.lastScanDate == nil)
        #expect(!coordinator.isScanFresh)
    }

    @Test("clearAll 清空所有分组")
    func clearAll() {
        let coordinator = CleanupCoordinator()
        // 手动验证 clearAll 不会 crash
        coordinator.clearAll()
        #expect(coordinator.pendingGroups.isEmpty)
        #expect(coordinator.totalSavableSize == 0)
    }

    @Test("isScanFresh 过期判断")
    func scanFreshness() {
        let coordinator = CleanupCoordinator()
        // 没有 lastScanDate 时不新鲜
        #expect(!coordinator.isScanFresh)
    }
}
