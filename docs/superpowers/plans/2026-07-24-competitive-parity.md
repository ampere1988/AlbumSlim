# 竞品对齐（Cleanup 全功能覆盖）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐竞品 Cleanup（DEEP FLOW，id1510944943）相对 AlbumSlim 的全部功能缺口——卡片式左右滑动清理、按堆推进的清理入口、第三方 App 相册识别、联系人去重合并、以及基于人脸与用户行为信号的「保留最佳」——并在每一项上做出超过竞品的差异化。

**Architecture:** 完全在现有 MVVM + `AppServiceContainer` 架构内扩展，不重构既有模块。新增 3 个服务（`SourceAlbumService`、`ContactCleanupService`、`SwipeCleanProgressStore`）、1 个分析器（`BestPhotoAnalyzer`）、2 个 ViewModel、2 个视图目录。删除动作一律复用已建成的 `TrashService` 软删除通道，不新增删除路径。

**Tech Stack:** Swift 6 / SwiftUI / iOS 17+ / Photos / Vision / CoreImage(CIDetector) / Contacts / XcodeGen / XCTest

---

## Global Constraints

- **付费模式不变**：$1 一次性买断，产品 ID `com.hao.doushan.pro.lifetime`。门控语义沿用 `ProFeatureGate.canClean(isPro:)`。
- **门控时点沿用现状**：拦截发生在「移入垃圾桶」这一步，参照 `AlbumSlim/Views/Shuffle/ShuffleFeedView.swift:233`。浏览、扫描、滑动本身免费；`SwipeDecision.trash` 落地前必须过门控。
- **不做邮件清理**。竞品的 Gmail 促销邮件清理需要联网与第三方账号授权，与「100% 本地、零网络」定位直接冲突，是本计划的显式 Non-Goal。
- 所有 `@Observable` 类标 `@MainActor`；Photos 写操作走 `PHPhotoLibrary.shared().performChanges`。
- 纯算法类型（无 UI 状态）保持 `Sendable` 且不加 `@MainActor`，参照 `AIAnalysisEngine`。
- 大批量处理分批，每批 `AppConstants.Analysis.batchSize`（100）。
- 用户可见字符串一律 `String(localized:)`；**新增字符串的翻译统一在 Task 12 补齐**，前面任务只写中文源文案。
- **项目支持 9 种语言**（见 `project.yml` 的 `knownRegions`）：`zh-Hans`（开发语言）、`zh-Hant`、`en`、`ja`、`ko`、`es`、`fr`、`de`、`pt-BR`、`ru`。Task 12 必须为每条新增文案补齐**全部 9 种**翻译。
- 模拟器 `OS=26.5`（本机实际可用版本；`CLAUDE.md` 里写的 26.4 已过期）。
- 并发严格性 `SWIFT_STRICT_CONCURRENCY = targeted`。
- 每个任务完成后必须执行，构建通过才能 commit：

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

- 单测运行命令：

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/<TestClass>
```

- git commit 消息用中文。
- 新增 Swift 文件后必须 `xcodegen generate`，否则不进编译。
- **任务实施前先 Read 任务列出的每个文件**，以实际代码为准适配锚点（下述行号为写计划时快照）。

---

## 已核实的现状（不要重复造）

实施前请注意，以下能力**已经存在**，本计划一律复用而非新建：

| 能力 | 位置 | 说明 |
|---|---|---|
| 待删除暂存区 / 垃圾桶 | `AlbumSlim/Services/TrashService.swift` | 已含软删除、恢复、永久删除、体积统计、库同步、旧数据迁移。竞品的 Trash 功能我们**已经有了**。 |
| 垃圾桶 UI | `AlbumSlim/Views/Trash/GlobalTrashView.swift` | — |
| 缩略图 / 全图 / Live Photo / 视频加载 | `AlbumSlim/Services/PhotoLibraryService.swift` | 含信号量限流与取消处理，滑动卡片直接复用 `thumbnail(for:size:)`。 |
| 图像技术质量评分 | `AIAnalysisEngine.qualityScore(for:)` `:30` | 锐度 0.5 + 曝光 0.3 + 分辨率 0.2。Task 1 在其之上叠加人脸与行为信号，**不重写**。 |
| 特征向量相似度与缓存 | `ImageSimilarityService.swift` + `AnalysisCacheService` | — |
| Toast / 触感 / 空状态 / 加载态组件 | `Views/Common/`、`Utils/Haptics.swift` | — |

**缺口即本计划范围**：最佳照片选择过弱（`ImageSimilarityService.swift:136` 仅 `max(by: fileSize)`）、无卡片滑动清理、无分堆推进入口、无第三方 App 相册识别、无联系人去重。

---

## 阶段划分

五个阶段互相独立，各自可单独发版。若需拆成多份计划执行，按此边界拆：

- **Phase A（Task 1–2）** 最佳照片评分升级 — 纯算法增强，零 UI 变更，风险最低，建议先做。
- **Phase B（Task 3–6）** 卡片式滑动清理 — 竞品核心护城河，工作量最大。
- **Phase C（Task 7–8）** 第三方 App 相册识别。
- **Phase D（Task 9–11）** 联系人去重合并 — 引入新权限，风险最高，建议最后做。
- **Phase E（Task 12）** 英文本地化补齐。

---

### Task 1: 最佳照片评分器（人脸 + 行为信号）

**背景:** 竞品明示其「保留最佳」依据包含直视镜头、微笑、对焦、以及照片是否被编辑过。我们目前只按文件大小选最佳（`ImageSimilarityService.swift:136`），这是本计划里性价比最高的一项改进。

**Files:**
- Create: `AlbumSlim/Services/BestPhotoAnalyzer.swift`
- Test: `AlbumSlimTests/BestPhotoAnalyzerTests.swift`
- Read first: `AlbumSlim/Services/AIAnalysisEngine.swift`（确认 `qualityScore(for:)` 签名与返回区间 0...1）

**Interfaces:**
- Produces:
  - `struct PhotoSignals: Sendable` — 字段 `technical: Float`、`face: Float`、`behavior: Float`，均为 0...1
  - `BestPhotoAnalyzer.compositeScore(_ signals: PhotoSignals) -> Float`
  - `BestPhotoAnalyzer.behaviorScore(for asset: PHAsset) -> Float`（`nonisolated`，静态）
  - `BestPhotoAnalyzer.faceScore(for cgImage: CGImage) -> Float`（实例方法，内部持有 CIDetector）
  - `BestPhotoAnalyzer.signals(for cgImage: CGImage, asset: PHAsset, engine: AIAnalysisEngine) -> PhotoSignals`

- [ ] **Step 1: 写失败测试** — 创建 `AlbumSlimTests/BestPhotoAnalyzerTests.swift`

```swift
import XCTest
import Photos
import UIKit
@testable import AlbumSlim

final class BestPhotoAnalyzerTests: XCTestCase {

    func testCompositeScoreWeightsSumToOne() {
        // 三项信号全 1 时合成分应为 1（权重和为 1）
        let signals = PhotoSignals(technical: 1.0, face: 1.0, behavior: 1.0)
        XCTAssertEqual(BestPhotoAnalyzer.compositeScore(signals), 1.0, accuracy: 0.001)
    }

    func testCompositeScoreAllZeroIsZero() {
        let signals = PhotoSignals(technical: 0, face: 0, behavior: 0)
        XCTAssertEqual(BestPhotoAnalyzer.compositeScore(signals), 0, accuracy: 0.001)
    }

    func testFaceSignalOutweighsNothingWhenTechnicalTied() {
        // 技术质量相同时，有笑脸睁眼的一张必须胜出
        let smiling = PhotoSignals(technical: 0.5, face: 1.0, behavior: 0.3)
        let neutral = PhotoSignals(technical: 0.5, face: 0.5, behavior: 0.3)
        XCTAssertGreaterThan(
            BestPhotoAnalyzer.compositeScore(smiling),
            BestPhotoAnalyzer.compositeScore(neutral)
        )
    }

    func testFavoriteBehaviorScoreIsMaximum() {
        // 收藏是最强保留信号，必须拿满分
        XCTAssertEqual(BestPhotoAnalyzer.behaviorScoreValue(isFavorite: true, isEdited: false), 1.0, accuracy: 0.001)
        XCTAssertEqual(BestPhotoAnalyzer.behaviorScoreValue(isFavorite: true, isEdited: true), 1.0, accuracy: 0.001)
    }

    func testEditedBeatsUntouched() {
        let edited = BestPhotoAnalyzer.behaviorScoreValue(isFavorite: false, isEdited: true)
        let untouched = BestPhotoAnalyzer.behaviorScoreValue(isFavorite: false, isEdited: false)
        XCTAssertGreaterThan(edited, untouched)
        XCTAssertLessThan(edited, 1.0)
    }

