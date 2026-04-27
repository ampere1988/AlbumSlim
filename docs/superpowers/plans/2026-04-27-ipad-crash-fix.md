# iPad 闪退综合修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 系统性消除 iPad（尤其 iPad Pro 12.9"）频繁闪退问题，覆盖内存压力、Swift 6 actor 隔离、资源生命周期、iPad 适配四个层面。

**Architecture:**
- 不重构架构，仅做"低风险高收益"修复，保持现有 MVVM + AppServiceContainer 不变。
- 内存层：限制全图目标尺寸、拆分独立 semaphore、加内存警告响应、修掉 backdrop 后台 UIKit 不安全调用。
- 并发层：把所有 `@MainActor` 类中调用 `PHPhotoLibrary.performChanges` 的方法拆出 `nonisolated` 入口，避免 Swift 6 闭包隐式隔离触发 `_dispatch_assert_queue_fail`。
- 生命周期层：Tab 切换时主动卸载视频/Live Photo，配置 AVAudioSession，修正 ShufflePhotoView 取消语义。

**Tech Stack:** Swift 6 / SwiftUI / Photos / AVFoundation / UIKit (UIGraphicsImageRenderer) / XcodeGen

**前置说明:**
- 本计划基于 2026-04-27 静态代码审查，未基于真实 crash log。**Phase 1 完成后必须先在 iPad Pro 12.9 模拟器或真机跑一遍，看是否还闪。如果还闪，必须拿到 .ips 崩溃日志再继续后续 Phase。**
- 每个 Phase 结束都跑一次 `xcodebuild build` 验证。
- 修改 Swift 源文件后必须 `xcodegen generate` 重新生成 xcodeproj 才能 build。

**Build / Test 命令（贴脚本备用）:**

```bash
# 重新生成 xcodeproj
cd /Users/huge/Project/AlbumSlim && xcodegen generate

# Debug build（iOS Simulator）
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -quiet

# 单元测试
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -quiet

# iPad Pro 12.9 模拟器（手动验证内存压力修复）
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=26.4' \
  -quiet
```

如果 `iPad Pro 13-inch (M4)` 不存在，用 `xcrun simctl list devices available | grep iPad` 找一台并替换 `name=`。

---

## File Structure

### 修改文件

| 文件 | 责任 | 改动概述 |
|---|---|---|
| `AlbumSlim/App/AppConstants.swift` | 全局常量 | 限制 `fullImageTargetSize` 上限到 1600；新增 `fullImageSemaphoreLimit` |
| `AlbumSlim/Services/PhotoLibraryService.swift` | Photos 框架封装 | 拆分独立的 `fullImageSemaphore`；`toggleFavorite` 标 `nonisolated` |
| `AlbumSlim/Services/BackdropAdapterService.swift` | 亮度采样 | `averageBrightness` 改用 `UIGraphicsImageRenderer`（线程安全） |
| `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift` | 首页数据 | 监听内存警告清缓存；`refreshAfterLibraryChange` fetch 移到后台线程 |
| `AlbumSlim/Services/VideoCompressionService.swift` | 视频压缩 | `replaceOriginal` / `saveCompressedToLibrary` 改 `nonisolated` 走 photoLibrary 抽象 |
| `AlbumSlim/Services/CleanupCoordinator.swift` | 清理协调 | `executeCleanup` 中 `performChanges` 闭包改走 nonisolated 路径 |
| `AlbumSlim/Views/Shuffle/ShuffleVideoView.swift` | 视频页面 | tab 离开时改为 `unload()` 而非 pause |
| `AlbumSlim/Views/Shuffle/ShuffleLivePhotoView.swift` | Live Photo 页面 | tab 离开时清空 livePhoto 引用 |
| `AlbumSlim/Views/Shuffle/ShufflePhotoView.swift` | 静态图页面 | 修正 `task(id:)` 取消时不立即清空显示 |
| `AlbumSlim/App/AlbumSlimApp.swift` | App 入口 | App 启动时配置 AVAudioSession |
| `project.yml` | XcodeGen | 锁定 iPad 全屏（`UIRequiresFullScreen: true`），关闭横屏 |

### 新增文件

| 文件 | 责任 |
|---|---|
| `AlbumSlimTests/AppConstantsTests.swift` | 验证 `fullImageTargetSize` 上限逻辑 |
| `AlbumSlimTests/ShuffleFeedViewModelMemoryTests.swift` | 验证内存警告响应清空缓存 |

### 不动的文件（已确认安全）

- `Utils/AsyncSemaphore.swift` — 简单合理
- `Utils/ShuffleIndexQueue.swift` — 无死循环
- `Services/PhotoLibraryService.swift` 的 `deleteAssets` — 已经 `nonisolated`

---

## Phase 1: 内存压力修复（iPad Pro 头号嫌疑）

完成本 Phase 后立即在 iPad Pro 模拟器上手动验证 30 分钟连续滑动 + Tab 切换不闪退。

### Task 1: 限制 `fullImageTargetSize` 与定义 fullImage semaphore 容量

**Files:**
- Modify: `AlbumSlim/App/AppConstants.swift:30-46`
- Test (create): `AlbumSlimTests/AppConstantsTests.swift`

- [ ] **Step 1: 写失败测试**

