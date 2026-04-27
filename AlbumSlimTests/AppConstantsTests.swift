import Foundation
import Testing
import UIKit
@testable import AlbumSlim

@Suite("AppConstants 测试")
struct AppConstantsTests {

    @MainActor
    @Test("fullImageTargetSize 锁在 1600pt 上限")
    func fullImageTargetSize_capsAt1600Points() {
        let size = AppConstants.Shuffle.fullImageTargetSize
        let cap = 1600 * UIScreen.main.scale
        #expect(size.width <= cap)
        #expect(size.height <= cap)
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    @Test("fullImageSemaphoreLimit 在保守范围")
    func fullImageSemaphoreLimit_isConservative() {
        #expect(AppConstants.Shuffle.fullImageSemaphoreLimit <= 3)
        #expect(AppConstants.Shuffle.fullImageSemaphoreLimit >= 1)
    }
}