    func testNoFaceReturnsNeutralScore() {
        // 纯色图无人脸，应返回中性 0.5 而不是 0——否则风景照会被系统性判劣
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let analyzer = BestPhotoAnalyzer()
        let score = analyzer.faceScore(for: image.cgImage!)
        XCTAssertEqual(score, 0.5, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/BestPhotoAnalyzerTests
```

Expected: 编译失败，`cannot find 'BestPhotoAnalyzer' in scope` / `cannot find 'PhotoSignals' in scope`

- [ ] **Step 3: 实现** — 创建 `AlbumSlim/Services/BestPhotoAnalyzer.swift`

```swift
import Foundation
import CoreImage
import Photos
import UIKit

/// 单张照片的三维打分信号，各项均归一化到 0...1
struct PhotoSignals: Sendable {
    /// 技术质量：锐度/曝光/分辨率，来自 AIAnalysisEngine.qualityScore
    var technical: Float
    /// 人脸质量：微笑 + 睁眼；无人脸时为中性 0.5
    var face: Float
    /// 用户行为信号：收藏 / 编辑过
    var behavior: Float
}

/// 在技术质量之上叠加人脸与用户行为信号，选出一组照片里最该保留的那张。
///
/// 权重设计说明：
/// - technical 0.45 —— 糊片再有笑脸也不该留
/// - face 0.25 —— 人像场景的决定性差异；风景照走中性值不产生偏置
/// - behavior 0.30 —— 用户自己收藏/修过的照片是最可信的保留意图
final class BestPhotoAnalyzer: @unchecked Sendable {

    private static let technicalWeight: Float = 0.45
    private static let faceWeight: Float = 0.25
    private static let behaviorWeight: Float = 0.30

    /// CIDetector 创建开销大，复用同一实例
    private let detector: CIDetector?

    init() {
        let context = CIContext(options: nil)
        detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: context,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }

    // MARK: - 合成

    static func compositeScore(_ signals: PhotoSignals) -> Float {
        signals.technical * technicalWeight
            + signals.face * faceWeight
            + signals.behavior * behaviorWeight
    }

    func signals(for cgImage: CGImage, asset: PHAsset, engine: AIAnalysisEngine) -> PhotoSignals {
        PhotoSignals(
            technical: engine.qualityScore(for: cgImage),
            face: faceScore(for: cgImage),
            behavior: Self.behaviorScore(for: asset)
        )
    }

    // MARK: - 人脸信号

    /// 返回 0...1。无人脸返回中性 0.5，避免风景照被系统性判劣。
    /// 多张人脸时取各脸得分的均值——合照里大家都在笑才算好照片。
    func faceScore(for cgImage: CGImage) -> Float {
        guard let detector else { return 0.5 }
        let ciImage = CIImage(cgImage: cgImage)
        let features = detector.features(in: ciImage, options: [
            CIDetectorSmile: true,
            CIDetectorEyeBlink: true,
        ])
        let faces = features.compactMap { $0 as? CIFaceFeature }
        guard !faces.isEmpty else { return 0.5 }

        var total: Float = 0
        for face in faces {
            // 睁眼 0.6 权重（闭眼是硬伤），微笑 0.4 权重
            let bothEyesOpen = !face.leftEyeClosed && !face.rightEyeClosed
            let eyeScore: Float = bothEyesOpen ? 1.0 : (face.leftEyeClosed && face.rightEyeClosed ? 0.0 : 0.4)
            let smileScore: Float = face.hasSmile ? 1.0 : 0.5
            total += eyeScore * 0.6 + smileScore * 0.4
        }
        return total / Float(faces.count)
    }

    // MARK: - 行为信号

    static func behaviorScore(for asset: PHAsset) -> Float {
        behaviorScoreValue(isFavorite: asset.isFavorite, isEdited: isEdited(asset))
    }

    /// 纯值函数，便于单测（不依赖 PHAsset 构造）
    static func behaviorScoreValue(isFavorite: Bool, isEdited: Bool) -> Float {
        if isFavorite { return 1.0 }
        return isEdited ? 0.7 : 0.3
    }

    /// 通过 PHAssetResource 是否含 adjustmentData 判断照片被编辑过
    static func isEdited(_ asset: PHAsset) -> Bool {
        PHAssetResource.assetResources(for: asset).contains { $0.type == .adjustmentData }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/BestPhotoAnalyzerTests
```

Expected: 6 个测试全部 PASS

- [ ] **Step 5: 构建并提交**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
git add AlbumSlim/Services/BestPhotoAnalyzer.swift AlbumSlimTests/BestPhotoAnalyzerTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增 BestPhotoAnalyzer: 人脸(微笑/睁眼) + 行为(收藏/编辑) 信号打分"
```

---

### Task 2: 相似照片组接入新评分

**Files:**
- Modify: `AlbumSlim/Services/ImageSimilarityService.swift`（`findSimilarInGroup` 尾部选最佳逻辑，快照在 `:134-138`）
- Test: `AlbumSlimTests/BestPhotoAnalyzerTests.swift`（追加）

**Interfaces:**
- Consumes: Task 1 的 `BestPhotoAnalyzer`、`PhotoSignals`、`BestPhotoAnalyzer.compositeScore(_:)`
- Produces: `BestPhotoAnalyzer.pickBest(from candidates: [(id: String, score: Float, fileSize: Int64)]) -> String?` — 按分数降序，同分时取文件更大者

- [ ] **Step 1: 写失败测试**（追加到 `AlbumSlimTests/BestPhotoAnalyzerTests.swift`）

```swift
    func testPickBestChoosesHighestScore() {
        let best = BestPhotoAnalyzer.pickBest(from: [
            (id: "a", score: 0.4, fileSize: 9_000_000),
            (id: "b", score: 0.8, fileSize: 1_000),
        ])
        // 分数压倒文件大小——这正是相对旧逻辑的改进点
        XCTAssertEqual(best, "b")
    }

    func testPickBestBreaksTieByFileSize() {
        let best = BestPhotoAnalyzer.pickBest(from: [
            (id: "a", score: 0.5, fileSize: 100),
            (id: "b", score: 0.5, fileSize: 999),
        ])
        XCTAssertEqual(best, "b")
    }

    func testPickBestOnEmptyReturnsNil() {
        XCTAssertNil(BestPhotoAnalyzer.pickBest(from: []))
    }
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/BestPhotoAnalyzerTests
```

Expected: 编译失败，`type 'BestPhotoAnalyzer' has no member 'pickBest'`

- [ ] **Step 3: 实现 pickBest** — 在 `BestPhotoAnalyzer.swift` 的 `// MARK: - 行为信号` 之前插入

```swift
    // MARK: - 择优

    /// 从候选中选出最佳。同分时取文件更大者（保留旧行为作为 tiebreaker）。
    static func pickBest(from candidates: [(id: String, score: Float, fileSize: Int64)]) -> String? {
        candidates.max { lhs, rhs in
            if abs(lhs.score - rhs.score) < 0.0001 {
                return lhs.fileSize < rhs.fileSize
            }
            return lhs.score < rhs.score
        }?.id
    }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/BestPhotoAnalyzerTests
```

Expected: 9 个测试全部 PASS

- [ ] **Step 5: 接入 ImageSimilarityService**

在 `findSimilarInGroup` 的签名处新增 `analyzer` 参数。先修改 `findSimilarGroups`（`:16-18` 附近）创建复用实例：

```swift
        // 复用同一个 engine 实例，避免循环内每组重复创建
        let engine = AIAnalysisEngine()
        let analyzer = BestPhotoAnalyzer()

        for group in timeGroups {
            let base = processedItems
            let similar = await findSimilarInGroup(group, engine: engine, analyzer: analyzer, using: photoLibrary, cache: cache) { itemsDone in
                onProgress(Double(base + itemsDone) / Double(totalItems))
            }
```

再修改 `findSimilarInGroup` 签名（`:72`）：

```swift
    private func findSimilarInGroup(_ items: [MediaItem], engine: AIAnalysisEngine, analyzer: BestPhotoAnalyzer, using photoLibrary: PhotoLibraryService, cache: AnalysisCacheService, onItemProgress: (@MainActor @Sendable (Int) -> Void)? = nil) async -> [CleanupGroup] {
```

- [ ] **Step 6: 替换选最佳逻辑**

在 `findSimilarInGroup` 内，把分组循环（快照 `:134-138`）从：

```swift
            if similarItems.count > 1 {
                visited.insert(featurePrints[i].item.id)
                let best = similarItems.max(by: { $0.fileSize < $1.fileSize })
                groups.append(CleanupGroup(type: .similar, items: similarItems, bestItemID: best?.id))
            }
```

改为：

```swift
            if similarItems.count > 1 {
                visited.insert(featurePrints[i].item.id)
                let bestID = await bestItemID(in: similarItems, engine: engine, analyzer: analyzer, using: photoLibrary)
                groups.append(CleanupGroup(type: .similar, items: similarItems, bestItemID: bestID))
            }
```

并在 `ImageSimilarityService` 末尾（`findSimilarInGroup` 之后）新增私有方法：

```swift
    /// 对一组相似照片逐张打分，返回最该保留的那张的 id。
    /// 只在组内（通常 2–5 张）执行，不影响全库扫描耗时。
    private func bestItemID(in items: [MediaItem], engine: AIAnalysisEngine, analyzer: BestPhotoAnalyzer, using photoLibrary: PhotoLibraryService) async -> String? {
        let size = CGSize(width: 300, height: 300)
        var candidates: [(id: String, score: Float, fileSize: Int64)] = []

        for item in items {
            guard let image = await photoLibrary.thumbnail(for: item.asset, size: size),
                  let cgImage = image.cgImage else {
                // 取不到图时退化为纯行为信号，不让该张直接出局
                let fallback = PhotoSignals(
                    technical: 0,
                    face: 0.5,
                    behavior: BestPhotoAnalyzer.behaviorScore(for: item.asset)
                )
                candidates.append((id: item.id, score: BestPhotoAnalyzer.compositeScore(fallback), fileSize: item.fileSize))
                continue
            }
            let signals = autoreleasepool {
                analyzer.signals(for: cgImage, asset: item.asset, engine: engine)
            }
            candidates.append((
                id: item.id,
                score: BestPhotoAnalyzer.compositeScore(signals),
                fileSize: item.fileSize
            ))
        }

        return BestPhotoAnalyzer.pickBest(from: candidates)
    }
```

- [ ] **Step 7: 构建并跑全量测试**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 全部 PASS（含既有 `CleanupGroupTests`、`CleanupCoordinatorTests`）

- [ ] **Step 8: 提交**

```bash
git add AlbumSlim/Services/BestPhotoAnalyzer.swift AlbumSlim/Services/ImageSimilarityService.swift AlbumSlimTests/BestPhotoAnalyzerTests.swift
git commit -m "相似照片择优改用综合评分: 技术质量 + 人脸 + 收藏/编辑行为"
```

---

### Task 3: 滑动清理的分堆模型与进度存储

**背景:** 竞品把相册按堆（月份/相册）切开逐堆推进，这是「有始有终」体验的来源。本任务只做纯逻辑与持久化，无 UI。

**Files:**
- Create: `AlbumSlim/Models/SwipeCleanBucket.swift`
- Create: `AlbumSlim/Services/SwipeCleanProgressStore.swift`
- Modify: `AlbumSlim/App/AppServiceContainer.swift`
- Test: `AlbumSlimTests/SwipeCleanProgressStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum SwipeDecision: String, Codable { case keep, trash }`
  - `struct SwipeCleanBucket: Identifiable, Sendable` — `id: String`、`kind: Kind`、`title: String`、`assetIDs: [String]`、`totalSize: Int64`
  - `enum SwipeCleanBucket.Kind: Hashable, Sendable { case month(year: Int, month: Int), sourceAlbum(localIdentifier: String), screenshots, videos }` —— **必须 Hashable**，Task 6 拿它当字典键做月份分组
  - `@MainActor @Observable final class SwipeCleanProgressStore`，方法 `isKept(_:) -> Bool`、`markKept(_:)`、`unmarkKept(_:)`、`keptCount(in:) -> Int`、`resetBucket(assetIDs:)`、`pendingIDs(from:excluding:) -> [String]`
- Consumes: `TrashService.trashedAssetIDs`（由调用方传入 `excluding:`）

- [ ] **Step 1: 写失败测试** — 创建 `AlbumSlimTests/SwipeCleanProgressStoreTests.swift`

```swift
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/SwipeCleanProgressStoreTests
```

Expected: 编译失败，`cannot find 'SwipeCleanProgressStore' in scope`

- [ ] **Step 3: 实现模型** — 创建 `AlbumSlim/Models/SwipeCleanBucket.swift`

```swift
import Foundation

/// 卡片滑动时的单次决策
enum SwipeDecision: String, Codable, Sendable {
    /// 右滑：保留，并记入已处理，之后不再出现
    case keep
    /// 左滑：移入垃圾桶（软删除，可在垃圾桶恢复）
    case trash
}

/// 一「堆」待滑动清理的素材。按堆推进，让用户有明确的开始与结束。
struct SwipeCleanBucket: Identifiable, Sendable {
    /// Hashable 是必需的——Task 6 用它作为月份分组的字典键
    enum Kind: Hashable, Sendable {
        case month(year: Int, month: Int)
        case sourceAlbum(localIdentifier: String)
        case screenshots
        case videos
    }

    let id: String
    let kind: Kind
    let title: String
    let assetIDs: [String]
    let totalSize: Int64

    var count: Int { assetIDs.count }
    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
```

- [ ] **Step 4: 实现进度存储** — 创建 `AlbumSlim/Services/SwipeCleanProgressStore.swift`

```swift
import Foundation

/// 记录用户在滑动清理中「保留」过的照片，避免下次重复出现。
///
/// 只持久化 keep 决策——trash 决策由 `TrashService` 自己持久化，
/// 两边合起来构成「已处理」全集，不重复记账。
@MainActor @Observable
final class SwipeCleanProgressStore {

    static let storageKey = "swipeCleanKeptIDs_v1"

    private(set) var keptIDs: Set<String> = []

    init() {
        load()
    }

    // MARK: - 查询

    func isKept(_ assetID: String) -> Bool {
        keptIDs.contains(assetID)
    }

    func keptCount(in assetIDs: [String]) -> Int {
        assetIDs.reduce(0) { $0 + (keptIDs.contains($1) ? 1 : 0) }
    }

    /// 从候选中剔除已保留与已在垃圾桶的，保持原始顺序
    func pendingIDs(from assetIDs: [String], excluding trashedIDs: Set<String>) -> [String] {
        assetIDs.filter { !keptIDs.contains($0) && !trashedIDs.contains($0) }
    }

    // MARK: - 写入

    func markKept(_ assetID: String) {
        guard !keptIDs.contains(assetID) else { return }
        keptIDs.insert(assetID)
        persist()
    }

    /// 撤销用：把一次 keep 决策撤回
    func unmarkKept(_ assetID: String) {
        guard keptIDs.contains(assetID) else { return }
        keptIDs.remove(assetID)
        persist()
    }

    /// 重新清理某一堆：只清掉这堆内的记录
    func resetBucket(assetIDs: [String]) {
        let target = Set(assetIDs)
        let remaining = keptIDs.subtracting(target)
        guard remaining.count != keptIDs.count else { return }
        keptIDs = remaining
        persist()
    }

    // MARK: - 持久化

    private func load() {
        guard let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] else { return }
        keptIDs = Set(stored)
    }

    private func persist() {
        UserDefaults.standard.set(Array(keptIDs), forKey: Self.storageKey)
    }
}
```

- [ ] **Step 5: 新增垃圾桶来源分类** — 修改 `AlbumSlim/Services/TrashService.swift`

滑动清理需要独立归因，不要借用 `.shuffle`（标签是「浏览」，会让用户在垃圾桶里看不懂来源）。

在 `TrashSource` 枚举（`:4-13`）的 `case shuffle` 之后加一个 case：

```swift
    case swipeClean
```

在 `label` 的 switch（`:14-25`）里 `case .shuffle` 之后加：

```swift
        case .swipeClean: return "逐张清理"
```

枚举是 `String` RawValue 的 `Codable`，新增 case 不影响已持久化的旧数据解码。

- [ ] **Step 6: 注册到服务容器** — 修改 `AlbumSlim/App/AppServiceContainer.swift`

在属性声明区（`:22` 的 `backdrop` 之后）加：

```swift
    let swipeProgress: SwipeCleanProgressStore
```

在 `init()` 内（`:46` 的 `self.backdrop = ...` 之后）加：

```swift
        self.swipeProgress = SwipeCleanProgressStore()
```

- [ ] **Step 7: 运行测试确认通过**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/SwipeCleanProgressStoreTests
```

Expected: 6 个测试全部 PASS。既有的 `TrashServiceFilterTests` / `TrashServiceMigrationTests` 也必须仍然通过：

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/TrashServiceMigrationTests
```

- [ ] **Step 8: 提交**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
git add AlbumSlim/Models/SwipeCleanBucket.swift AlbumSlim/Services/SwipeCleanProgressStore.swift AlbumSlim/Services/TrashService.swift AlbumSlim/App/AppServiceContainer.swift AlbumSlimTests/SwipeCleanProgressStoreTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增滑动清理分堆模型与进度存储"
```

---

### Task 4: 滑动清理 ViewModel

**Files:**
- Create: `AlbumSlim/ViewModels/SwipeCleanViewModel.swift`
- Test: `AlbumSlimTests/SwipeCleanViewModelTests.swift`
- Read first: `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift`（对齐缩略图缓存与预取写法）

**Interfaces:**
- Consumes: Task 3 的 `SwipeCleanBucket`、`SwipeDecision`、`SwipeCleanProgressStore`；`TrashService.moveToTrash(assets:source:mediaType:)`；`TrashService.restore(_:)`
- Produces:
  - `@MainActor @Observable final class SwipeCleanViewModel`
  - `func load(bucket: SwipeCleanBucket, services: AppServiceContainer) async`
  - `func decide(_ decision: SwipeDecision, services: AppServiceContainer)`
  - `func undo(services: AppServiceContainer)`
  - `var current: MediaItem?`、`var upcoming: MediaItem?`、`var canUndo: Bool`、`var isFinished: Bool`
  - `var processedCount: Int`、`var totalCount: Int`、`var trashedSizeInSession: Int64`

- [ ] **Step 1: 写失败测试** — 创建 `AlbumSlimTests/SwipeCleanViewModelTests.swift`

纯逻辑部分（队列推进与撤销栈）不依赖 Photos，用注入的假数据测：

```swift
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/SwipeCleanViewModelTests
```

Expected: 编译失败，`cannot find 'SwipeCleanViewModel' in scope`

- [ ] **Step 3: 实现** — 创建 `AlbumSlim/ViewModels/SwipeCleanViewModel.swift`

```swift
import Foundation
import Photos
import SwiftUI
import UIKit

@MainActor @Observable
final class SwipeCleanViewModel {

    /// 一次决策的记录，供撤销
    private struct HistoryEntry {
        let item: MediaItem
        let decision: SwipeDecision
        let reclaimedSize: Int64
    }

    private(set) var items: [MediaItem] = []
    private(set) var index: Int = 0
    private(set) var isLoading = false
    private(set) var trashedSizeInSession: Int64 = 0
    private(set) var bucketTitle: String = ""

    private var history: [HistoryEntry] = []
    private var bucket: SwipeCleanBucket?

    /// 缩略图缓存，键为 assetID
    private(set) var thumbnails: [String: UIImage] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]

    /// 预取窗口：当前卡之后再准备 3 张
    private let prefetchWindow = 3

    // MARK: - 派生状态

    var current: MediaItem? { index < items.count ? items[index] : nil }
    var upcoming: MediaItem? { index + 1 < items.count ? items[index + 1] : nil }
    var canUndo: Bool { !history.isEmpty }
    var isFinished: Bool { !items.isEmpty && index >= items.count }
    var processedCount: Int { index }
    var totalCount: Int { items.count }
    var progress: Double {
        items.isEmpty ? 0 : Double(index) / Double(items.count)
    }
    var trashedSizeText: String {
        ByteCountFormatter.string(fromByteCount: trashedSizeInSession, countStyle: .file)
    }

    // MARK: - 加载

    func load(bucket: SwipeCleanBucket, services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        self.bucket = bucket
        bucketTitle = bucket.title
        index = 0
        history = []
        trashedSizeInSession = 0
        thumbnails = [:]

        let pendingIDs = services.swipeProgress.pendingIDs(
            from: bucket.assetIDs,
            excluding: services.trash.trashedAssetIDs
        )
        guard !pendingIDs.isEmpty else {
            items = []
            return
        }

        // fetchAssets 不保证返回顺序，按 pendingIDs 顺序重排
        let fetched = services.trash.fetchAssets(for: Set(pendingIDs))
        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })
        let ordered = pendingIDs.compactMap { byID[$0] }

        items = ordered.map { asset in
            MediaItem(
                id: asset.localIdentifier,
                asset: asset,
                fileSize: services.photoLibrary.fileSize(for: asset),
                creationDate: asset.creationDate
            )
        }

        prefetchThumbnails(services: services)
    }

    // MARK: - 决策

    /// 调用方必须先过 `ProFeatureGate.canClean(isPro:)` 才允许传入 `.trash`
    func decide(_ decision: SwipeDecision, services: AppServiceContainer) {
        guard let item = current else { return }

        var reclaimed: Int64 = 0
        switch decision {
        case .keep:
            services.swipeProgress.markKept(item.id)
        case .trash:
            let mediaType: TrashedMediaType = {
                if item.mediaType == .video { return .video }
                if item.isScreenshot { return .screenshot }
                if item.isLivePhoto { return .livePhoto }
                return .photo
            }()
            let result = services.trash.moveToTrash(
                assets: [item.asset],
                source: .swipeClean,
                mediaType: mediaType
            )
            reclaimed = result.totalSize
            trashedSizeInSession += reclaimed
        }

        history.append(HistoryEntry(item: item, decision: decision, reclaimedSize: reclaimed))
        index += 1
        thumbnails.removeValue(forKey: item.id)
        prefetchThumbnails(services: services)
        Haptics.light()
    }

    func undo(services: AppServiceContainer) {
        guard let entry = history.popLast() else { return }
        switch entry.decision {
        case .keep:
            services.swipeProgress.unmarkKept(entry.item.id)
        case .trash:
            services.trash.restore([entry.item.id])
            trashedSizeInSession = max(0, trashedSizeInSession - entry.reclaimedSize)
        }
        index = max(0, index - 1)
        prefetchThumbnails(services: services)
        Haptics.light()
    }

    /// 重新清理这一堆
    func restart(services: AppServiceContainer) async {
        guard let bucket else { return }
        services.swipeProgress.resetBucket(assetIDs: bucket.assetIDs)
        await load(bucket: bucket, services: services)
    }

    // MARK: - 缩略图

    func thumbnail(for assetID: String) -> UIImage? { thumbnails[assetID] }

    private func prefetchThumbnails(services: AppServiceContainer) {
        let upperBound = min(index + prefetchWindow, items.count)
        guard index < upperBound else { return }

        // 目标尺寸取屏幕宽度的 2 倍像素，卡片本身不超过屏宽
        let side = UIScreen.main.bounds.width * UIScreen.main.scale
        let size = CGSize(width: side, height: side * 1.6)

        for i in index..<upperBound {
            let item = items[i]
            guard thumbnails[item.id] == nil, thumbnailTasks[item.id] == nil else { continue }
            let task = Task { @MainActor [weak self] in
                let image = await services.photoLibrary.thumbnail(
                    for: item.asset, size: size, contentMode: .aspectFit
                )
                guard let self, !Task.isCancelled else { return }
                if let image { self.thumbnails[item.id] = image }
                self.thumbnailTasks.removeValue(forKey: item.id)
            }
            thumbnailTasks[item.id] = task
        }
    }

    func cancelAllTasks() {
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
        thumbnails.removeAll()
    }
}

#if DEBUG
extension SwipeCleanViewModel {
    var currentIDForTesting: String? { current?.id }
    var upcomingIDForTesting: String? { upcoming?.id }

    /// 用假 id 构造队列，绕开 PHAsset —— 只测队列推进与撤销栈
    func injectQueueForTesting(ids: [String]) {
        items = ids.map { id in
            MediaItem(id: id, asset: PHAsset(), fileSize: 0, creationDate: nil)
        }
        index = 0
        history = []
    }

    func advanceForTesting() {
        guard let item = current else { return }
        history.append(HistoryEntry(item: item, decision: .keep, reclaimedSize: 0))
        index += 1
    }

    func rewindForTesting() {
        guard history.popLast() != nil else { return }
        index = max(0, index - 1)
    }
}
#endif
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/SwipeCleanViewModelTests
```

Expected: 6 个测试全部 PASS

若 `Haptics.light()` 不存在，先 Read `AlbumSlim/Utils/Haptics.swift` 用其实际提供的方法名替换。

- [ ] **Step 5: 提交**

```bash
git add AlbumSlim/ViewModels/SwipeCleanViewModel.swift AlbumSlimTests/SwipeCleanViewModelTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增 SwipeCleanViewModel: 卡片队列 + 撤销栈 + 缩略图预取"
```

---

### Task 5: 滑动卡片界面

**Files:**
- Create: `AlbumSlim/Views/SwipeClean/SwipeCard.swift`
- Create: `AlbumSlim/Views/SwipeClean/SwipeCleanSessionView.swift`
- Read first: `AlbumSlim/Utils/DesignSystem.swift`、`AlbumSlim/Views/Common/EmptyState.swift`、`AlbumSlim/Views/Settings/PaywallView.swift`（确认 paywall 的 present 方式）

**Interfaces:**
- Consumes: Task 4 的 `SwipeCleanViewModel`；Task 3 的 `SwipeCleanBucket`
- Produces: `SwipeCleanSessionView(bucket: SwipeCleanBucket)`、`SwipeCard(image:size:offset:)`

- [ ] **Step 1: 实现卡片组件** — 创建 `AlbumSlim/Views/SwipeClean/SwipeCard.swift`

无独立测试（纯视图）；正确性由 Step 4 的真机/模拟器验收保证。

```swift
import SwiftUI

/// 单张滑动卡片。offset 由父视图的拖拽手势驱动，卡片自己负责倾斜与角标。
struct SwipeCard: View {
    let image: UIImage?
    let offset: CGSize
    let isTop: Bool

    /// 超过这个横向位移即判定为一次决策
    static let decisionThreshold: CGFloat = 110

    private var rotation: Double {
        Double(offset.width / 18)
    }

    /// 角标透明度随位移线性增强
    private var badgeOpacity: Double {
        min(Double(abs(offset.width) / Self.decisionThreshold), 1.0)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if isTop, offset.width < 0 {
                badge(text: String(localized: "删除"), color: .red)
                    .padding(20)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isTop, offset.width > 0 {
                badge(text: String(localized: "保留"), color: .green)
                    .padding(20)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .rotationEffect(.degrees(isTop ? rotation : 0))
        .offset(isTop ? offset : .zero)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color, lineWidth: 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .opacity(badgeOpacity)
    }
}
```

- [ ] **Step 2: 实现会话页** — 创建 `AlbumSlim/Views/SwipeClean/SwipeCleanSessionView.swift`

```swift
import SwiftUI

struct SwipeCleanSessionView: View {
    let bucket: SwipeCleanBucket

    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SwipeCleanViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.isFinished || viewModel.totalCount == 0 {
                finishedState
            } else {
                cardStack
                actionBar
            }
        }
        .navigationTitle(bucket.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.undo(services: services)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
            }
        }
        .task {
            await viewModel.load(bucket: bucket, services: services)
        }
        .onDisappear {
            viewModel.cancelAllTasks()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - 头部进度

    private var header: some View {
        VStack(spacing: 6) {
            ProgressView(value: viewModel.progress)
                .tint(.accentColor)
            HStack {
                Text(String(localized: "\(viewModel.processedCount) / \(viewModel.totalCount)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.trashedSizeInSession > 0 {
                    Label(viewModel.trashedSizeText, systemImage: "trash")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 卡片堆

    private var cardStack: some View {
        GeometryReader { geo in
            ZStack {
                // 下一张垫在底下，制造纵深
                if let upcoming = viewModel.upcoming {
                    SwipeCard(
                        image: viewModel.thumbnail(for: upcoming.id),
                        offset: .zero,
                        isTop: false
                    )
                    .scaleEffect(0.94)
                    .opacity(0.6)
                }

                if let current = viewModel.current {
                    SwipeCard(
                        image: viewModel.thumbnail(for: current.id),
                        offset: dragOffset,
                        isTop: true
                    )
                    .gesture(dragGesture)
                    .id(current.id)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let width = value.translation.width
                if width < -SwipeCard.decisionThreshold {
                    commit(.trash)
                } else if width > SwipeCard.decisionThreshold {
                    commit(.keep)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - 底部按钮

    private var actionBar: some View {
        HStack(spacing: 40) {
            circleButton(icon: "trash.fill", tint: .red) { commit(.trash) }
            circleButton(icon: "checkmark", tint: .green) { commit(.keep) }
        }
        .padding(.bottom, 28)
    }

    private func circleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5) }
        }
    }

    // MARK: - 完成态

    private var finishedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(String(localized: "这一堆清完了"))
                .font(.title3.bold())
            if viewModel.trashedSizeInSession > 0 {
                Text(String(localized: "本次可释放 \(viewModel.trashedSizeText)，去垃圾桶确认删除"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Button(String(localized: "重新清理这一堆")) {
                Task { await viewModel.restart(services: services) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button(String(localized: "完成")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 28)
        }
    }

    // MARK: - 决策落地

    private func commit(_ decision: SwipeDecision) {
        // 门控时点与 ShuffleFeedView.swift:233 保持一致：拦在移入垃圾桶这一步
        if decision == .trash,
           !ProFeatureGate.canClean(isPro: services.subscription.isPro) {
            showPaywall = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
            return
        }

        // 先把卡片甩出屏幕，再推进队列，避免下一张闪现在旧位置
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGSize(
                width: decision == .trash ? -700 : 700,
                height: dragOffset.height
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            viewModel.decide(decision, services: services)
            dragOffset = .zero
        }
    }
}
```

- [ ] **Step 3: 构建**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: BUILD SUCCEEDED

若 `PaywallView()` 需要参数，Read `AlbumSlim/Views/Settings/PaywallView.swift` 按其实际初始化方式调整。

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/Views/SwipeClean AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增滑动清理卡片界面: 左删右留 + 撤销 + Pro 门控"
```

---

### Task 6: 分堆入口页并接入 Tab

**Files:**
- Create: `AlbumSlim/ViewModels/SwipeCleanHomeViewModel.swift`
- Create: `AlbumSlim/Views/SwipeClean/SwipeCleanHomeView.swift`
- Modify: `AlbumSlim/Views/MainTabView.swift`（`PhotoCleanerCategory` 枚举 `:149-171`，`PhotoCleanerTabView` 的 switch `:178-184`）

**Interfaces:**
- Consumes: Task 3 的 `SwipeCleanBucket`；Task 5 的 `SwipeCleanSessionView`
- Produces:
  - `@MainActor @Observable final class SwipeCleanHomeViewModel`，方法 `loadBuckets(services:) async`，属性 `buckets: [SwipeCleanBucket]`、`isLoading: Bool`
  - `PhotoCleanerCategory.swipe` 新 case

- [ ] **Step 1: 实现分堆 ViewModel** — 创建 `AlbumSlim/ViewModels/SwipeCleanHomeViewModel.swift`

```swift
import Foundation
import Photos

@MainActor @Observable
final class SwipeCleanHomeViewModel {
    private(set) var buckets: [SwipeCleanBucket] = []
    private(set) var isLoading = false

    /// 少于这个数量的月份不单独成堆，避免入口页碎片化
    private let minimumBucketCount = 5

    func loadBuckets(services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets()
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else {
            buckets = []
            return
        }

        let calendar = Calendar.current
        var grouped: [SwipeCleanBucket.Kind: [PHAsset]] = [:]

        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { continue }
            grouped[.month(year: year, month: month), default: []].append(asset)
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")

        var result: [SwipeCleanBucket] = []
        for (kind, groupAssets) in grouped {
            guard groupAssets.count >= minimumBucketCount,
                  case let .month(year, month) = kind else { continue }

            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = month
            let title = calendar.date(from: dateComponents).map { formatter.string(from: $0) }
                ?? "\(year)-\(month)"

            let totalSize = groupAssets.reduce(Int64(0)) {
                $0 + services.photoLibrary.fileSize(for: $1)
            }

            result.append(SwipeCleanBucket(
                id: "month-\(year)-\(month)",
                kind: kind,
                title: title,
                assetIDs: groupAssets.map(\.localIdentifier),
                totalSize: totalSize
            ))
        }

        // 新的月份排前面
        buckets = result.sorted { lhs, rhs in
            guard case let .month(ly, lm) = lhs.kind, case let .month(ry, rm) = rhs.kind else {
                return false
            }
            return (ly, lm) > (ry, rm)
        }
    }

    /// 某一堆还剩多少张没处理
    func remainingCount(for bucket: SwipeCleanBucket, services: AppServiceContainer) -> Int {
        services.swipeProgress.pendingIDs(
            from: bucket.assetIDs,
            excluding: services.trash.trashedAssetIDs
        ).count
    }
}
```

- [ ] **Step 2: 实现入口页** — 创建 `AlbumSlim/Views/SwipeClean/SwipeCleanHomeView.swift`

```swift
import SwiftUI

struct SwipeCleanHomeView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = SwipeCleanHomeViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.buckets.isEmpty {
                ContentUnavailableView(
                    String(localized: "没有可清理的照片"),
                    systemImage: "rectangle.stack",
                    description: Text(String(localized: "相册为空，或每个月份的照片都少于 5 张"))
                )
            } else {
                List {
                    Section {
                        ForEach(viewModel.buckets) { bucket in
                            bucketRow(bucket)
                        }
                    } header: {
                        Text(String(localized: "按月份逐堆清理"))
                    } footer: {
                        Text(String(localized: "左滑删除，右滑保留。删除的照片先进垃圾桶，可随时恢复。"))
                    }
                }
            }
        }
        .task {
            await viewModel.loadBuckets(services: services)
        }
    }

    private func bucketRow(_ bucket: SwipeCleanBucket) -> some View {
        let remaining = viewModel.remainingCount(for: bucket, services: services)
        return NavigationLink {
            SwipeCleanSessionView(bucket: bucket)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.title)
                        .font(.body.weight(.medium))
                    Text(String(localized: "\(bucket.count) 张 · \(bucket.totalSizeText)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if remaining == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(String(localized: "剩 \(remaining)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(remaining == 0)
    }
}
```

- [ ] **Step 3: 接入照片 Tab** — 修改 `AlbumSlim/Views/MainTabView.swift`

把 `PhotoCleanerCategory`（`:150`）改为：

```swift
enum PhotoCleanerCategory: Int, CaseIterable, Identifiable {
    case swipe, similar, waste, burst, large

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .swipe: "逐张清理"
        case .similar: "相似照片"
        case .waste: "废片"
        case .burst: "连拍"
        case .large: "超大照片"
        }
    }

    var icon: String {
        switch self {
        case .swipe:   "hand.draw"
        case .similar: AppIcons.similar
        case .waste:   AppIcons.waste
        case .burst:   AppIcons.burst
        case .large:   AppIcons.largePhoto
        }
    }
}
```

把 `PhotoCleanerTabView` 的默认分类与 switch（`:174-184`）改为：

```swift
struct PhotoCleanerTabView: View {
    @State private var selectedCategory: PhotoCleanerCategory = .swipe

    var body: some View {
        NavigationStack {
            Group {
                switch selectedCategory {
                case .swipe: SwipeCleanHomeView()
                case .similar: SimilarPhotosView()
                case .waste: WastePhotosView()
                case .burst: BurstPhotosView()
                case .large: LargePhotosView()
                }
            }
```

- [ ] **Step 4: 构建**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: 跑全量测试**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 全部 PASS

- [ ] **Step 6: 提交**

```bash
git add AlbumSlim/ViewModels/SwipeCleanHomeViewModel.swift AlbumSlim/Views/SwipeClean/SwipeCleanHomeView.swift AlbumSlim/Views/MainTabView.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增按月份分堆的滑动清理入口，设为照片 Tab 默认分类"
```

---

### Task 7: 第三方 App 相册识别服务

**背景:** 竞品能列出 WhatsApp / Snapchat / Messenger 创建的相册。国内场景下微信、QQ、小红书、抖音的权重更高——这是我们能直接超过它的地方。

**Files:**
- Create: `AlbumSlim/Services/SourceAlbumService.swift`
- Modify: `AlbumSlim/App/AppServiceContainer.swift`
- Test: `AlbumSlimTests/SourceAlbumServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct SourceApp: Identifiable, Sendable` — `id: String`、`displayName: String`、`iconName: String`、`aliases: [String]`
  - `SourceApp.known: [SourceApp]`（静态表）
  - `SourceApp.match(albumTitle: String) -> SourceApp?`（静态，大小写不敏感）
  - `struct SourceAlbum: Identifiable, Sendable` — `id: String`（collection localIdentifier）、`app: SourceApp`、`title: String`、`assetIDs: [String]`、`totalSize: Int64`
  - `@MainActor @Observable final class SourceAlbumService`，方法 `loadAlbums(photoLibrary:) async`，属性 `albums: [SourceAlbum]`、`isLoading: Bool`

- [ ] **Step 1: 写失败测试** — 创建 `AlbumSlimTests/SourceAlbumServiceTests.swift`

匹配逻辑是纯函数，可完整单测：

```swift
import XCTest
@testable import AlbumSlim

final class SourceAlbumServiceTests: XCTestCase {

    func testMatchesWeChatByChineseName() {
        let app = SourceApp.match(albumTitle: "微信")
        XCTAssertEqual(app?.id, "wechat")
    }

    func testMatchesWeChatByEnglishName() {
        XCTAssertEqual(SourceApp.match(albumTitle: "WeChat")?.id, "wechat")
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(SourceApp.match(albumTitle: "whatsapp")?.id, "whatsapp")
        XCTAssertEqual(SourceApp.match(albumTitle: "WhatsApp")?.id, "whatsapp")
    }

    func testMatchTrimsWhitespace() {
        XCTAssertEqual(SourceApp.match(albumTitle: "  QQ  ")?.id, "qq")
    }

    func testUnknownAlbumReturnsNil() {
        XCTAssertNil(SourceApp.match(albumTitle: "我的旅行相册"))
    }

    func testDoesNotMatchOnPartialSubstring() {
        // "微信读书" 是另一个 app，不该被算成微信
        XCTAssertNil(SourceApp.match(albumTitle: "微信读书"))
    }

    func testAllKnownAppsHaveUniqueIDs() {
        let ids = SourceApp.known.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAllKnownAppsHaveAtLeastOneAlias() {
        for app in SourceApp.known {
            XCTAssertFalse(app.aliases.isEmpty, "\(app.id) 缺少别名")
        }
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/SourceAlbumServiceTests
```

Expected: 编译失败，`cannot find 'SourceApp' in scope`

- [ ] **Step 3: 实现** — 创建 `AlbumSlim/Services/SourceAlbumService.swift`

```swift
import Foundation
import Photos

/// 会在系统相册里创建自有相册的第三方 App。
/// 匹配用全等（trim + 小写），不用 contains——"微信读书" 不应被算作 "微信"。
struct SourceApp: Identifiable, Sendable {
    let id: String
    let displayName: String
    let iconName: String
    let aliases: [String]

    static let known: [SourceApp] = [
        SourceApp(id: "wechat", displayName: String(localized: "微信"),
                  iconName: "message.fill", aliases: ["微信", "wechat"]),
        SourceApp(id: "qq", displayName: "QQ",
                  iconName: "bubble.left.fill", aliases: ["qq", "qq空间", "qzone"]),
        SourceApp(id: "weibo", displayName: String(localized: "微博"),
                  iconName: "at", aliases: ["微博", "weibo", "sina weibo"]),
        SourceApp(id: "xiaohongshu", displayName: String(localized: "小红书"),
                  iconName: "book.fill", aliases: ["小红书", "xiaohongshu", "red"]),
        SourceApp(id: "douyin", displayName: String(localized: "抖音"),
                  iconName: "music.note", aliases: ["抖音", "douyin"]),
        SourceApp(id: "whatsapp", displayName: "WhatsApp",
                  iconName: "phone.fill", aliases: ["whatsapp", "whatsapp images", "whatsapp video"]),
        SourceApp(id: "telegram", displayName: "Telegram",
                  iconName: "paperplane.fill", aliases: ["telegram"]),
        SourceApp(id: "instagram", displayName: "Instagram",
                  iconName: "camera.fill", aliases: ["instagram"]),
        SourceApp(id: "snapchat", displayName: "Snapchat",
                  iconName: "bolt.fill", aliases: ["snapchat"]),
        SourceApp(id: "messenger", displayName: "Messenger",
                  iconName: "bubble.left.and.bubble.right.fill", aliases: ["messenger", "facebook messenger"]),
        SourceApp(id: "facebook", displayName: "Facebook",
                  iconName: "person.2.fill", aliases: ["facebook"]),
        SourceApp(id: "line", displayName: "LINE",
                  iconName: "bubble.right.fill", aliases: ["line"]),
        SourceApp(id: "twitter", displayName: "X",
                  iconName: "xmark", aliases: ["twitter", "x"]),
    ]

    static func match(albumTitle: String) -> SourceApp? {
        let normalized = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return known.first { $0.aliases.contains(normalized) }
    }
}

struct SourceAlbum: Identifiable, Sendable {
    let id: String
    let app: SourceApp
    let title: String
    let assetIDs: [String]
    let totalSize: Int64

    var count: Int { assetIDs.count }
    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

@MainActor @Observable
final class SourceAlbumService {
    private(set) var albums: [SourceAlbum] = []
    private(set) var isLoading = false

    /// 扫描系统里的用户相册，挑出由已知第三方 App 创建的那些。
    /// 第三方 App 通过 `PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:)`
    /// 建的相册都是 `.albumRegular`。
    func loadAlbums(photoLibrary: PhotoLibraryService) async {
        isLoading = true
        defer { isLoading = false }

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )

        var found: [SourceAlbum] = []
        collections.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle,
                  let app = SourceApp.match(albumTitle: title) else { return }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assetsResult = PHAsset.fetchAssets(in: collection, options: options)
            guard assetsResult.count > 0 else { return }

            var ids: [String] = []
            var size: Int64 = 0
            ids.reserveCapacity(assetsResult.count)
            assetsResult.enumerateObjects { asset, _, _ in
                ids.append(asset.localIdentifier)
                size += photoLibrary.fileSize(for: asset)
            }

            found.append(SourceAlbum(
                id: collection.localIdentifier,
                app: app,
                title: title,
                assetIDs: ids,
                totalSize: size
            ))
        }

        // 占空间大的排前面
        albums = found.sorted { $0.totalSize > $1.totalSize }
    }
}
```

- [ ] **Step 4: 注册到服务容器** — 修改 `AlbumSlim/App/AppServiceContainer.swift`

属性区加：

```swift
    let sourceAlbum: SourceAlbumService
```

`init()` 内加：

```swift
        self.sourceAlbum = SourceAlbumService()
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/SourceAlbumServiceTests
```

Expected: 8 个测试全部 PASS

- [ ] **Step 6: 提交**

```bash
git add AlbumSlim/Services/SourceAlbumService.swift AlbumSlim/App/AppServiceContainer.swift AlbumSlimTests/SourceAlbumServiceTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增 SourceAlbumService: 识别微信/QQ/小红书等 13 个第三方 App 相册"
```

---

### Task 8: 第三方相册接入滑动清理入口

**Files:**
- Modify: `AlbumSlim/ViewModels/SwipeCleanHomeViewModel.swift`
- Modify: `AlbumSlim/Views/SwipeClean/SwipeCleanHomeView.swift`

**Interfaces:**
- Consumes: Task 7 的 `SourceAlbumService.loadAlbums(photoLibrary:)`、`SourceAlbum`；Task 3 的 `SwipeCleanBucket.Kind.sourceAlbum(localIdentifier:)`
- Produces: `SwipeCleanHomeViewModel.appBuckets: [SwipeCleanBucket]`

- [ ] **Step 1: 扩展 ViewModel** — 修改 `AlbumSlim/ViewModels/SwipeCleanHomeViewModel.swift`

在 `buckets` 属性下方新增：

```swift
    /// 第三方 App 相册堆，与月份堆分开展示
    private(set) var appBuckets: [SwipeCleanBucket] = []
```

在 `loadBuckets(services:)` 方法体最后（`buckets = result.sorted {...}` 之后）追加：

```swift
        await loadAppBuckets(services: services)
```

并在 `remainingCount(for:services:)` 之前新增：

```swift
    private func loadAppBuckets(services: AppServiceContainer) async {
        await services.sourceAlbum.loadAlbums(photoLibrary: services.photoLibrary)
        appBuckets = services.sourceAlbum.albums.map { album in
            SwipeCleanBucket(
                id: "album-\(album.id)",
                kind: .sourceAlbum(localIdentifier: album.id),
                title: album.app.displayName,
                assetIDs: album.assetIDs,
                totalSize: album.totalSize
            )
        }
    }

    /// 第三方相册对应的图标，未知时回退到通用图标
    func iconName(for bucket: SwipeCleanBucket) -> String {
        switch bucket.kind {
        case .month:
            return "calendar"
        case .sourceAlbum:
            return SourceApp.known.first { $0.displayName == bucket.title }?.iconName
                ?? "square.stack.3d.up"
        case .screenshots:
            return "camera.viewfinder"
        case .videos:
            return "video"
        }
    }
```

- [ ] **Step 2: 入口页加一个 Section** — 修改 `AlbumSlim/Views/SwipeClean/SwipeCleanHomeView.swift`

把 `List { ... }` 的内容替换为：

```swift
                List {
                    if !viewModel.appBuckets.isEmpty {
                        Section {
                            ForEach(viewModel.appBuckets) { bucket in
                                bucketRow(bucket)
                            }
                        } header: {
                            Text(String(localized: "聊天与社交 App 相册"))
                        } footer: {
                            Text(String(localized: "这些相册由对应 App 自动保存，通常是占空间最快的一类。"))
                        }
                    }

                    Section {
                        ForEach(viewModel.buckets) { bucket in
                            bucketRow(bucket)
                        }
                    } header: {
                        Text(String(localized: "按月份逐堆清理"))
                    } footer: {
                        Text(String(localized: "左滑删除，右滑保留。删除的照片先进垃圾桶，可随时恢复。"))
                    }
                }
```

并把 `bucketRow` 的 label 加上图标：

```swift
    private func bucketRow(_ bucket: SwipeCleanBucket) -> some View {
        let remaining = viewModel.remainingCount(for: bucket, services: services)
        return NavigationLink {
            SwipeCleanSessionView(bucket: bucket)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.iconName(for: bucket))
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.title)
                        .font(.body.weight(.medium))
                    Text(String(localized: "\(bucket.count) 张 · \(bucket.totalSizeText)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if remaining == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(String(localized: "剩 \(remaining)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(remaining == 0)
    }
```

同时把空状态判断从 `viewModel.buckets.isEmpty` 改为：

```swift
            } else if viewModel.buckets.isEmpty && viewModel.appBuckets.isEmpty {
```

- [ ] **Step 3: 构建**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/ViewModels/SwipeCleanHomeViewModel.swift AlbumSlim/Views/SwipeClean/SwipeCleanHomeView.swift
git commit -m "第三方 App 相册接入滑动清理入口"
```

---

### Task 9: 联系人去重服务

**背景:** 竞品提供重复联系人合并。这引入 `NSContactsUsageDescription` 新权限，会稀释「只碰相册」的隐私叙事——因此实现上**只在用户主动进入该模块时才请求权限**，绝不在启动或引导流程里请求。

**Files:**
- Create: `AlbumSlim/Models/ContactDuplicateGroup.swift`
- Create: `AlbumSlim/Services/ContactCleanupService.swift`
- Modify: `AlbumSlim/App/AppServiceContainer.swift`
- Modify: `project.yml`（新增 `INFOPLIST_KEY_NSContactsUsageDescription`）
- Test: `AlbumSlimTests/ContactCleanupServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct ContactSummary: Identifiable, Sendable` — `id: String`、`fullName: String`、`phones: [String]`、`emails: [String]`、`organization: String`、`hasImage: Bool`
  - `struct ContactDuplicateGroup: Identifiable, Sendable` — `id: String`、`reason: MatchReason`、`contacts: [ContactSummary]`、`primaryID: String`
  - `enum ContactDuplicateGroup.MatchReason: String, Sendable { case samePhone, sameName }`
  - `ContactCleanupService.normalizePhone(_ raw: String) -> String`（静态）
  - `ContactCleanupService.findDuplicates(in contacts: [ContactSummary]) -> [ContactDuplicateGroup]`（静态，纯函数）
  - `ContactCleanupService.pickPrimary(from contacts: [ContactSummary]) -> String`（静态）
  - `@MainActor @Observable final class ContactCleanupService`，方法 `requestAccess() async -> Bool`、`scan() async`、`merge(group:) async throws`

- [ ] **Step 1: 写失败测试** — 创建 `AlbumSlimTests/ContactCleanupServiceTests.swift`

```swift
import XCTest
@testable import AlbumSlim

final class ContactCleanupServiceTests: XCTestCase {

    private func contact(
        _ id: String,
        name: String = "张三",
        phones: [String] = [],
        emails: [String] = [],
        org: String = "",
        hasImage: Bool = false
    ) -> ContactSummary {
        ContactSummary(id: id, fullName: name, phones: phones, emails: emails,
                       organization: org, hasImage: hasImage)
    }

    // MARK: - 号码归一化

    func testNormalizePhoneStripsFormatting() {
        XCTAssertEqual(ContactCleanupService.normalizePhone("+86 138-0013-8000"), "13800138000")
    }

    func testNormalizePhoneStripsCountryCode() {
        // 同一个号码的两种写法必须归一到同一个键
        XCTAssertEqual(
            ContactCleanupService.normalizePhone("+8613800138000"),
            ContactCleanupService.normalizePhone("13800138000")
        )
    }

    func testNormalizeShortNumberKeptAsIs() {
        XCTAssertEqual(ContactCleanupService.normalizePhone("10086"), "10086")
    }

    // MARK: - 重复检测

    func testFindsDuplicatesBySharedPhone() {
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "张三", phones: ["13800138000"]),
            contact("2", name: "张三(工作)", phones: ["+86 138 0013 8000"]),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reason, .samePhone)
        XCTAssertEqual(groups.first?.contacts.count, 2)
    }

    func testFindsDuplicatesByIdenticalName() {
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "李四", phones: ["111"]),
            contact("2", name: "李四", phones: ["222"]),
        ])
        XCTAssertEqual(groups.first?.reason, .sameName)
    }

    func testDistinctContactsProduceNoGroups() {
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "张三", phones: ["111"]),
            contact("2", name: "李四", phones: ["222"]),
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyNameDoesNotGroup() {
        // 两个无名无号的条目不应被当成重复
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "", phones: []),
            contact("2", name: "", phones: []),
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testPhoneMatchTakesPriorityOverNameMatch() {
        // 同号码的分组不应再被同名规则重复收录
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "王五", phones: ["13900139000"]),
            contact("2", name: "王五", phones: ["13900139000"]),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reason, .samePhone)
    }

    // MARK: - 主记录选择

    func testPrimaryPrefersContactWithMostInformation() {
        let rich = contact("rich", phones: ["1", "2"], emails: ["a@b.com"], org: "Acme", hasImage: true)
        let sparse = contact("sparse", phones: ["1"])
        XCTAssertEqual(ContactCleanupService.pickPrimary(from: [sparse, rich]), "rich")
    }

    func testPrimaryIsStableForEqualContacts() {
        let a = contact("a", phones: ["1"])
        let b = contact("b", phones: ["1"])
        // 信息量相同时取第一个，保证结果可预测
        XCTAssertEqual(ContactCleanupService.pickPrimary(from: [a, b]), "a")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/ContactCleanupServiceTests
```

Expected: 编译失败，`cannot find 'ContactSummary' in scope`

- [ ] **Step 3: 实现模型** — 创建 `AlbumSlim/Models/ContactDuplicateGroup.swift`

```swift
import Foundation

struct ContactSummary: Identifiable, Sendable, Equatable {
    let id: String
    let fullName: String
    let phones: [String]
    let emails: [String]
    let organization: String
    let hasImage: Bool

    /// 信息完整度，用于挑选合并后的主记录
    var richness: Int {
        var score = phones.count * 2 + emails.count * 2
        if !organization.isEmpty { score += 1 }
        if hasImage { score += 3 }
        if !fullName.isEmpty { score += 1 }
        return score
    }

    var subtitle: String {
        if let phone = phones.first { return phone }
        if let email = emails.first { return email }
        return organization
    }
}

struct ContactDuplicateGroup: Identifiable, Sendable {
    enum MatchReason: String, Sendable {
        case samePhone
        case sameName

        var label: String {
            switch self {
            case .samePhone: return String(localized: "号码相同")
            case .sameName:  return String(localized: "姓名相同")
            }
        }
    }

    let id: String
    let reason: MatchReason
    let contacts: [ContactSummary]
    let primaryID: String

    var primary: ContactSummary? {
        contacts.first { $0.id == primaryID }
    }

    /// 合并后会被删掉的条目数
    var removableCount: Int { max(0, contacts.count - 1) }
}
```

- [ ] **Step 4: 实现服务** — 创建 `AlbumSlim/Services/ContactCleanupService.swift`

```swift
import Foundation
import Contacts

@MainActor @Observable
final class ContactCleanupService {

    private(set) var groups: [ContactDuplicateGroup] = []
    private(set) var isScanning = false
    private(set) var totalContactCount = 0
    var errorMessage: String?

    private let store = CNContactStore()

    // MARK: - 权限

    /// 只在用户主动进入联系人模块时调用，绝不在启动或引导流程里请求
    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - 扫描

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        errorMessage = nil

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]

        var summaries: [ContactSummary] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                summaries.append(Self.summarize(contact))
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        totalContactCount = summaries.count
        groups = Self.findDuplicates(in: summaries)
    }

    private static func summarize(_ contact: CNContact) -> ContactSummary {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? "\(contact.familyName)\(contact.givenName)"
        return ContactSummary(
            id: contact.identifier,
            fullName: name.trimmingCharacters(in: .whitespaces),
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String },
            organization: contact.organizationName,
            hasImage: contact.imageDataAvailable
        )
    }

    // MARK: - 归一化与匹配（纯函数，可单测）

    /// 抹掉格式差异，并去掉中国大陆 +86 国家码，让同一号码的多种写法归到同一个键
    static func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count > 11 else { return digits }
        if digits.hasPrefix("86") {
            return String(digits.dropFirst(2))
        }
        // 其它国家码：保留后 11 位做近似匹配
        return String(digits.suffix(11))
    }

    /// 先按号码分组，剩下的再按姓名分组。号码优先——同号码的条目不会被姓名规则重复收录。
    static func findDuplicates(in contacts: [ContactSummary]) -> [ContactDuplicateGroup] {
        var groups: [ContactDuplicateGroup] = []
        var claimed = Set<String>()

        // 1) 号码相同
        var byPhone: [String: [ContactSummary]] = [:]
        for contact in contacts {
            for phone in contact.phones {
                let key = normalizePhone(phone)
                guard !key.isEmpty else { continue }
                if byPhone[key]?.contains(where: { $0.id == contact.id }) == true { continue }
                byPhone[key, default: []].append(contact)
            }
        }
        for (key, members) in byPhone where members.count > 1 {
            let fresh = members.filter { !claimed.contains($0.id) }
            guard fresh.count > 1 else { continue }
            fresh.forEach { claimed.insert($0.id) }
            groups.append(ContactDuplicateGroup(
                id: "phone-\(key)",
                reason: .samePhone,
                contacts: fresh,
                primaryID: pickPrimary(from: fresh)
            ))
        }

        // 2) 姓名相同（排除已被号码规则收走的，以及空名）
        var byName: [String: [ContactSummary]] = [:]
        for contact in contacts where !claimed.contains(contact.id) {
            let key = contact.fullName.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            byName[key, default: []].append(contact)
        }
        for (key, members) in byName where members.count > 1 {
            members.forEach { claimed.insert($0.id) }
            groups.append(ContactDuplicateGroup(
                id: "name-\(key)",
                reason: .sameName,
                contacts: members,
                primaryID: pickPrimary(from: members)
            ))
        }

        // 结果按可删除数量降序，收益大的排前面；同数量时按 id 保证顺序稳定
        return groups.sorted {
            $0.removableCount == $1.removableCount
                ? $0.id < $1.id
                : $0.removableCount > $1.removableCount
        }
    }

    /// 信息最全的作为主记录；并列时取输入顺序里的第一个，保证结果可预测
    static func pickPrimary(from contacts: [ContactSummary]) -> String {
        guard var best = contacts.first else { return "" }
        for candidate in contacts.dropFirst() where candidate.richness > best.richness {
            best = candidate
        }
        return best.id
    }

    // MARK: - 合并

    /// 把组内其余条目的号码与邮箱并入主记录，然后删除其余条目。
    /// 不可逆——调用方必须先弹确认。
    func merge(group: ContactDuplicateGroup) async throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]

        let ids = group.contacts.map(\.id)
        let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
        let fetched = try store.unifiedContacts(matching: predicate, keysToFetch: keys)

        guard let primaryContact = fetched.first(where: { $0.identifier == group.primaryID }) else {
            throw NSError(domain: "ContactCleanup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "找不到主联系人")
            ])
        }