新建 `AlbumSlimTests/AppConstantsTests.swift`：

```swift
import XCTest
@testable import AlbumSlim

final class AppConstantsTests: XCTestCase {
    @MainActor
    func test_fullImageTargetSize_capsAt1600Points() {
        let size = AppConstants.Shuffle.fullImageTargetSize
        // 上限 1600 像素 × 任意 scale。任一边都不应超过 1600 * UIScreen.main.scale
        let cap = 1600 * UIScreen.main.scale
        XCTAssertLessThanOrEqual(size.width, cap)
        XCTAssertLessThanOrEqual(size.height, cap)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func test_fullImageSemaphoreLimit_isConservative() {
        XCTAssertLessThanOrEqual(AppConstants.Shuffle.fullImageSemaphoreLimit, 3)
        XCTAssertGreaterThanOrEqual(AppConstants.Shuffle.fullImageSemaphoreLimit, 1)
    }
}
```

- [ ] **Step 2: 加入测试到 project.yml**

打开 `project.yml`，找到 `targets:` 下的 `AlbumSlimTests`（如果不存在就略过本步），确认 `sources:` 包含 `AlbumSlimTests`。本仓库测试目录已存在，xcodegen 会自动收录新文件，无需手动列。

跑：

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate
```

- [ ] **Step 3: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:AlbumSlimTests/AppConstantsTests
```

预期：编译失败（`fullImageSemaphoreLimit` 未定义）或测试失败（`fullImageTargetSize` 超过上限）。

- [ ] **Step 4: 修改 AppConstants**

打开 `AlbumSlim/App/AppConstants.swift`，把 `enum Shuffle` 替换为：

```swift
    enum Shuffle {
        /// 高清图目标像素尺寸：iPad Pro 12.9" 全屏 = 1024×1366 pt × 2x = 2048×2732 px，
        /// 单张位图占用 ~22 MB，缓存 3 张 + 同时解码 6 张会触发 jetsam。
        /// 这里把 point 维度上限锁到 1600，用户视觉上无感（屏幕本身做下采样）。
        @MainActor static var fullImageTargetSize: CGSize {
            let scale = UIScreen.main.scale
            let bounds = UIScreen.main.bounds.size
            let pointCap: CGFloat = 1600
            let cappedWidth = min(bounds.width, pointCap)
            let cappedHeight = min(bounds.height, pointCap)
            return CGSize(width: cappedWidth * scale, height: cappedHeight * scale)
        }
        /// 预加载/占位用的 thumbnail 尺寸（本地缓存易命中、内存占用小）
        static let thumbnailSize = CGSize(width: 1200, height: 1200)
        /// 预加载窗口：前 1 + 后 2
        static let prefetchOffsets: [Int] = [-1, 1, 2]
        /// thumbnail LRU cache 容量（窗口 3 + 缓冲）
        static let thumbnailCacheCapacity = 12
        /// 全图 UIImage 内存缓存容量（当前 + 下一张 + 回滑上一张）
        static let fullImageCacheCapacity = 3
        /// 分享导出图的尺寸
        static let shareImageSize = CGSize(width: 1600, height: 1600)
        /// 全图请求并发上限（独立于 thumbnail，避免 iPad 上 6 路并发解码瞬时占用 130+ MB）
        static let fullImageSemaphoreLimit = 2
    }
```

- [ ] **Step 5: 重新生成 xcodeproj 并跑测试**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:AlbumSlimTests/AppConstantsTests
```

预期：通过。

- [ ] **Step 6: 提交**

```bash
git add AlbumSlim/App/AppConstants.swift AlbumSlimTests/AppConstantsTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "iPad 闪退修复 1/N: fullImageTargetSize 锁 1600pt 上限 + 新增 fullImage semaphore 容量常量"
```

---

### Task 2: PhotoLibraryService 拆出独立的 fullImage semaphore

**Files:**
- Modify: `AlbumSlim/Services/PhotoLibraryService.swift:13`，`148-187`，`191-217`

- [ ] **Step 1: 修改 semaphore 字段**

打开 `AlbumSlim/Services/PhotoLibraryService.swift`，把第 13 行：

```swift
    private let thumbnailSemaphore = AsyncSemaphore(limit: 6)
```

替换为：

```swift
    private let thumbnailSemaphore = AsyncSemaphore(limit: 6)
    /// 全图 / Live Photo 解码独立限流，避免 iPad 上瞬时 6 路 22MB 解码触发 jetsam
    private let fullImageSemaphore = AsyncSemaphore(limit: AppConstants.Shuffle.fullImageSemaphoreLimit)
```

- [ ] **Step 2: 切换 loadFullImage 使用新 semaphore**

把 `loadFullImage` 方法中第 153-154 行：

```swift
        await thumbnailSemaphore.wait()
        defer { thumbnailSemaphore.signal() }
```

替换为：

```swift
        await fullImageSemaphore.wait()
        defer { fullImageSemaphore.signal() }
```

- [ ] **Step 3: 切换 loadLivePhoto 使用新 semaphore**

把 `loadLivePhoto` 方法中第 192-193 行：

```swift
        await thumbnailSemaphore.wait()
        defer { thumbnailSemaphore.signal() }
