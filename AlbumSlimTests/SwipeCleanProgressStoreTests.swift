import XCTest
@testable import AlbumSlim

@MainActor
final class SwipeCleanProgressStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SwipeCleanProgressStore.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SwipeCleanProgressStore.storageKey)
        super.tearDown()
    }

    func testMarkKeptPersists() {
        let store = SwipeCleanProgressStore()
        store.markKept("asset-1")
        XCTAssertTrue(store.isKept("asset-1"))

        // 新实例从 UserDefaults 恢复
        let reloaded = SwipeCleanProgressStore()
        XCTAssertTrue(reloaded.isKept("asset-1"))
    }

    func testUnmarkKeptSupportsUndo() {
        let store = SwipeCleanProgressStore()
        store.markKept("asset-1")
        store.unmarkKept("asset-1")
        XCTAssertFalse(store.isKept("asset-1"))
    }

    func testPendingExcludesKeptAndTrashed() {
        let store = SwipeCleanProgressStore()
        store.markKept("a")
        let pending = store.pendingIDs(from: ["a", "b", "c"], excluding: ["c"])
        // a 已保留、c 已在垃圾桶，只剩 b
        XCTAssertEqual(pending, ["b"])
    }

    func testPendingPreservesInputOrder() {
        let store = SwipeCleanProgressStore()
        let pending = store.pendingIDs(from: ["z", "y", "x"], excluding: [])
        XCTAssertEqual(pending, ["z", "y", "x"])
    }

    func testKeptCountCountsOnlyWithinBucket() {
        let store = SwipeCleanProgressStore()
        store.markKept("a")
        store.markKept("outside")
        XCTAssertEqual(store.keptCount(in: ["a", "b"]), 1)
    }

    func testResetBucketClearsOnlyItsOwnIDs() {
        let store = SwipeCleanProgressStore()
        store.markKept("a")
        store.markKept("b")
        store.resetBucket(assetIDs: ["a"])
        XCTAssertFalse(store.isKept("a"))
        XCTAssertTrue(store.isKept("b"))
    }
}