        let mutable = primaryContact.mutableCopy() as! CNMutableContact
        let others = fetched.filter { $0.identifier != group.primaryID }

        // 按归一化号码去重后并入
        var seenPhones = Set(mutable.phoneNumbers.map { Self.normalizePhone($0.value.stringValue) })
        var seenEmails = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })

        for other in others {
            for phone in other.phoneNumbers {
                let key = Self.normalizePhone(phone.value.stringValue)
                guard !key.isEmpty, !seenPhones.contains(key) else { continue }
                seenPhones.insert(key)
                mutable.phoneNumbers.append(phone)
            }
            for email in other.emailAddresses {
                let key = (email.value as String).lowercased()
                guard !key.isEmpty, !seenEmails.contains(key) else { continue }
                seenEmails.insert(key)
                mutable.emailAddresses.append(email)
            }
            if mutable.organizationName.isEmpty, !other.organizationName.isEmpty {
                mutable.organizationName = other.organizationName
            }
        }

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        for other in others {
            guard let deletable = other.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(deletable)
        }
        try store.execute(saveRequest)

        groups.removeAll { $0.id == group.id }
    }
}
```

- [ ] **Step 5: 注册服务并加权限声明**

修改 `AlbumSlim/App/AppServiceContainer.swift`，属性区加：

```swift
    let contactCleanup: ContactCleanupService