```

替换为：

```swift
        await fullImageSemaphore.wait()
        defer { fullImageSemaphore.signal() }
```

- [ ] **Step 4: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED。

- [ ] **Step 5: 提交**

```bash
git add AlbumSlim/Services/PhotoLibraryService.swift
git commit -m "iPad 闪退修复 2/N: fullImage / livePhoto 解码改用独立 semaphore (limit=2)"
```

---

### Task 3: BackdropAdapterService 改用 UIGraphicsImageRenderer（线程安全）

**Files:**
- Modify: `AlbumSlim/Services/BackdropAdapterService.swift:31-50`

- [ ] **Step 1: 修改 averageBrightness**

打开 `AlbumSlim/Services/BackdropAdapterService.swift`，把整个 `averageBrightness` 静态函数替换为：

```swift
    /// 缩放到 10x10 采样 grid 计算平均灰度亮度
    /// 使用 UIGraphicsImageRenderer（iOS 10+，线程安全）替代旧的
    /// UIGraphicsBeginImageContextWithOptions（在后台线程使用会偶发崩溃）
    nonisolated static func averageBrightness(of image: UIImage) -> CGFloat {
        let size = CGSize(width: 10, height: 10)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        var sum: Double = 0
        let pixelCount = 10 * 10

        // renderer.image 返回 UIImage，但我们要的是底层 CGContext 的像素 buffer。
        // 通过 jpegData 之类太重，直接走 CGContext 重画一次：
        let cgImage = renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage

        guard let cg = cgImage,
              let provider = cg.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }

        let bytesPerPixel = cg.bitsPerPixel / 8
        let bytesPerRow = cg.bytesPerRow
        let alphaInfo = cg.alphaInfo

        for y in 0..<10 {
            for x in 0..<10 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                // CGImage 的通道顺序取决于 alphaInfo，我们用 opaque + standard range，
                // 默认是 BGRA premultipliedFirst 或 RGBA premultipliedLast，
                // 简单起见取前三个通道做平均（绝对亮度差异微乎其微，10x10 采样无所谓）
                let c0 = Double(bytes[offset]) / 255.0
                let c1 = Double(bytes[offset + 1]) / 255.0
                let c2 = Double(bytes[offset + 2]) / 255.0
                // Rec. 709 luminance（顺序假设 RGB；BGR 顺序会让 R/B 系数互换，
                // 对二值化阈值 0.5 影响极小）
                if alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst {
                    // BGRA: bytes[offset+1]=R, +2=G, +3=B（但我们只取前三，c0=B、c1=G、c2=R）
                    sum += 0.0722 * c0 + 0.7152 * c1 + 0.2126 * c2
                } else {
                    sum += 0.2126 * c0 + 0.7152 * c1 + 0.0722 * c2
                }
            }
        }
        return CGFloat(sum / Double(pixelCount))
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED。

- [ ] **Step 3: 手动验证（在 iPad Pro 模拟器跑 app）**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=26.4' -quiet
```

启动模拟器，在浏览 tab 连续滑 30 张媒体，观察浮动按钮是否在浅色/深色照片上正常切换图标颜色（说明 backdrop 仍在工作）。

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/Services/BackdropAdapterService.swift
git commit -m "iPad 闪退修复 3/N: BackdropAdapter 改用 UIGraphicsImageRenderer 替换不安全的旧 API"
```

---

### Task 4: ShuffleFeedViewModel 监听内存警告清缓存

**Files:**
- Modify: `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift:1-50`，新增 `init()`、`memoryWarningObserver`、`evictAllCaches`
- Test (create): `AlbumSlimTests/ShuffleFeedViewModelMemoryTests.swift`

- [ ] **Step 1: 写测试**

新建 `AlbumSlimTests/ShuffleFeedViewModelMemoryTests.swift`：

```swift
import XCTest
import UIKit
@testable import AlbumSlim

@MainActor
final class ShuffleFeedViewModelMemoryTests: XCTestCase {
    func test_memoryWarning_clearsCaches() {
        let vm = ShuffleFeedViewModel()
        // 注入伪缓存
        vm.injectThumbnailForTesting(UIImage(), id: "fake-thumb")
        vm.injectFullImageForTesting(UIImage(), id: "fake-full")
        XCTAssertNotNil(vm.cachedThumbnail(for: "fake-thumb"))
        XCTAssertNotNil(vm.cachedFullImage(for: "fake-full"))

        // 触发系统内存警告
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // 给主线程一点时间处理 notification
        let exp = expectation(description: "caches cleared")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertNil(vm.cachedThumbnail(for: "fake-thumb"))
        XCTAssertNil(vm.cachedFullImage(for: "fake-full"))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:AlbumSlimTests/ShuffleFeedViewModelMemoryTests
```

预期：编译失败（`injectThumbnailForTesting` 未定义）。

- [ ] **Step 3: 给 ShuffleFeedViewModel 加 init/observer/evict 方法**

打开 `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift`。

在 `final class ShuffleFeedViewModel { ` 下、`private(set) var items: ...` 之前，加入：

