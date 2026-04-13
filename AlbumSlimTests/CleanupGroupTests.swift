import Testing
import Photos
@testable import AlbumSlim

@Suite("CleanupGroup 测试")
struct CleanupGroupTests {

    @Test("GroupType 原始值")
    func groupTypeRawValues() {
        #expect(CleanupGroup.GroupType.similar.rawValue == "similar")
        #expect(CleanupGroup.GroupType.burst.rawValue == "burst")
        #expect(CleanupGroup.GroupType.waste.rawValue == "waste")
        #expect(CleanupGroup.GroupType.screenshot.rawValue == "screenshot")
        #expect(CleanupGroup.GroupType.largeVideo.rawValue == "largeVideo")
    }
}