```

`init()` 内加：

```swift
        self.contactCleanup = ContactCleanupService()
```

修改 `project.yml`，在 `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` 那一行之后加：

```yaml
        INFOPLIST_KEY_NSContactsUsageDescription: "闪图需要访问通讯录来找出重复联系人，所有处理均在本地完成，不会上传任何信息。"
```

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodegen generate && xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:AlbumSlimTests/ContactCleanupServiceTests
```

Expected: 10 个测试全部 PASS

- [ ] **Step 7: 提交**

```bash
git add AlbumSlim/Models/ContactDuplicateGroup.swift AlbumSlim/Services/ContactCleanupService.swift AlbumSlim/App/AppServiceContainer.swift project.yml AlbumSlimTests/ContactCleanupServiceTests.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增 ContactCleanupService: 按号码/姓名找重复联系人并合并"
```

---

### Task 10: 联系人去重界面

**Files:**
- Create: `AlbumSlim/Views/Contacts/ContactCleanupView.swift`
- Modify: `AlbumSlim/Views/Settings/SettingsView.swift`（加入口）
- Read first: `AlbumSlim/Views/Settings/SettingsView.swift`（确认现有 Section 结构与导航写法）

**Interfaces:**
- Consumes: Task 9 的 `ContactCleanupService`、`ContactDuplicateGroup`、`ContactSummary`
- Produces: `ContactCleanupView`