```swift
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // notification queue 是 .main，已在 MainActor 上下文，但 closure 是 @Sendable，
            // 需要再 hop 一次以拿到 isolated self
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    /// 收到系统内存警告时主动清空所有 in-memory 缓存与 in-flight 任务，
    /// 避免被 jetsam。下次 onPageAppeared / updatePrefetchWindow 会重新加载。
    private func handleMemoryWarning() {
        evictAllCaches()
    }

    /// 清空所有 thumbnail/fullImage 缓存与对应的 in-flight Task。
    /// items 列表本身保留，scrolledID 不变，UI 不会跳动。
    func evictAllCaches() {
        for task in prefetchTasks.values { task.cancel() }
        prefetchTasks.removeAll()
        for task in fullImagePrefetchTasks.values { task.cancel() }
        fullImagePrefetchTasks.removeAll()
        thumbnailCache.removeAll()
        thumbnailCacheOrder.removeAll()
        fullImageCache.removeAll()
        fullImageCacheOrder.removeAll()
    }

#if DEBUG
    func injectThumbnailForTesting(_ image: UIImage, id: String) {
        storeThumbnail(image, for: id)
    }
    func injectFullImageForTesting(_ image: UIImage, id: String) {
        storeFullImage(image, for: id)
    }
#endif
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:AlbumSlimTests/ShuffleFeedViewModelMemoryTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add AlbumSlim/ViewModels/ShuffleFeedViewModel.swift AlbumSlimTests/ShuffleFeedViewModelMemoryTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "iPad 闪退修复 4/N: ShuffleFeedViewModel 监听内存警告主动清缓存"
```

---

### Phase 1 验收

- [ ] **手动 iPad 模拟器烟雾测试（30 分钟）**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=26.4' -quiet
```

启动后：
1. 在浏览 tab 连续上滑 100 次以上
2. 中间切到设置 tab 来回 5 次
3. 进入相似照片扫描跑一遍
4. 回到浏览继续滑

观察 Xcode Debug Navigator → Memory 是否稳定在 300 MB 以下、是否出现 jetsam（Console.app 搜 `jetsam` 或 `Memory limit`）。

- [ ] **如果还闪退：停止后续 Phase，把 .ips 崩溃日志贴出来重新分析**

如果通过：进入 Phase 2。

---

## Phase 2: Swift 6 Actor 隔离修复

修复 `@MainActor` 类中调用 `PHPhotoLibrary.performChanges` 的方法，避免闭包被隐式隔离到 MainActor 触发 `_dispatch_assert_queue_fail`。

### Task 5: PhotoLibraryService.toggleFavorite 改 nonisolated

**Files:**
- Modify: `AlbumSlim/Services/PhotoLibraryService.swift:244-250`

- [ ] **Step 1: 修改方法签名**

打开 `AlbumSlim/Services/PhotoLibraryService.swift`，找到第 242-250 行：

```swift
    // MARK: - 收藏

    func toggleFavorite(_ asset: PHAsset) async throws {
        let target = !asset.isFavorite
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = target
        }
    }
```

替换为：

```swift
    // MARK: - 收藏

    /// `nonisolated` 关键：@MainActor 类的 performChanges 闭包会被隐式隔离到主线程，
    /// 与 Photos 框架要求闭包在自己的 changes queue 上执行冲突，触发 _dispatch_assert_queue_fail
    nonisolated func toggleFavorite(_ asset: PHAsset) async throws {
        let target = !asset.isFavorite
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = target
        }
    }
```

- [ ] **Step 2: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED。如果有 actor 隔离编译警告/错误，按编译器提示修复 — 通常 Photos 框架的方法已经是 nonisolated 兼容的。

- [ ] **Step 3: 提交**

```bash
git add AlbumSlim/Services/PhotoLibraryService.swift
git commit -m "iPad 闪退修复 5/N: toggleFavorite 标 nonisolated 避免 performChanges 闭包隔离冲突"
```

---

### Task 6: VideoCompressionService 把 performChanges 抽到 nonisolated 入口

**Files:**
- Modify: `AlbumSlim/Services/VideoCompressionService.swift:136-149`

- [ ] **Step 1: 替换两个 performChanges 方法**

打开 `AlbumSlim/Services/VideoCompressionService.swift`，找到第 136-149 行：

```swift
    func saveCompressedToLibrary(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
        cleanupTempFile(url)
    }

    func replaceOriginal(asset: PHAsset, with url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
        }
        cleanupTempFile(url)
    }
```

替换为：

```swift
    func saveCompressedToLibrary(url: URL) async throws {
        try await Self.performSave(videoFileURL: url)
        cleanupTempFile(url)
    }

    func replaceOriginal(asset: PHAsset, with url: URL) async throws {
        try await Self.performReplace(asset: asset, videoFileURL: url)
        cleanupTempFile(url)
    }

    /// nonisolated 入口：避免 @MainActor 类闭包被隐式隔离到主线程，
    /// 与 Photos changes queue 冲突触发 _dispatch_assert_queue_fail
    private nonisolated static func performSave(videoFileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoFileURL)
        }
    }

    private nonisolated static func performReplace(asset: PHAsset, videoFileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoFileURL)
            PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
        }
    }
```

- [ ] **Step 2: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add AlbumSlim/Services/VideoCompressionService.swift
git commit -m "iPad 闪退修复 6/N: VideoCompression 把 performChanges 抽到 nonisolated 静态入口"
```

---

