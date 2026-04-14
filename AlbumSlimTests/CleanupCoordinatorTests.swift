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
        #expect(!coordinator.isCategoryFresh(.waste, libraryVersion: 0))
    }

    @Test("clearAll 清空所有分组")
    func clearAll() {
        let coordinator = CleanupCoordinator()
        coordinator.clearAll()
        #expect(coordinator.pendingGroups.isEmpty)
        #expect(coordinator.totalSavableSize == 0)
    }

    @Test("isCategoryFresh 基于相册版本号判断")
    func categoryFreshness() {
        let coordinator = CleanupCoordinator()
        // 未扫描时不新鲜
        #expect(!coordinator.isCategoryFresh(.waste, libraryVersion: 0))

        // 标记扫描后新鲜
        coordinator.markCategoryScanned(.waste, libraryVersion: 1)
        #expect(coordinator.isCategoryFresh(.waste, libraryVersion: 1))

        // 相册版本变化后失效
        #expect(!coordinator.isCategoryFresh(.waste, libraryVersion: 2))

        // 其他分类不受影响
        #expect(!coordinator.isCategoryFresh(.similar, libraryVersion: 1))
    }
}
