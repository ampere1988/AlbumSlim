import Foundation
import Testing
import UIKit
@testable import AlbumSlim

@Suite("ShuffleFeedViewModel 内存警告测试")
struct ShuffleFeedViewModelMemoryTests {

    @MainActor
    @Test("收到 didReceiveMemoryWarning 时清空所有缓存")
    func memoryWarning_clearsCaches() async {
        let vm = ShuffleFeedViewModel()
        vm.injectThumbnailForTesting(UIImage(), id: "fake-thumb")
        vm.injectFullImageForTesting(UIImage(), id: "fake-full")
        #expect(vm.cachedThumbnail(for: "fake-thumb") != nil)
        #expect(vm.cachedFullImage(for: "fake-full") != nil)

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // 让 NotificationCenter main queue 闭包以及 Task { @MainActor } 跑完
        // 给两次 yield 通常足够；保险加少量延迟
        for _ in 0..<3 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        #expect(vm.cachedThumbnail(for: "fake-thumb") == nil)
        #expect(vm.cachedFullImage(for: "fake-full") == nil)
    }
}