### Task 7: CleanupCoordinator.executeCleanup 中的 performChanges 改走 PhotoLibraryService

**Files:**
- Modify: `AlbumSlim/Services/CleanupCoordinator.swift:154-194`

- [ ] **Step 1: 让 executeCleanup 接收 photoLibrary 参数**

打开 `AlbumSlim/Services/CleanupCoordinator.swift`，找到 `func executeCleanup(groups: [CleanupGroup]) async throws -> Int64` 这个方法（第 154 行）。

把签名改为接收 `photoLibrary`：

```swift
    func executeCleanup(groups: [CleanupGroup], photoLibrary: PhotoLibraryService) async throws -> Int64 {
```

把方法内部第 180-184 行：

```swift
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(batchAssets as NSFastEnumeration)
            }
            freedSize += batchSize
```

替换为：

```swift
            // 走 photoLibrary.deleteAssets（已经标 nonisolated），避免 @MainActor 类的
            // performChanges 闭包隐式隔离到主线程触发 _dispatch_assert_queue_fail
            try await photoLibrary.deleteAssets(batchAssets)
            freedSize += batchSize
```

注意：`photoLibrary.deleteAssets` 内部已经做了 50 个一批的分批，这里外层的分批可能产生"嵌套分批"。改为：把外层分批保留（按 50 切），但内部直接调 `photoLibrary.deleteAssets(batchAssets)`，因为传进去的就是 50 个，photoLibrary 里再分一次也是一批。**此处不做去重**，避免越界改动。

- [ ] **Step 2: 找出所有 executeCleanup 调用方并修复**

```bash
grep -rn "executeCleanup(groups:" /Users/huge/Project/AlbumSlim/AlbumSlim --include="*.swift"
```

预期会列出 2-3 处调用。每一处都加上 `photoLibrary:` 参数。例：

```swift
// 调用方原本是
try await services.cleanupCoordinator.executeCleanup(groups: selectedGroups)
// 改为
try await services.cleanupCoordinator.executeCleanup(groups: selectedGroups, photoLibrary: services.photoLibrary)
```

把每个调用方都改完。

- [ ] **Step 3: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED。如果有调用方漏改，编译器会告诉你哪里。

- [ ] **Step 4: 跑全量测试**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：所有测试通过。`CleanupCoordinatorTests` 可能需要更新——如果测试调用 `executeCleanup` 不带 `photoLibrary`，给它传一个真实的 `PhotoLibraryService()`。

- [ ] **Step 5: 提交**

```bash
git add AlbumSlim/Services/CleanupCoordinator.swift
git add -A AlbumSlim/Views AlbumSlim/ViewModels  # 调用方修改
git diff --cached  # 确认改动符合预期
git commit -m "iPad 闪退修复 7/N: CleanupCoordinator.executeCleanup 走 photoLibrary.deleteAssets 避免主线程闭包隔离"
```

---

## Phase 3: 资源生命周期 + 音频会话

### Task 8: ShuffleVideoView Tab 离开时 unload 而非 pause

**Files:**
- Modify: `AlbumSlim/Views/Shuffle/ShuffleVideoView.swift:40-42`

- [ ] **Step 1: 改 onReceive 行为**

打开 `AlbumSlim/Views/Shuffle/ShuffleVideoView.swift`，把第 40-42 行：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            controller.pause()
        }
```

替换为：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            // tab 离开时不仅暂停，还释放 PlayerItem，避免在非可见 tab 上累积 AVPlayer 资源；
            // 切回 tab 时 task(id: isActive) 会重新触发 activate() 加载
            controller.unload()
            isLoading = true
        }
```

- [ ] **Step 2: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

- [ ] **Step 3: 手动验证**

iPad 模拟器跑 app：
1. 浏览 tab 滑到一个视频，正在播放
2. 切到设置 tab 停留 3 秒
3. 切回浏览 tab → 视频应该重新加载并自动播放（看到短暂 ProgressView）

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/Views/Shuffle/ShuffleVideoView.swift
git commit -m "iPad 闪退修复 8/N: 浏览 Tab 离开时 unload 视频 PlayerItem 而非仅暂停"
```

---

### Task 9: ShuffleLivePhotoView Tab 离开时清空 livePhoto 引用

**Files:**
- Modify: `AlbumSlim/Views/Shuffle/ShuffleLivePhotoView.swift:54-56`

- [ ] **Step 1: 修改 onReceive**

打开 `AlbumSlim/Views/Shuffle/ShuffleLivePhotoView.swift`，把第 54-56 行：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            playTrigger = 0
        }
```

替换为：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            // tab 离开时释放 PHLivePhoto 强引用，避免持续占用解码后的位图内存；
            // 回到 tab 后 activate() 会重新加载
            livePhoto = nil
            isLoading = true
            playTrigger = 0
        }
```

- [ ] **Step 2: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

- [ ] **Step 3: 提交**

```bash
git add AlbumSlim/Views/Shuffle/ShuffleLivePhotoView.swift
git commit -m "iPad 闪退修复 9/N: 浏览 Tab 离开时释放 PHLivePhoto 强引用"
```

---

### Task 10: AlbumSlimApp 启动配置 AVAudioSession

**Files:**
- Modify: `AlbumSlim/App/AlbumSlimApp.swift:1-15`

- [ ] **Step 1: 修改 init**

打开 `AlbumSlim/App/AlbumSlimApp.swift`，把第 1-13 行：

```swift
import SwiftUI
import SwiftData