- [ ] **Step 1: 实现界面** — 创建 `AlbumSlim/Views/Contacts/ContactCleanupView.swift`

```swift
import SwiftUI
import Contacts

struct ContactCleanupView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var pendingMerge: ContactDuplicateGroup?
    @State private var showPaywall = false

    private var service: ContactCleanupService { services.contactCleanup }

    var body: some View {
        Group {
            switch service.authorizationStatus {
            case .authorized:
                contentView
            case .denied, .restricted:
                deniedView
            default:
                requestView
            }
        }
        .navigationTitle(String(localized: "重复联系人"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert(
            String(localized: "合并这些联系人？"),
            isPresented: Binding(
                get: { pendingMerge != nil },
                set: { if !$0 { pendingMerge = nil } }
            ),
            presenting: pendingMerge
        ) { group in
            Button(String(localized: "合并"), role: .destructive) {
                performMerge(group)
            }
            Button(AppStrings.cancel, role: .cancel) { pendingMerge = nil }
        } message: { group in
            Text(String(localized: "号码和邮箱会并入信息最全的那条，其余 \(group.removableCount) 条将被删除。此操作不可撤销。"))
        }
    }

    // MARK: - 未授权

    private var requestView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(String(localized: "查找重复联系人"))
                .font(.title3.bold())
            Text(String(localized: "闪图会在本地比对号码与姓名，找出重复条目。通讯录内容不会离开你的设备。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(String(localized: "允许访问通讯录")) {
                Task {
                    if await service.requestAccess() {
                        await service.scan()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label(String(localized: "未授权通讯录"), systemImage: "lock")
        } description: {
            Text(String(localized: "请到系统设置里允许闪图访问通讯录"))
        } actions: {
            Button(String(localized: "去设置")) { PermissionManager.openSettings() }
        }
    }

    // MARK: - 已授权

    @ViewBuilder
    private var contentView: some View {
        if service.isScanning {
            ProgressView(AppStrings.scanning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if service.groups.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "没有重复联系人"), systemImage: "checkmark.seal")
            } description: {
                Text(String(localized: "已检查 \(service.totalContactCount) 位联系人"))
            }
            .task { if service.totalContactCount == 0 { await service.scan() } }
        } else {
            List {
                ForEach(service.groups) { group in
                    Section {
                        ForEach(group.contacts) { contact in
                            contactRow(contact, isPrimary: contact.id == group.primaryID)
                        }
                        Button {
                            requestMerge(group)
                        } label: {
                            Label(
                                String(localized: "合并为 1 条（删除 \(group.removableCount) 条）"),
                                systemImage: "arrow.triangle.merge"
                            )
                        }
                    } header: {
                        Text(group.reason.label)
                    }
                }
            }
        }
    }

    private func contactRow(_ contact: ContactSummary, isPrimary: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName.isEmpty ? String(localized: "(无姓名)") : contact.fullName)
                    .font(.body)
                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isPrimary {
                Text(String(localized: "保留"))
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: - 动作

    private func requestMerge(_ group: ContactDuplicateGroup) {
        // 合并是清理操作，门控口径与其它模块一致
        guard ProFeatureGate.canClean(isPro: services.subscription.isPro) else {
            showPaywall = true
            return
        }
        pendingMerge = group
    }

    private func performMerge(_ group: ContactDuplicateGroup) {
        pendingMerge = nil
        Task {
            do {
                try await service.merge(group: group)
                services.toast.show(String(localized: "已合并 \(group.contacts.count) 条联系人"))
            } catch {
                services.toast.show(error.localizedDescription)
            }
        }
    }
}
```

