import XCTest
@testable import AlbumSlim

@MainActor
final class SwipeCleanViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SwipeCleanProgressStore.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SwipeCleanProgressStore.storageKey)
        super.tearDown()
    }

    func testInitialStateIsEmpty() {
        let vm = SwipeCleanViewModel()
        XCTAssertNil(vm.current)
        XCTAssertFalse(vm.canUndo)
        XCTAssertEqual(vm.processedCount, 0)
    }

    func testAdvanceMovesToNextItem() {
        let vm = SwipeCleanViewModel()
        vm.injectQueueForTesting(ids: ["a", "b", "c"])
        XCTAssertEqual(vm.currentIDForTesting, "a")
        vm.advanceForTesting()
        XCTAssertEqual(vm.currentIDForTesting, "b")
        XCTAssertEqual(vm.processedCount, 1)
    }

    func testUpcomingIsTheCardBehindCurrent() {
        let vm = SwipeCleanViewModel()
        vm.injectQueueForTesting(ids: ["a", "b", "c"])
        XCTAssertEqual(vm.upcomingIDForTesting, "b")
    }

    func testIsFinishedWhenQueueExhausted() {
        let vm = SwipeCleanViewModel()
        vm.injectQueueForTesting(ids: ["a"])
        XCTAssertFalse(vm.isFinished)
        vm.advanceForTesting()
        XCTAssertTrue(vm.isFinished)
        XCTAssertNil(vm.currentIDForTesting)
    }

    func testUndoRestoresPreviousCard() {
        let vm = SwipeCleanViewModel()
        vm.injectQueueForTesting(ids: ["a", "b"])
        vm.advanceForTesting()
        XCTAssertEqual(vm.currentIDForTesting, "b")
        vm.rewindForTesting()
        XCTAssertEqual(vm.currentIDForTesting, "a")
        XCTAssertEqual(vm.processedCount, 0)
    }

    func testRewindAtStartIsNoOp() {
        let vm = SwipeCleanViewModel()
        vm.injectQueueForTesting(ids: ["a"])
        vm.rewindForTesting()
        XCTAssertEqual(vm.currentIDForTesting, "a")
        XCTAssertEqual(vm.processedCount, 0)
    }
}