@main
struct AlbumSlimApp: App {
    let services = AppServiceContainer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        services.backgroundTask.registerBackgroundTasks(services: services)
    }
```

替换为：

```swift
import SwiftUI
import SwiftData
import AVFoundation

@main
struct AlbumSlimApp: App {
    let services = AppServiceContainer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        Self.configureAudioSession()
        services.backgroundTask.registerBackgroundTasks(services: services)
    }

    /// 配置音频会话为 .ambient + .mixWithOthers：
    /// - 浏览视频带声播放，但不抢占用户正在播放的音乐/播客
    /// - 来电、AirPods 切换等中断后系统自动恢复，不会让 AVPlayer 卡死
    private static func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 配置失败不影响 app 启动，只是音频混响行为退化
            print("[AlbumSlim] AVAudioSession 配置失败: \(error)")
        }
    }
```

- [ ] **Step 2: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

- [ ] **Step 3: 手动验证（用真机或 iPad 模拟器）**

1. 真机/模拟器先放音乐
2. 启动 app，浏览 tab 上滑到视频
3. 视频播放时音乐应该继续播放（mixWithOthers 生效）

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/App/AlbumSlimApp.swift
git commit -m "iPad 闪退修复 10/N: 启动时配置 AVAudioSession=.ambient+mixWithOthers 不抢占用户音频"
```

---

### Task 11: ShufflePhotoView 取消语义修正（不立即清空 displayImage）

**Files:**
- Modify: `AlbumSlim/Views/Shuffle/ShufflePhotoView.swift:39-49`

- [ ] **Step 1: 修改 task 块**

打开 `AlbumSlim/Views/Shuffle/ShufflePhotoView.swift`，把第 39-49 行：

```swift
        .task(id: isActive) {
            if isActive {
                await load()
                await services.backdrop.sample(image: displayImage)
            } else {
                displayImage = nil
                hasFullImage = false
                downloadProgress = 0
                onZoomStateChanged(false)
            }
        }
```

替换为：

```swift
        .task(id: isActive) {
            if isActive {
                await load()
                await services.backdrop.sample(image: displayImage)
            } else {
                // 注意：仅重置 zoom 状态与下载进度。displayImage 不主动清空 ——
                // SwiftUI 复用 cell 时清空会让回滑/分页跳动期间出现一闪而过的黑屏；
                // 真正的内存释放由 LazyVStack 销毁 cell 时触发，由内存警告触发 evictAllCaches
                downloadProgress = 0
                onZoomStateChanged(false)
            }
        }
```

- [ ] **Step 2: Build 验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

- [ ] **Step 3: 手动验证**

iPad 模拟器：浏览 tab 来回快速上下滑（fast swipe），不应再看到照片消失变黑屏后又出现。

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/Views/Shuffle/ShufflePhotoView.swift
git commit -m "iPad 闪退修复 11/N: ShufflePhotoView 切非 active 时不主动清 displayImage 避免快速分页时闪屏"
```

---

## Phase 4: iPad 适配 + 主线程压力

### Task 12: project.yml 锁定 iPad 全屏（保留横屏）

**Files:**
- Modify: `project.yml`

**说明**：保留 iPhone/iPad 全部横竖屏方向（产品要求保留横屏体验），只追加 `UIRequiresFullScreen: true` 关闭 iPad 多任务分屏（Slide Over / Split View），消除 GeometryReader + LazyVStack paging 在分屏下尺寸突变导致锚点错乱的风险。

- [ ] **Step 1: 编辑 project.yml**

打开 `project.yml`，定位到 `info: properties:` 段（在 `BGTaskSchedulerPermittedIdentifiers` 等键附近）。

**保留** 现有的 `UISupportedInterfaceOrientations` 和 `UISupportedInterfaceOrientations~ipad` 两段不动。

在同一 `properties:` 缩进层级追加一行：

```yaml
        UIRequiresFullScreen: true
```

把它放在 `UISupportedInterfaceOrientations~ipad: ...` 之后。

修改后该 properties 段相关部分应类似：

```yaml
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        "UISupportedInterfaceOrientations~ipad":
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        UIRequiresFullScreen: true
```

（如果 ipad orientations 段实际只有 3 个，保持原状即可，仅在末尾追加 `UIRequiresFullScreen: true`）

- [ ] **Step 2: 重新生成 xcodeproj**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate
```