**注意:** `services.toast.show(_:)` 的实际方法名以 `AlbumSlim/Services/ToastCenter.swift` 为准，实施前先 Read 并适配。

- [ ] **Step 2: 在设置页加入口** — 修改 `AlbumSlim/Views/Settings/SettingsView.swift`

先 Read 该文件确认现有 Section 结构，然后在功能类 Section 内新增一行：

```swift
                NavigationLink {
                    ContactCleanupView()
                } label: {
                    Label(String(localized: "重复联系人"), systemImage: "person.2.slash")
                }
```

- [ ] **Step 3: 构建**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/Views/Contacts AlbumSlim/Views/Settings/SettingsView.swift AlbumSlim.xcodeproj/project.pbxproj
git commit -m "新增重复联系人界面: 分组展示 + 合并确认 + Pro 门控"
```

---

### Task 11: 成就与统计接线

**背景:** 新增的滑动清理与联系人合并要计入既有成就体系，否则这两个模块的清理量在成就页里凭空消失。

**Files:**
- Read first: `AlbumSlim/Services/AchievementService.swift`（确认 `recordCleanup` 的实际签名与记账口径）
- Modify: `AlbumSlim/Views/Trash/GlobalTrashView.swift`（确认永久删除时已记账，未记则补）
- Test: `AlbumSlimTests/SwipeCleanProgressStoreTests.swift`（追加）

**Interfaces:**
- Consumes: `AchievementService.recordCleanup(...)`（签名以实际代码为准）

- [ ] **Step 1: 确认现有记账口径**

```bash
grep -n "recordCleanup" -r AlbumSlim --include="*.swift"
```

按 `docs/superpowers/plans/2026-07-24-product-optimization-p0-p1.md` 的决定，成就记账口径统一收敛到「永久删除」时点。滑动清理走的是 `TrashService.moveToTrash`，最终永久删除仍在 `GlobalTrashView` 发生——**若上一份计划已完成，本任务无需改动记账逻辑**，只需验证。

本任务是**验证任务，不新增测试**——记账逻辑本身在上一份计划里已完成并测过，这里只确认新模块没有绕开它。

- [ ] **Step 2: 跑全量测试确认无回归**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 全部 PASS

- [ ] **Step 3: 确认滑动清理未绕开记账**

确认 `SwipeCleanViewModel.decide` 中 `.trash` 分支只调用 `services.trash.moveToTrash`，**没有**直接调用 `photoLibrary.deleteAssets` 或 `achievement.recordCleanup`：

```bash
grep -n "deleteAssets\|recordCleanup" AlbumSlim/ViewModels/SwipeCleanViewModel.swift AlbumSlim/Views/SwipeClean/*.swift
```

Expected: 无输出。释放量只在垃圾桶永久删除时记账，滑动清理不重复记。

- [ ] **Step 4: 手动验收清单**

在模拟器上依次确认：

1. 照片 Tab 默认落在「逐张清理」，能看到月份堆与第三方 App 相册堆
2. 进入一堆，左滑出现红色「删除」角标，右滑出现绿色「保留」角标
3. 非 Pro 用户左滑时弹出 Paywall，卡片回弹不推进
4. 撤销按钮能把上一张退回来，被删的那张从垃圾桶恢复
5. 退出再进同一堆，已保留的照片不再出现
6. 垃圾桶里能看到滑动清理删掉的照片，来源标为「逐张清理」
7. 设置页能进入「重复联系人」，未授权时显示请求页而非空白

- [ ] **Step 5: 提交**

本任务若无代码改动则无需 commit（纯验证）。若 Step 3 发现绕开记账并做了修正，则：

```bash
git add -A
git commit -m "修正滑动清理的记账口径"
```

---

### Task 12: 本地化补齐（9 种语言）

**Files:**
- Modify: `AlbumSlim/Localizable.xcstrings`
- Read first: `AlbumSlim/Utils/AppStrings.swift`（复用已有术语，避免同义词分裂）

**Interfaces:**
- Consumes: Task 1–11 新增的全部中文源文案

- [ ] **Step 1: 收集本次新增的所有字符串**

```bash
grep -rn "String(localized:" AlbumSlim/Views/SwipeClean AlbumSlim/Views/Contacts AlbumSlim/Services/SourceAlbumService.swift AlbumSlim/Services/ContactCleanupService.swift AlbumSlim/Models/ContactDuplicateGroup.swift AlbumSlim/Models/SwipeCleanBucket.swift
```

同时检查 `MainTabView.swift` 里新增的 `"逐张清理"` LocalizedStringKey。

- [ ] **Step 2: 逐条补 en 翻译到 `AlbumSlim/Localizable.xcstrings`**

用以下对照表（术语与既有 `AppStrings` 保持一致）：

| 中文 | English |
|---|---|
| 逐张清理 | Swipe to Clean |
| 删除 | Delete |
| 保留 | Keep |
| 按月份逐堆清理 | Clean by Month |
| 聊天与社交 App 相册 | Chat & Social Albums |
| 这些相册由对应 App 自动保存，通常是占空间最快的一类。 | These albums are saved automatically by their apps and usually grow the fastest. |
| 左滑删除，右滑保留。删除的照片先进垃圾桶，可随时恢复。 | Swipe left to delete, right to keep. Deleted photos go to Trash and can be restored anytime. |
| 这一堆清完了 | This batch is done |
| 本次可释放 %@，去垃圾桶确认删除 | %@ ready to free up — confirm in Trash |
| 重新清理这一堆 | Clean this batch again |
| 没有可清理的照片 | Nothing to clean |
| 相册为空，或每个月份的照片都少于 5 张 | Your library is empty, or every month has fewer than 5 photos |
| %lld 张 · %@ | %lld photos · %@ |
| 剩 %lld | %lld left |
| 微信 | WeChat |
| 微博 | Weibo |
| 小红书 | RED |
| 抖音 | Douyin |
| 重复联系人 | Duplicate Contacts |
| 查找重复联系人 | Find Duplicate Contacts |
| 闪图会在本地比对号码与姓名，找出重复条目。通讯录内容不会离开你的设备。 | AlbumSlim compares numbers and names on device. Your contacts never leave your iPhone. |
| 允许访问通讯录 | Allow Contacts Access |
| 未授权通讯录 | Contacts Access Denied |
| 请到系统设置里允许闪图访问通讯录 | Allow AlbumSlim to access Contacts in Settings |
| 去设置 | Open Settings |
| 没有重复联系人 | No Duplicates Found |
| 已检查 %lld 位联系人 | Checked %lld contacts |
| 号码相同 | Same Number |
| 姓名相同 | Same Name |
| 合并为 1 条（删除 %lld 条） | Merge into 1 (remove %lld) |
| 合并这些联系人？ | Merge these contacts? |
| 合并 | Merge |
| 号码和邮箱会并入信息最全的那条，其余 %lld 条将被删除。此操作不可撤销。 | Numbers and emails move to the most complete entry; the other %lld will be deleted. This cannot be undone. |
| 已合并 %lld 条联系人 | Merged %lld contacts |
| (无姓名) | (No Name) |
| 找不到主联系人 | Primary contact not found |
| %lld / %lld | %lld / %lld |

同时补上 `project.yml` 里新增的 `NSContactsUsageDescription` 的英文版——Info.plist 键的本地化需要 `InfoPlist.xcstrings`，若项目尚无该文件则保留中文，并在 commit 说明里注明。

- [ ] **Step 3: 补齐其余 7 种语言**

除 `zh-Hans`（源）和 `en`（Step 2 已完成）外，还需补 `zh-Hant`、`ja`、`ko`、`es`、`fr`、`de`、`pt-BR`、`ru` 共 8 种。

先按下表统一核心术语，避免同一概念在不同句子里译法漂移。表中每个词在该语言的所有句子中必须一致使用：

| zh-Hans | zh-Hant | ja | ko | es | fr | de | pt-BR | ru |
|---|---|---|---|---|---|---|---|---|
| 逐张清理 | 逐張清理 | 1枚ずつ整理 | 한 장씩 정리 | Limpiar una a una | Nettoyer une à une | Einzeln aufräumen | Limpar uma a uma | Разбор по одному |
| 删除 | 刪除 | 削除 | 삭제 | Eliminar | Supprimer | Löschen | Excluir | Удалить |
| 保留 | 保留 | 残す | 보관 | Conservar | Garder | Behalten | Manter | Оставить |
| 合并 | 合併 | 統合 | 병합 | Combinar | Fusionner | Zusammenführen | Mesclar | Объединить |
| 垃圾桶 | 垃圾桶 | ゴミ箱 | 휴지통 | Papelera | Corbeille | Papierkorb | Lixeira | Корзина |
| 重复联系人 | 重複聯絡人 | 重複した連絡先 | 중복 연락처 | Contactos duplicados | Contacts en double | Doppelte Kontakte | Contatos duplicados | Дубликаты контактов |
| 通讯录 | 通訊錄 | 連絡先 | 연락처 | Contactos | Contacts | Kontakte | Contatos | Контакты |
| 相册 | 相簿 | アルバム | 앨범 | Álbum | Album | Album | Álbum | Альбом |
| 照片 | 照片 | 写真 | 사진 | Fotos | Photos | Fotos | Fotos | Фото |

然后为 Step 1 收集到的**每一条**新增字符串，在 `AlbumSlim/Localizable.xcstrings` 里补上这 8 种语言的 `stringUnit`。格式参照文件中已有条目：

```json
"逐张清理" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Swipe to Clean" } },
    "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "逐張清理" } },
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "1枚ずつ整理" } },
    "ko" : { "stringUnit" : { "state" : "translated", "value" : "한 장씩 정리" } },
    "es" : { "stringUnit" : { "state" : "translated", "value" : "Limpiar una a una" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Nettoyer une à une" } },
    "de" : { "stringUnit" : { "state" : "translated", "value" : "Einzeln aufräumen" } },
    "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Limpar uma a uma" } },
    "ru" : { "stringUnit" : { "state" : "translated", "value" : "Разбор по одному" } }
  }
}
```

带格式占位符的条目（`%lld`、`%@`）必须在每种语言里保留相同数量与类型的占位符，顺序可按该语言语法调整（调整顺序时用 `%1$@` 形式显式编号）。

- [ ] **Step 4: 验证 9 种语言零缺失**

用下面的脚本检查每个 key 是否都有 9 种语言（源语言 zh-Hans 不出现在 localizations 里，故期望 9 个 localization 条目：en/zh-Hant/ja/ko/es/fr/de/pt-BR/ru）：

```bash
python3 -c "
import json
langs = {'en','zh-Hant','ja','ko','es','fr','de','pt-BR','ru'}
data = json.load(open('AlbumSlim/Localizable.xcstrings'))
bad = []
for key, entry in data['strings'].items():
    have = set(entry.get('localizations', {}).keys())
    missing = langs - have
    if missing:
        bad.append((key, sorted(missing)))
print(f'总计 {len(data[\"strings\"])} 条, 缺失 {len(bad)} 条')
for key, miss in bad[:40]:
    print(f'  {key!r}: 缺 {miss}')
"
```

Expected: `缺失 0 条`

若既有旧条目也报缺失，只需保证**本次新增的条目**为 0 缺失，旧条目的缺口记录到 commit 说明里，不在本任务扩大范围。

- [ ] **Step 5: 构建并检查有无未翻译警告**

```bash
xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' 2>&1 | grep -i "localiz\|warning: " | head -20
```

Expected: 无本地化相关警告

- [ ] **Step 6: 跑全量测试**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 全部 PASS

- [ ] **Step 7: 提交**

```bash
git add AlbumSlim/Localizable.xcstrings
git commit -m "本地化: 滑动清理 + 第三方相册 + 联系人去重文案补齐 9 种语言"
```

---

## 竞品覆盖对照

计划完成后，与 Cleanup 的功能对照：

| 竞品功能 | 我们的落地 | 差异化 |
|---|---|---|
| 左右滑动清理 | Task 3–6 | 滑的是 AI 预筛后的候选，不是全相册盲滑——直接解掉竞品「全靠手滑」的头号差评 |
| 待删除垃圾箱 | **已有** `TrashService` | 跨模块统一，含体积统计与库同步 |
| 相似照片智能择优 | Task 1–2 | 竞品只提微笑/对焦，我们额外用收藏与编辑历史作为强保留信号 |
| 视频按大小排序 | **已有** `VideoListView` | 另有 HEVC 三档压缩，竞品无 |
| 聊天 App 相册 | Task 7–8 | 覆盖微信/QQ/小红书/抖音/微博，竞品只有海外 App |
| 联系人去重合并 | Task 9–10 | 号码归一化处理 +86，中国号码场景更准 |
| 邮件清理 | **不做** | 与本地隐私定位冲突，显式 Non-Goal |
| 截图批量清理 | **已有** `ScreenshotListView` | 另有 OCR 与导出备忘录，竞品无 |
| — | **已有** 废片检测 / 连拍 / 成就分享 / Widget / 沉浸式浏览 | 竞品完全没有 |

价格上仍是 $1 买断 vs 竞品周订阅 ¥18–¥88 —— 这是拉新时最硬的一条对比文案。

## 遗留风险

1. **通讯录权限稀释隐私叙事**。Task 9–10 已把权限请求限制在用户主动进入模块时。若上架后发现审核或用户反馈有阻力，可把整个 Phase D 降级为付费墙后的可选模块。
2. **`CIDetector` 是老 API**。目前仍是 iOS 上唯一直接给出 `hasSmile` / `eyeClosed` 的接口，Vision 无对应能力。若未来被弃用，替换点集中在 `BestPhotoAnalyzer.faceScore(for:)` 一个方法内。
3. **Task 2 增加相似组扫描耗时**。择优只在组内（通常 2–5 张）执行，但每张多一次 CIDetector 调用。若实测大库明显变慢，改为仅对含人脸的组走完整评分，其余组沿用文件大小。
4. **月份分堆在超大相册上的内存**。`SwipeCleanHomeViewModel.loadBuckets` 一次性 enumerate 全库 PHAsset。5 万张以上时需要改为分批 + 只存 localIdentifier，实施时若实测 RSS 超过 200MB 就要改。