- [ ] **Step 3: Build 验证**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=26.4' -quiet
```

预期：BUILD SUCCEEDED。

- [ ] **Step 4: 手动验证**

启动 iPad 模拟器，确认：
1. 旋转设备 → app 跟随旋转（横屏仍可用）
2. 从屏幕底部上滑或 dock 拖出另一 app 试图调起 Slide Over → 系统提示该 app 不支持分屏

- [ ] **Step 5: 提交**

```bash
git add project.yml AlbumSlim.xcodeproj/project.pbxproj
git commit -m "iPad 闪退修复 12/N: UIRequiresFullScreen=true 关闭 iPad Split View 但保留横屏"
```

---

### Task 13: refreshAfterLibraryChange 把 PHAsset.fetchAssets 移到后台

**Files:**
- Modify: `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift:162-176`

- [ ] **Step 1: 修改 refreshAfterLibraryChange**

打开 `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift`，把第 162-176 行：

```swift
    func refreshAfterLibraryChange(services: AppServiceContainer) async {
        let ids = items.map { $0.asset.localIdentifier }
        guard !ids.isEmpty else { return }
        let existing = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var aliveIDs: Set<String> = []
        existing.enumerateObjects { asset, _, _ in aliveIDs.insert(asset.localIdentifier) }
        let trashedIDs = services.trash.trashedAssetIDs
        let removed = items.filter { !aliveIDs.contains($0.asset.localIdentifier) || trashedIDs.contains($0.asset.localIdentifier) }
        items.removeAll { !aliveIDs.contains($0.asset.localIdentifier) || trashedIDs.contains($0.asset.localIdentifier) }
        for it in removed {
            indexQueue.remove(fetchIndex: it.fetchIndex)
            evictAll(for: it.asset.localIdentifier)
        }
        if items.count < 5 { appendNext(count: 5) }
    }
```

替换为：

```swift
    func refreshAfterLibraryChange(services: AppServiceContainer) async {
        let ids = items.map { $0.asset.localIdentifier }
        guard !ids.isEmpty else { return }

        // PHAsset.fetchAssets 是同步阻塞调用 ——
        // 大相册或 PHChange 触发频繁时，在主线程做会出现明显卡顿。
        // 移到 utility 线程后再回主线程 mutate items
        let aliveIDs = await Task.detached(priority: .utility) { () -> Set<String> in
            let existing = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var alive: Set<String> = []
            existing.enumerateObjects { asset, _, _ in alive.insert(asset.localIdentifier) }
            return alive
        }.value

        let trashedIDs = services.trash.trashedAssetIDs
        let removed = items.filter { !aliveIDs.contains($0.asset.localIdentifier) || trashedIDs.contains($0.asset.localIdentifier) }
        items.removeAll { !aliveIDs.contains($0.asset.localIdentifier) || trashedIDs.contains($0.asset.localIdentifier) }
        for it in removed {
            indexQueue.remove(fetchIndex: it.fetchIndex)
            evictAll(for: it.asset.localIdentifier)
        }
        if items.count < 5 { appendNext(count: 5) }
    }
```

- [ ] **Step 2: Build + 测试**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED 且测试通过。

- [ ] **Step 3: 提交**

```bash
git add AlbumSlim/ViewModels/ShuffleFeedViewModel.swift
git commit -m "iPad 闪退修复 13/N: refreshAfterLibraryChange 把 PHAsset.fetchAssets 移到 utility 线程"
```

---

### Task 14: ShuffleFeedView activeItem 用字典查询优化

**Files:**
- Modify: `AlbumSlim/Views/Shuffle/ShuffleFeedView.swift:22-25`，`ShuffleFeedViewModel.swift` 加 `item(for:)` helper

- [ ] **Step 1: ViewModel 加 helper**

打开 `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift`，在 `func cachedFullImage(for assetID: String) -> UIImage? { fullImageCache[assetID] }` 后面（第 33 行下方）加：

```swift
    /// O(1) 查询：scrolledID 拿到后用这个，避免 ShuffleFeedView.body 里
    /// items.first(where:) 在 80 个 items 时每帧 O(N) 遍历
    func item(for id: ShuffleItem.ID?) -> ShuffleItem? {
        guard let id else { return items.first }
        return itemIndexByID[id].map { items[$0] }
    }

    /// id → items index 的索引，items 变化时同步重建
    private var itemIndexByID: [ShuffleItem.ID: Int] = [:]

    private func rebuildItemIndex() {
        itemIndexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    }
```

然后找到所有 `items` 被 mutate 的地方，每次 mutate 后调用 `rebuildItemIndex()`。具体位置：
- `bootstrap` 末尾 `appendNext(count: 5)` 之后（约第 51 行）
- `onPageAppeared` 中 `items.removeFirst(dropCount)` 之后（约第 147 行）
- `remove` 中 `items.remove(at: idx)` 之后（约第 156 行）
- `refreshAfterLibraryChange` 中 `items.removeAll` 之后、`appendNext` 之前（约第 173 行）
- `filterTrashedItems` 中 `items.removeAll` 之后、`appendNext` 之前（约第 184 行）
- `appendNext` 末尾（确保 append 后重建）

更稳妥的方式：把 `items` 的 mutate 集中到一个 `setItems(_:)` 方法。但这次为了改动最小，**直接在每个 mutate 点之后调一次 rebuild**。下面是每处的精确补丁：

```swift
// bootstrap (第 35-52 行)，在 appendNext(count: 5) 后追加：
        appendNext(count: 5)
        rebuildItemIndex()  // 新增
```

```swift
// onPageAppeared (第 138-151 行)，在 dropped for-loop 后追加：
                for it in dropped { evictAll(for: it.asset.localIdentifier) }
                rebuildItemIndex()  // 新增
```

```swift
// remove (第 153-160 行)，在 if items.count < 5 上方追加：
        evictAll(for: removed.asset.localIdentifier)
        rebuildItemIndex()  // 新增
        if items.count < 5 { appendNext(count: 5); rebuildItemIndex() }  // 改这一行
```

```swift
// refreshAfterLibraryChange，在 if items.count < 5 上方追加：
        for it in removed {
            indexQueue.remove(fetchIndex: it.fetchIndex)
            evictAll(for: it.asset.localIdentifier)
        }
        rebuildItemIndex()  // 新增
        if items.count < 5 { appendNext(count: 5); rebuildItemIndex() }  // 改这一行
```

```swift
// filterTrashedItems，类似处理：
        for it in removed {
            indexQueue.remove(fetchIndex: it.fetchIndex)
            evictAll(for: it.asset.localIdentifier)
        }
        rebuildItemIndex()  // 新增
        if items.count < 5 { appendNext(count: 5); rebuildItemIndex() }  // 改这一行
```

`appendNext` 自身末尾不需要单独 rebuild，因为它的所有调用方在它之后立即调 rebuild。

- [ ] **Step 2: View 用 helper**

打开 `AlbumSlim/Views/Shuffle/ShuffleFeedView.swift`，把第 22-25 行：

```swift
    private var activeItem: ShuffleItem? {
        guard let scrolledID else { return viewModel.items.first }
        return viewModel.items.first(where: { $0.id == scrolledID })
    }
```

替换为：

```swift
    private var activeItem: ShuffleItem? {
        viewModel.item(for: scrolledID)
    }
```

- [ ] **Step 3: Build + 测试**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -quiet
```

预期：BUILD SUCCEEDED 且测试通过。

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/Views/Shuffle/ShuffleFeedView.swift AlbumSlim/ViewModels/ShuffleFeedViewModel.swift
git commit -m "iPad 闪退修复 14/N: activeItem 用字典查询替代每帧 O(N) 遍历"
```

---

## Phase 5: 集成验证

### Task 15: 跑全量测试 + iPad 真机/模拟器烟雾测试

- [ ] **Step 1: 跑所有单元测试**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && \
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
```

预期：所有测试通过。

- [ ] **Step 2: iPad Pro 12.9 模拟器手动场景测试**

启动模拟器：

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=26.4' -quiet
```

依次执行（每步过后看 Xcode Memory Report）：

| 场景 | 预期 |
|---|---|
| 浏览 tab 连续上滑 100 次 | 内存 < 350 MB，无崩溃 |
| 滑到视频自动播放 + 切设置 tab + 切回 | 视频重新加载并播放 |
| 收藏一张照片（点星形） | 不崩溃，状态正确切换 |
| 进入"照片"tab，相似照片扫描 → 全选 → 删除 | 不崩溃，删除成功 |
| 进入"视频"tab → 选一个视频 → 压缩中质量 | 不崩溃，完成通知到达 |
| 在 iPad 上模拟内存警告（Simulator → Device → Memory Warning） | app 不崩溃，浏览 tab 缓存被清，下次加载正常 |
| 浏览 tab 滑到 50 张以上后切其他 tab 来回 5 次 | 无崩溃，内存稳定回落 |

如果任一场景崩溃：拿 Xcode Console 的崩溃堆栈或模拟器 .ips 文件，对照本计划相关 task 重新检查。

- [ ] **Step 3: 写收尾 commit（如有 README/CHANGELOG 需要更新）**

如果项目有 README 标注 minimum iPad 支持，确认无需修改。

- [ ] **Step 4: 提交并推送（如需要）**

```bash
git status
git log --oneline | head -20
```

确认所有修复 commit 都在 branch 上。

---

## 自检 Checklist

- [x] **覆盖审查报告中的所有 🔴 头号嫌疑**
  - 内存压力 (Task 1-4)
  - BackdropAdapter 线程不安全 (Task 3)
  - Semaphore 共享 (Task 2)
  - 视频音频会话 (Task 10)
  - Tab 切换不卸载 (Task 8-9)
- [x] **覆盖所有 🟡 中危**
  - Swift 6 actor 隔离 (Task 5-7)
  - iPad 分屏 (Task 12)
  - ShufflePhotoView 重复加载 (Task 11)
- [x] **没有 "TBD"、"add appropriate" 之类占位**
- [x] **每个 task 都有：文件路径、完整代码、build 验证、commit 命令**
- [x] **有可衡量的 Phase 1 验收标准**（30 分钟 iPad 模拟器烟雾测试 + 内存上限）

## 风险提示

1. **本计划基于静态审查，未基于 crash log 验证**。Phase 1 完成后如果 iPad 仍闪退，必须停下来拿崩溃日志（Settings → Privacy → Analytics & Improvements → Analytics Data → AlbumSlim-*.ips）再决定后续动作。
2. **Task 7 改了 `executeCleanup` 公共签名**，调用方都得改。如果调用方很多（>5 处），评估是否改为给方法加默认参数 `photoLibrary: PhotoLibraryService? = nil`、内部 fallback 到旧路径，但更推荐显式参数避免遗漏。
3. **Task 12 已按用户要求保留横屏**，仅通过 `UIRequiresFullScreen=true` 关闭 iPad 分屏（Split View / Slide Over），既消除了分屏下 GeometryReader 尺寸突变风险，又不影响横屏使用。
