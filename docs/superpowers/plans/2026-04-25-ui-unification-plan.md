# AlbumSlim UI 统一化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不做视觉重绘的前提下，把 AlbumSlim 5 个 Tab 的批量选择、删除/垃圾桶、术语、SF Symbol、按钮、Toast、Haptic、加载/空状态全部统一到一套规范，并以共享组件沉淀。

**Architecture:** Wave 1 沉淀基础设施（图标/文案/触觉/按钮常量 + 扩展现有 TrashService 支持多模块来源 + 共享 UI 组件 + 全局垃圾桶视图）。Wave 2 各模块并行接入新规范。Wave 3 收尾、废弃旧代码、最终验证。

**Tech Stack:** Swift 6 / SwiftUI (iOS 17+) / SwiftData / Photos / Swift Testing (`@Test`/`#expect`) / XcodeGen。

**Spec:** [`docs/superpowers/specs/2026-04-25-ui-unification-design.md`](../specs/2026-04-25-ui-unification-design.md)

---

## 通用约定

- 所有新增 Swift 文件后必须执行 `xcodegen generate` 重新生成 xcodeproj
- 编译验证统一命令：
  ```
  xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
  ```
- 测试验证统一命令：
  ```
  xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
    -only-testing:AlbumSlimTests/<SuiteName>
  ```
- 所有 commit 消息中文

---

## Wave 1：基础设施（必须串行）

### Task 1：新增 SF Symbol 常量表

**Files:**
- Create: `AlbumSlim/Utils/AppIcons.swift`

- [ ] **Step 1：创建文件**

```swift
// AlbumSlim/Utils/AppIcons.swift
import Foundation

/// 全局 SF Symbol 常量表，统一各模块图标使用
enum AppIcons {
    // 模块语义
    static let similar = "square.on.square"
    static let waste = "photo.badge.exclamationmark"
    static let burst = "square.stack.3d.up.fill"
    static let largePhoto = "photo.badge.plus"
    static let screenshot = "camera.viewfinder"
    static let video = "video.fill"

    // 通用动作
    static let trash = "trash"
    static let trashFill = "trash.fill"
    static let restore = "arrow.uturn.backward"
    static let favorite = "heart"
    static let favoriteFill = "heart.fill"
    static let share = "square.and.arrow.up"
    static let more = "ellipsis"
    static let close = "xmark.circle.fill"
    static let info = "info.circle"
    static let settings = "gearshape.fill"
    static let scan = "sparkles.magnifyingglass"
    static let compress = "rectangle.compress.vertical"
    static let ocr = "text.viewfinder"
    static let achievement = "trophy.fill"
    static let proCrown = "crown.fill"

    // 状态
    static let circle = "circle"
    static let checkmarkCircle = "checkmark.circle"
    static let checkmarkCircleFill = "checkmark.circle.fill"
    static let checkmark = "checkmark"
}
```

- [ ] **Step 2：重新生成 xcodeproj**

Run: `xcodegen generate`
Expected: 无错误，新文件被加入 target

- [ ] **Step 3：编译验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Utils/AppIcons.swift
git commit -m "新增 AppIcons：统一 SF Symbol 常量"
```

---

### Task 2：新增文案常量表

**Files:**
- Create: `AlbumSlim/Utils/AppStrings.swift`

- [ ] **Step 1：创建文件**

```swift
// AlbumSlim/Utils/AppStrings.swift
import Foundation

/// 全局文案常量，统一术语
enum AppStrings {
    // 动作
    static let select = "选择"
    static let done = "完成"
    static let selectAll = "全选"
    static let deselectAll = "取消全选"
    static let cancel = "取消"
    static let restore = "恢复"
    static let moveToTrash = "移到垃圾桶"
    static let permanentlyDelete = "永久删除"
    static let emptyTrash = "全部清空"

    // 加载文案
    static let loading = "加载中…"
    static let scanning = "扫描中…"
    static let analyzing = "分析中…"
    static let compressing = "压缩中…"
    static let recognizing = "识别中…"

    // 计数 / 数量格式
    static func selected(_ count: Int) -> String { "已选 \(count) 项" }
    static func items(_ count: Int) -> String { "\(count) 项" }
    static func releasable(_ bytes: Int64) -> String {
        "可释放 " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // Toast 反馈
    static func movedToTrash(_ count: Int) -> String { "已移到垃圾桶 \(count) 项" }
    static func restored(_ count: Int) -> String { "已恢复 \(count) 项" }
    static func permanentlyDeleted(_ count: Int, freed: Int64) -> String {
        "已永久删除 \(count) 项，释放 " + ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
    }
    static func compressed(_ saved: Int64) -> String {
        "已压缩，节省 " + ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)
    }
    static let saved = "已保存"
    static let copied = "已复制到剪贴板"
    static let proRequired = "此功能需要 Pro"

    // 空状态前缀
    static func empty(_ object: String) -> String { "没有\(object)" }

    // 永久删除确认
    static func confirmPermanentDeleteTitle(_ count: Int) -> String { "永久删除 \(count) 项？" }
    static let confirmPermanentDeleteMessage = "此操作无法撤销，相册中将同时移除这些项"
    static let confirmEmptyTrashMessage = "此操作无法撤销，垃圾桶中所有项目都会被永久删除"
}
```

- [ ] **Step 2：重新生成 xcodeproj**

Run: `xcodegen generate`

- [ ] **Step 3：编译验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Utils/AppStrings.swift
git commit -m "新增 AppStrings：统一文案与术语"
```

---

### Task 3：新增触觉反馈封装

**Files:**
- Create: `AlbumSlim/Utils/Haptics.swift`

- [ ] **Step 1：创建文件**

```swift
// AlbumSlim/Utils/Haptics.swift
import UIKit

/// 全局触觉反馈封装。所有关键交互必须走这里。
@MainActor
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // 高层语义封装
    static func tap()              { light() }
    static func toggleSelect()     { selection() }
    static func moveToTrash()      { medium() }
    static func permanentDelete()  { heavy(); warning() }
    static func operationSuccess() { success() }
    static func proGate()          { warning() }
}
```

- [ ] **Step 2：重新生成 xcodeproj 并编译**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Utils/Haptics.swift
git commit -m "新增 Haptics：统一触觉反馈封装"
```

---

### Task 4：新增按钮样式 extensions

**Files:**
- Create: `AlbumSlim/Utils/ButtonStyles.swift`

- [ ] **Step 1：创建文件**

```swift
// AlbumSlim/Utils/ButtonStyles.swift
import SwiftUI

extension View {
    /// 主要操作按钮：底部 action bar 中的主按钮
    /// - destructive: true 时使用红色
    func primaryActionStyle(destructive: Bool = false) -> some View {
        self
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(destructive ? .red : .blue)
    }

    /// 次要操作按钮：底部 action bar 中的次按钮
    func secondaryActionStyle() -> some View {
        self
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}
```

- [ ] **Step 2：重新生成 xcodeproj 并编译**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Utils/ButtonStyles.swift
git commit -m "新增 ButtonStyles：主要/次要操作按钮样式"
```

---

### Task 5：扩展 TrashedItem 加入 sourceModule + 数据迁移

**Files:**
- Modify: `AlbumSlim/Services/TrashService.swift`
- Test: `AlbumSlimTests/TrashServiceMigrationTests.swift`

**背景：** 现有 `TrashedItem` 已实现，但只用于截图（key `trashedScreenshotItems`）。需要：
1. 加入 `TrashSource` 枚举字段
2. 加入 `mediaType` 字段（用于显示标签）
3. 存储 key 升级为 `trashedItems_v2`，启动时一次性把旧 `trashedScreenshotItems` 迁移过来（默认 `sourceModule = .screenshot, mediaType = .screenshot`）

- [ ] **Step 1：先写迁移测试（失败）**

Create `AlbumSlimTests/TrashServiceMigrationTests.swift`:

```swift
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
        // 准备旧格式数据（仅包含 v1 字段）
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

        // 启动 TrashService 触发迁移
        let service = TrashService()

        #expect(service.trashedItems.count == 2)
        #expect(service.trashedItems.allSatisfy { $0.sourceModule == .screenshot })
        #expect(service.trashedItems.allSatisfy { $0.mediaType == .screenshot })
        #expect(UserDefaults.standard.bool(forKey: "trashItemsMigrated_v2"))
        // 旧 key 应被清除
        #expect(UserDefaults.standard.data(forKey: "trashedScreenshotItems") == nil)
    }

    @Test("迁移幂等：第二次启动不重复迁移")
    func migrateIdempotent() throws {
        resetUserDefaults()
        UserDefaults.standard.set(true, forKey: "trashItemsMigrated_v2")
        // 旧 key 仍有数据，但已标记迁移过 → 应忽略
        let dummy = "x".data(using: .utf8)!
        UserDefaults.standard.set(dummy, forKey: "trashedScreenshotItems")

        let service = TrashService()
        #expect(service.trashedItems.isEmpty)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

Run: `xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:AlbumSlimTests/TrashServiceMigrationTests`
Expected: 编译失败（`TrashSource` / `mediaType` 不存在）

- [ ] **Step 3：扩展 TrashedItem 与 TrashService**

替换 `AlbumSlim/Services/TrashService.swift` 全文为：

```swift
import Foundation
import Photos

enum TrashSource: String, Codable, CaseIterable {
    case similar
    case waste
    case burst
    case largePhoto
    case video
    case screenshot
    case shuffle
    case other

    var label: String {
        switch self {
        case .similar:    return "相似照片"
        case .waste:      return "废片"
        case .burst:      return "连拍"
        case .largePhoto: return "超大照片"
        case .video:      return "视频"
        case .screenshot: return "截图"
        case .shuffle:    return "浏览"
        case .other:      return "其他"
        }
    }
}

enum TrashedMediaType: String, Codable {
    case photo
    case video
    case livePhoto
    case screenshot
}

struct TrashedItem: Codable, Identifiable {
    let id: String
    let fileSize: Int64
    let creationDate: Date?
    let trashedDate: Date
    let sourceModule: TrashSource
    let mediaType: TrashedMediaType

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

@MainActor @Observable
final class TrashService {
    private(set) var trashedItems: [TrashedItem] = []

    var totalSize: Int64 {
        trashedItems.reduce(0) { $0 + $1.fileSize }
    }

    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// 当前所有被软删除的 asset localIdentifier 集合，供各模块过滤使用
    var trashedAssetIDs: Set<String> {
        Set(trashedItems.map(\.id))
    }

    private static let storageKeyV2 = "trashedItems_v2"
    private static let legacyKey = "trashedScreenshotItems"
    private static let migrationFlag = "trashItemsMigrated_v2"

    init() {
        migrateLegacyIfNeeded()
        load()
    }

    // MARK: - 软删除

    /// 通用入口：传入 PHAsset 列表 + 来源模块 + 媒体类型
    func moveToTrash(assets: [PHAsset], source: TrashSource, mediaType: TrashedMediaType) {
        let now = Date()
        let existingIDs = trashedAssetIDs
        let newItems: [TrashedItem] = assets.compactMap { asset in
            guard !existingIDs.contains(asset.localIdentifier) else { return nil }
            let bytes = asset.estimatedByteSize
            return TrashedItem(
                id: asset.localIdentifier,
                fileSize: bytes,
                creationDate: asset.creationDate,
                trashedDate: now,
                sourceModule: source,
                mediaType: mediaType
            )
        }
        guard !newItems.isEmpty else { return }
        trashedItems.insert(contentsOf: newItems, at: 0)
        persist()
    }

    /// 兼容老入口：保留给截图 ViewModel 现有调用，内部转发
    @available(*, deprecated, message: "使用 moveToTrash(assets:source:mediaType:)")
    func trash(_ items: [MediaItem]) {
        let now = Date()
        let existingIDs = trashedAssetIDs
        let newItems = items.compactMap { item -> TrashedItem? in
            guard !existingIDs.contains(item.id) else { return nil }
            return TrashedItem(
                id: item.id,
                fileSize: item.fileSize,
                creationDate: item.creationDate,
                trashedDate: now,
                sourceModule: .screenshot,
                mediaType: .screenshot
            )
        }
        guard !newItems.isEmpty else { return }
        trashedItems.insert(contentsOf: newItems, at: 0)
        persist()
    }

    // MARK: - 恢复 / 永久删除

    func restore(_ ids: Set<String>) {
        trashedItems.removeAll { ids.contains($0.id) }
        persist()
    }

    func permanentlyDelete(_ ids: Set<String>, photoLibrary: PhotoLibraryService) async throws {
        let assets = fetchAssets(for: ids)
        if !assets.isEmpty {
            try await photoLibrary.deleteAssets(assets)
        }
        trashedItems.removeAll { ids.contains($0.id) }
        persist()
    }

    func permanentlyDeleteAll(photoLibrary: PhotoLibraryService) async throws {
        let ids = Set(trashedItems.map(\.id))
        try await permanentlyDelete(ids, photoLibrary: photoLibrary)
    }

    // MARK: - 查询

    func contains(_ assetID: String) -> Bool {
        trashedAssetIDs.contains(assetID)
    }

    func fetchAssets(for ids: Set<String>) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // MARK: - 同步

    /// 剔除系统相册中已不存在的条目
    func reconcileWithLibrary() {
        guard !trashedItems.isEmpty else { return }
        let ids = trashedAssetIDs
        let validIDs = Set(fetchAssets(for: ids).map(\.localIdentifier))
        let removed = ids.subtracting(validIDs)
        guard !removed.isEmpty else { return }
        trashedItems.removeAll { removed.contains($0.id) }
        persist()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKeyV2),
              let items = try? JSONDecoder().decode([TrashedItem].self, from: data) else { return }
        trashedItems = items
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(trashedItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKeyV2)
    }

    // MARK: - 旧数据迁移

    private func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationFlag) else { return }
        defer {
            defaults.set(true, forKey: Self.migrationFlag)
            defaults.removeObject(forKey: Self.legacyKey)
        }
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }

        struct LegacyItem: Codable {
            let id: String
            let fileSize: Int64
            let creationDate: Date?
            let trashedDate: Date
        }
        guard let legacy = try? JSONDecoder().decode([LegacyItem].self, from: data), !legacy.isEmpty else { return }

        let migrated = legacy.map { item in
            TrashedItem(
                id: item.id,
                fileSize: item.fileSize,
                creationDate: item.creationDate,
                trashedDate: item.trashedDate,
                sourceModule: .screenshot,
                mediaType: .screenshot
            )
        }
        if let encoded = try? JSONEncoder().encode(migrated) {
            defaults.set(encoded, forKey: Self.storageKeyV2)
        }
    }
}

// MARK: - PHAsset 估算字节数

private extension PHAsset {
    var estimatedByteSize: Int64 {
        let resources = PHAssetResource.assetResources(for: self)
        for r in resources {
            if let n = r.value(forKey: "fileSize") as? NSNumber {
                return n.int64Value
            }
        }
        return 0
    }
}
```

- [ ] **Step 4：运行迁移测试确认通过**

Run: `xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:AlbumSlimTests/TrashServiceMigrationTests`
Expected: 2 tests passed

- [ ] **Step 5：全量编译验证（旧调用兼容）**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED（旧 `services.trash.trash(items)` 仍能编译，会有 deprecated warning）

- [ ] **Step 6：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Services/TrashService.swift AlbumSlimTests/TrashServiceMigrationTests.swift
git commit -m "扩展 TrashService：多模块来源 + 旧数据迁移"
```

---

### Task 6：TrashService 跨模块隐藏 + 去重测试

**Files:**
- Test: `AlbumSlimTests/TrashServiceFilterTests.swift`

**目的：** 验证：①同一 asset 重复加入只记录一次；②`trashedAssetIDs` 可被外部用于过滤；③`restore` 后从 set 移除。

- [ ] **Step 1：写测试**

Create `AlbumSlimTests/TrashServiceFilterTests.swift`:

```swift
import Testing
import Foundation
@testable import AlbumSlim

@Suite("TrashService 去重与过滤")
@MainActor
struct TrashServiceFilterTests {

    private func resetUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "trashedScreenshotItems")
        UserDefaults.standard.removeObject(forKey: "trashedItems_v2")
        UserDefaults.standard.set(true, forKey: "trashItemsMigrated_v2")
    }

    private func makeItem(id: String, source: TrashSource = .other) -> TrashedItem {
        TrashedItem(id: id, fileSize: 100, creationDate: nil, trashedDate: Date(),
                    sourceModule: source, mediaType: .photo)
    }

    @Test("trashedAssetIDs 反映当前所有软删除项 ID")
    func assetIDsReflectsItems() {
        resetUserDefaults()
        let service = TrashService()
        UserDefaults.standard.set(try! JSONEncoder().encode([makeItem(id: "a"), makeItem(id: "b")]),
                                  forKey: "trashedItems_v2")
        let s2 = TrashService()
        #expect(s2.trashedAssetIDs == Set(["a", "b"]))
        #expect(s2.contains("a"))
        #expect(!s2.contains("z"))
    }

    @Test("restore 后从 trashedAssetIDs 移除")
    func restoreRemovesFromIDs() {
        resetUserDefaults()
        UserDefaults.standard.set(try! JSONEncoder().encode([makeItem(id: "a"), makeItem(id: "b")]),
                                  forKey: "trashedItems_v2")
        let service = TrashService()
        service.restore(["a"])
        #expect(service.trashedAssetIDs == Set(["b"]))
    }
}
```

- [ ] **Step 2：运行测试**

Run: `xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -only-testing:AlbumSlimTests/TrashServiceFilterTests`
Expected: 2 tests passed

- [ ] **Step 3：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlimTests/TrashServiceFilterTests.swift
git commit -m "新增 TrashService 去重与过滤测试"
```

---

### Task 7：新增 ToastCenter + AppToast

**Files:**
- Create: `AlbumSlim/Services/ToastCenter.swift`
- Create: `AlbumSlim/Views/Common/AppToast.swift`

- [ ] **Step 1：创建 ToastCenter**

Create `AlbumSlim/Services/ToastCenter.swift`:

```swift
import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
    let tint: Color
}

@MainActor @Observable
final class ToastCenter {
    private(set) var current: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    func show(icon: String, text: String, tint: Color = .primary, duration: TimeInterval = 1.5) {
        dismissTask?.cancel()
        current = ToastMessage(icon: icon, text: text, tint: tint)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    // 高层语义封装
    func movedToTrash(_ count: Int) {
        show(icon: AppIcons.trash, text: AppStrings.movedToTrash(count))
    }

    func restored(_ count: Int) {
        show(icon: AppIcons.restore, text: AppStrings.restored(count), tint: .blue)
    }

    func permanentlyDeleted(_ count: Int, freed: Int64) {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.permanentlyDeleted(count, freed: freed), tint: .green)
    }

    func compressed(_ saved: Int64) {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.compressed(saved), tint: .green)
    }

    func saved() {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.saved, tint: .green)
    }

    func copied() {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.copied, tint: .green)
    }

    func proRequired() {
        show(icon: AppIcons.proCrown, text: AppStrings.proRequired, tint: .orange)
    }
}
```

- [ ] **Step 2：创建 AppToast 视图**

Create `AlbumSlim/Views/Common/AppToast.swift`:

```swift
import SwiftUI

/// 顶层 ZStack 中插入：
/// ```
/// ZStack(alignment: .bottom) {
///     content
///     AppToast(toastCenter: services.toast)
/// }
/// ```
struct AppToast: View {
    let toastCenter: ToastCenter

    var body: some View {
        Group {
            if let toast = toastCenter.current {
                HStack(spacing: 8) {
                    Image(systemName: toast.icon)
                        .foregroundStyle(toast.tint)
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastCenter.current)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3：编译验证**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Services/ToastCenter.swift AlbumSlim/Views/Common/AppToast.swift
git commit -m "新增 ToastCenter 与 AppToast：统一底部反馈"
```

---

### Task 8：新增 LoadingState / EmptyState 共享组件

**Files:**
- Create: `AlbumSlim/Views/Common/LoadingState.swift`
- Create: `AlbumSlim/Views/Common/EmptyState.swift`

- [ ] **Step 1：创建 LoadingState**

Create `AlbumSlim/Views/Common/LoadingState.swift`:

```swift
import SwiftUI

/// 简单加载视图：居中 ProgressView + 文案
struct LoadingState: View {
    let text: String

    init(_ text: String = AppStrings.loading) {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 带进度条加载视图：进度 0-1 + phase 文案
struct ProgressLoadingState: View {
    let phase: String
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
            Text("\(phase) \(Int(progress * 100))%")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
    }
}
```

- [ ] **Step 2：创建 EmptyState**

Create `AlbumSlim/Views/Common/EmptyState.swift`:

```swift
import SwiftUI

/// 统一空状态：标题"没有 X" + 图标 + 可选 description + 可选 actions
struct EmptyState<Actions: View>: View {
    let object: String           // 比如"视频"，会拼成"没有视频"
    let systemImage: String
    let description: String?
    let actions: () -> Actions

    init(
        _ object: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.object = object
        self.systemImage = systemImage
        self.description = description
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label(AppStrings.empty(object), systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            actions()
        }
    }
}
```

- [ ] **Step 3：编译验证**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Views/Common/LoadingState.swift AlbumSlim/Views/Common/EmptyState.swift
git commit -m "新增 LoadingState 与 EmptyState 共享组件"
```

---

### Task 9：新增 ActionBar / SelectionToolbar / TrashToolbarButton / ConfirmDialog

**Files:**
- Create: `AlbumSlim/Views/Common/ActionBar.swift`
- Create: `AlbumSlim/Views/Common/SelectionToolbar.swift`
- Create: `AlbumSlim/Views/Common/TrashToolbarButton.swift`

- [ ] **Step 1：创建 ActionBar**

Create `AlbumSlim/Views/Common/ActionBar.swift`:

```swift
import SwiftUI

/// 底部 action bar 容器：safeAreaInset 用，统一 .ultraThinMaterial 背景
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
```

- [ ] **Step 2：创建 SelectionToolbar**

Create `AlbumSlim/Views/Common/SelectionToolbar.swift`:

```swift
import SwiftUI

/// 标准编辑模式 toolbar：右上"选择/完成" + 编辑模式下左上"全选/取消全选"
/// 在 View 上挂载：`.modifier(SelectionToolbar(isEditing:..., selectedCount:..., totalCount:..., onSelectAll:..., onDeselectAll:...))`
struct SelectionToolbar: ViewModifier {
    @Binding var isEditing: Bool
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? AppStrings.done : AppStrings.select) {
                        Haptics.tap()
                        withAnimation { isEditing.toggle() }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selectedCount == totalCount && totalCount > 0
                               ? AppStrings.deselectAll
                               : AppStrings.selectAll) {
                            Haptics.tap()
                            if selectedCount == totalCount { onDeselectAll() } else { onSelectAll() }
                        }
                        .disabled(totalCount == 0)
                    }
                    ToolbarItem(placement: .principal) {
                        Text(AppStrings.selected(selectedCount))
                            .font(.headline)
                    }
                }
            }
            .navigationBarTitleDisplayMode(isEditing ? .inline : .automatic)
    }
}

extension View {
    func selectionToolbar(
        isEditing: Binding<Bool>,
        selectedCount: Int,
        totalCount: Int,
        onSelectAll: @escaping () -> Void,
        onDeselectAll: @escaping () -> Void
    ) -> some View {
        modifier(SelectionToolbar(
            isEditing: isEditing,
            selectedCount: selectedCount,
            totalCount: totalCount,
            onSelectAll: onSelectAll,
            onDeselectAll: onDeselectAll
        ))
    }
}
```

- [ ] **Step 3：创建 TrashToolbarButton**

Create `AlbumSlim/Views/Common/TrashToolbarButton.swift`:

```swift
import SwiftUI

/// 模块右上 toolbar 的垃圾桶入口按钮（带数字 badge）
/// 用法：`TrashToolbarButton(count: services.trash.trashedItems.count) { showTrash = true }`
struct TrashToolbarButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: AppIcons.trash)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(min(count, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .accessibilityLabel("垃圾桶")
        .accessibilityValue(count > 0 ? "\(count) 项" : "空")
    }
}
```

- [ ] **Step 4：编译验证**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Views/Common/ActionBar.swift AlbumSlim/Views/Common/SelectionToolbar.swift AlbumSlim/Views/Common/TrashToolbarButton.swift
git commit -m "新增 ActionBar / SelectionToolbar / TrashToolbarButton 共享组件"
```

---

### Task 10：新建 GlobalTrashView 取代旧 TrashView

**Files:**
- Create: `AlbumSlim/Views/Trash/GlobalTrashView.swift`

**注意：** 旧 `Views/Screenshot/TrashView.swift` 暂时保留，等 Wave 3 Task 21 才删除（避免编译破坏）。

- [ ] **Step 1：创建 GlobalTrashView**

Create `AlbumSlim/Views/Trash/GlobalTrashView.swift`:

```swift
import SwiftUI
import Photos

struct GlobalTrashView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var selectedIDs: Set<String> = []
    @State private var showPermanentDeleteConfirm = false
    @State private var showEmptyAllConfirm = false

    private var items: [TrashedItem] { services.trash.trashedItems }
    private var selectedItems: [TrashedItem] {
        items.filter { selectedIDs.contains($0.id) }
    }
    private var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("垃圾桶")
                .toolbar {
                    if !items.isEmpty && !isEditing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button(AppStrings.emptyTrash, role: .destructive) {
                                    showEmptyAllConfirm = true
                                }
                            } label: {
                                Image(systemName: AppIcons.more)
                            }
                        }
                    }
                }
                .selectionToolbar(
                    isEditing: $isEditing,
                    selectedCount: selectedIDs.count,
                    totalCount: items.count,
                    onSelectAll: { selectedIDs = Set(items.map(\.id)) },
                    onDeselectAll: { selectedIDs.removeAll() }
                )
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !selectedIDs.isEmpty {
                        ActionBar {
                            Button {
                                Haptics.tap()
                                services.trash.restore(selectedIDs)
                                services.toast.restored(selectedIDs.count)
                                selectedIDs.removeAll()
                            } label: {
                                Text("\(AppStrings.restore) \(AppStrings.items(selectedIDs.count))")
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryActionStyle()

                            Button(role: .destructive) {
                                showPermanentDeleteConfirm = true
                            } label: {
                                Text("\(AppStrings.permanentlyDelete) \(AppStrings.items(selectedIDs.count))")
                                    .frame(maxWidth: .infinity)
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
                .confirmationDialog(
                    AppStrings.confirmPermanentDeleteTitle(selectedIDs.count),
                    isPresented: $showPermanentDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button(AppStrings.permanentlyDelete, role: .destructive) {
                        let toDelete = selectedIDs
                        let freed = selectedSize
                        Task {
                            try? await services.trash.permanentlyDelete(toDelete, photoLibrary: services.photoLibrary)
                            await MainActor.run {
                                Haptics.permanentDelete()
                                services.toast.permanentlyDeleted(toDelete.count, freed: freed)
                                selectedIDs.removeAll()
                                if items.isEmpty { isEditing = false }
                            }
                        }
                    }
                } message: {
                    Text(AppStrings.confirmPermanentDeleteMessage)
                }
                .confirmationDialog(
                    AppStrings.confirmPermanentDeleteTitle(items.count),
                    isPresented: $showEmptyAllConfirm,
                    titleVisibility: .visible
                ) {
                    Button(AppStrings.emptyTrash, role: .destructive) {
                        let totalCount = items.count
                        let freed = services.trash.totalSize
                        Task {
                            try? await services.trash.permanentlyDeleteAll(photoLibrary: services.photoLibrary)
                            await MainActor.run {
                                Haptics.permanentDelete()
                                services.toast.permanentlyDeleted(totalCount, freed: freed)
                            }
                        }
                    }
                } message: {
                    Text(AppStrings.confirmEmptyTrashMessage)
                }
                .task { services.trash.reconcileWithLibrary() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            EmptyState("项目", systemImage: AppIcons.trash, description: "垃圾桶里没有内容")
        } else {
            List {
                Section {
                    Text("\(items.count) 项 · \(services.trash.totalSizeText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(items) { item in
                        TrashRow(
                            item: item,
                            isEditing: isEditing,
                            isSelected: selectedIDs.contains(item.id),
                            onToggle: {
                                Haptics.toggleSelect()
                                if selectedIDs.contains(item.id) {
                                    selectedIDs.remove(item.id)
                                } else {
                                    selectedIDs.insert(item.id)
                                }
                            }
                        )
                        .contextMenu {
                            Button(AppStrings.restore, systemImage: AppIcons.restore) {
                                services.trash.restore([item.id])
                                services.toast.restored(1)
                            }
                            Button(AppStrings.permanentlyDelete, systemImage: AppIcons.trashFill, role: .destructive) {
                                Task {
                                    try? await services.trash.permanentlyDelete([item.id], photoLibrary: services.photoLibrary)
                                    Haptics.permanentDelete()
                                    services.toast.permanentlyDeleted(1, freed: item.fileSize)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TrashRow: View {
    let item: TrashedItem
    let isEditing: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                Image(systemName: isSelected ? AppIcons.checkmarkCircleFill : AppIcons.circle)
                    .foregroundStyle(isSelected ? .accentColor : .secondary)
                    .font(.title3)
                    .onTapGesture(perform: onToggle)
            }
            // 缩略图占位（后续可替换为异步加载 PHAsset 缩略图）
            ThumbnailView(localIdentifier: item.id, mediaType: item.mediaType)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceModule.label)
                    .font(.subheadline.weight(.medium))
                Text(item.fileSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = item.creationDate {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing { onToggle() }
        }
    }
}

private struct ThumbnailView: View {
    let localIdentifier: String
    let mediaType: TrashedMediaType

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: mediaType == .video ? AppIcons.video : AppIcons.screenshot)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        let target = CGSize(width: 168, height: 168)
        manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { img, _ in
            Task { @MainActor in self.image = img }
        }
    }
}
```

- [ ] **Step 2：编译验证**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/Views/Trash/GlobalTrashView.swift
git commit -m "新增 GlobalTrashView：跨模块全局垃圾桶"
```

---

### Task 11：AppServiceContainer 注册 ToastCenter

**Files:**
- Modify: `AlbumSlim/App/AppServiceContainer.swift`

- [ ] **Step 1：在 AppServiceContainer 中注册**

修改 `AlbumSlim/App/AppServiceContainer.swift`：

`var backdrop: BackdropAdapterService` 行下面新增：

```swift
    let toast: ToastCenter
```

`init()` 内 `self.backdrop = BackdropAdapterService()` 后添加：

```swift
        self.toast = ToastCenter()
```

- [ ] **Step 2：在根 View 挂载 AppToast**

找到 `AlbumSlim/App/` 下的根 App 文件（应该是 `AlbumSlimApp.swift` 或 `MainTabView.swift` 中的 ContentView 等）。在最外层 `ZStack(alignment: .bottom)` 包裹原内容并加入 AppToast：

举例（假设 root 是 `MainTabView`，在 body 最外层）：

```swift
        ZStack(alignment: .bottom) {
            // ... 原 TabView 内容 ...

            AppToast(toastCenter: services.toast)
        }
```

如果 root 是 `AlbumSlimApp` 中的 WindowGroup，在 `ContentView` 或 root View 的 body 外层包 ZStack。

- [ ] **Step 3：编译验证**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4：commit**

```bash
git add AlbumSlim.xcodeproj AlbumSlim/App/AppServiceContainer.swift AlbumSlim/Views/MainTabView.swift
git commit -m "AppServiceContainer 注册 ToastCenter，根视图挂载 AppToast"
```

---

## Wave 2：模块接入（Task 12-20）

> **并行/串行依赖**：
> - **Task 12-14（Shuffle / 视频）和 Task 19（截图）** 可并行 — 文件互不重叠
> - **Task 15-18（4 个照片子模块）共享 `PhotoCleanerViewModel.swift`**：必须 **Task 15 先做**（它会给 `deleteSelected` 加 `source: TrashSource` 参数），完成 commit 后 Task 16/17/18 才能并行启动（因为它们只是各自 View 文件传入不同 `source` 调用）
> - **Task 20** 涉及跨模块过滤，必须等 Task 12-19 全部完成后做

### Task 12：Shuffle 首页接入软删除 + Toast + Haptic 统一

**Files:**
- Modify: `AlbumSlim/Views/Shuffle/ShuffleFeedView.swift`

- [ ] **Step 1：替换删除调用为 TrashService**

定位 `ShuffleFeedView.swift:228` 附近的删除逻辑（confirmationDialog 触发的 Task 块），原代码大致为：

```swift
try await services.photoLibrary.deleteAssets([target.asset])
```

替换为：

```swift
services.trash.moveToTrash(assets: [target.asset], source: .shuffle, mediaType: trashMediaType(for: target))
await MainActor.run {
    Haptics.moveToTrash()
    services.toast.movedToTrash(1)
}
```

并在文件末尾添加辅助函数（或就近放在 struct 内私有方法）：

```swift
private func trashMediaType(for item: ShuffleItem) -> TrashedMediaType {
    switch item.asset.mediaType {
    case .video: return .video
    case .image:
        return item.asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
    default: return .photo
    }
}
```

> 如果 `ShuffleItem` 类型/属性不同，请按实际命名调整。

- [ ] **Step 2：替换 confirmationDialog 文案与按钮**

找到 Shuffle 删除的 confirmationDialog（约 `:65-74`）：

```swift
.confirmationDialog("删除这个项目？", isPresented: $showDeleteConfirm) {
    Button("移到「最近删除」", role: .destructive) {
        // ... old code ...
    }
}
```

改为不再弹确认（直接软删除）。删除整个 `confirmationDialog` 修饰符块，把删除逻辑直接放到触发点（删除按钮的 action 中）。

- [ ] **Step 3：替换原有 Pro 门槛 Haptic**

定位 Shuffle 中触发 paywall 处的 `UINotificationFeedbackGenerator().notificationOccurred(.warning)`（约 `:212-216`），改为：

```swift
Haptics.proGate()
```

- [ ] **Step 4：替换原有删除 Haptic**

定位 Shuffle 中删除处现有的 `UIImpactFeedbackGenerator(style: .medium).impactOccurred()`，改为已经在 Step 1 加好的 `Haptics.moveToTrash()`，确认无其他重复 haptic 调用。

- [ ] **Step 5：编译验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6：commit**

```bash
git add AlbumSlim/Views/Shuffle/ShuffleFeedView.swift
git commit -m "Shuffle：删除改为软删除，统一 Toast/Haptic"
```

---

### Task 13：VideoListView 接入新规范

**Files:**
- Modify: `AlbumSlim/Views/Video/VideoListView.swift`
- Modify: `AlbumSlim/ViewModels/VideoManagerViewModel.swift`

- [ ] **Step 1：VideoManagerViewModel 删除改软删除**

定位 `VideoManagerViewModel.swift:144` 附近 `deleteAssets(assets)` 调用：

```swift
try await services.photoLibrary.deleteAssets(assets)
```

替换为：

```swift
let phAssets = items.compactMap(\.phAsset) // 按实际属性名调整
services.trash.moveToTrash(assets: phAssets, source: .video, mediaType: .video)
```

并把 `services.photoLibrary.deleteAssets([asset])`（`:122` 处的单删除）也类似改造。

> 移除原方法签名上的 `throws`/`async` 如果不再需要。如果 ViewModel 方法被外部 await，保留 async/throws 形式但用不到 try。

- [ ] **Step 2：VideoListView 接入 SelectionToolbar**

替换原 `.toolbar { ToolbarItem... "选择" / "完成" ...}` 块为：

```swift
.selectionToolbar(
    isEditing: $isEditing,
    selectedCount: viewModel.selectedIDs.count,
    totalCount: viewModel.items.count,
    onSelectAll: { viewModel.selectedIDs = Set(viewModel.items.map(\.id)) },
    onDeselectAll: { viewModel.selectedIDs.removeAll() }
)
```

> 按实际 ViewModel 属性名调整 `selectedIDs` / `items`。

- [ ] **Step 3：VideoListView 顶部 toolbar 加垃圾桶入口**

在原 toolbar block 内（编辑按钮之外）新增：

```swift
ToolbarItem(placement: .topBarTrailing) {
    TrashToolbarButton(count: services.trash.trashedItems.count) {
        showTrash = true
    }
}
```

并在 View 顶部加 `@State private var showTrash = false`，body 末尾追加：

```swift
.sheet(isPresented: $showTrash) { GlobalTrashView() }
```

- [ ] **Step 4：底部 ActionBar 替换 + 文案统一**

替换 `safeAreaInset(edge: .bottom)` 中的 HStack 内容：

```swift
.safeAreaInset(edge: .bottom) {
    if isEditing && !viewModel.selectedIDs.isEmpty {
        ActionBar {
            Button {
                Haptics.tap()
                viewModel.startBatchCompress()
            } label: {
                Text("\(AppStrings.compressing.dropLast()) \(AppStrings.items(viewModel.selectedIDs.count))")
                    .frame(maxWidth: .infinity)
            }
            .secondaryActionStyle()

            Button(role: .destructive) {
                Task {
                    await viewModel.deleteSelected(services: services)
                    Haptics.moveToTrash()
                    services.toast.movedToTrash(viewModel.selectedIDs.count)
                    viewModel.selectedIDs.removeAll()
                    isEditing = false
                }
            } label: {
                Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedIDs.count))")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle(destructive: true)
        }
    }
}
```

> 注：`compressing.dropLast()` 是去掉省略号变成"压缩"，按需求改成显式常量更清晰，建议在 AppStrings 中加 `static let compress = "压缩"` 后改为 `AppStrings.compress`。如果新增，参考 Task 2 的格式。

- [ ] **Step 5：删除原 confirmationDialog**

移除原 `.confirmationDialog("确定删除 X 个视频？" ...)` 整块，软删除不再确认。

- [ ] **Step 6：空状态/加载替换为统一组件**

将原 `ProgressView()` 与 `ContentUnavailableView` 替换：

```swift
// 加载
LoadingState(AppStrings.loading)

// 空状态
EmptyState("视频", systemImage: AppIcons.video)
```

- [ ] **Step 7：编译验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 8：commit**

```bash
git add AlbumSlim/Views/Video/VideoListView.swift AlbumSlim/ViewModels/VideoManagerViewModel.swift
git commit -m "视频列表：接入软删除 + 编辑模式统一 + 垃圾桶入口"
```

---

### Task 14：VideoSuggestionsView + VideoCompressView 接入

**Files:**
- Modify: `AlbumSlim/Views/Video/VideoSuggestionsView.swift`
- Modify: `AlbumSlim/Views/Video/VideoCompressView.swift`

- [ ] **Step 1：VideoSuggestionsView 替换删除**

定位 `VideoSuggestionsView.swift:174` 的 `deleteAssets(assets)`，改为：

```swift
services.trash.moveToTrash(assets: assets, source: .video, mediaType: .video)
Haptics.moveToTrash()
services.toast.movedToTrash(assets.count)
```

移除外层 `try? await`，原方法可不再 throws/async。

移除对应的 confirmationDialog（约 `:62-69`）。

- [ ] **Step 2：VideoSuggestionsView 替换底部按钮、空状态、文案**

参考 Task 13 Step 4 + Step 6 的写法，把"批量压缩 / 删除"按钮改为 ActionBar + 主次按钮样式，"已选 X 个" 改 `AppStrings.selected(...)`，空状态 `EmptyState("清理建议", systemImage: AppIcons.checkmarkCircle, description: "暂无可清理的视频")`。

- [ ] **Step 3：VideoCompressView 替换删除**

定位 `:172` 的 `deleteAssets([item.asset])`：

```swift
services.trash.moveToTrash(assets: [item.asset], source: .video, mediaType: .video)
Haptics.moveToTrash()
services.toast.movedToTrash(1)
```

移除原 confirmationDialog（约 `:169-178`）。

- [ ] **Step 4：VideoCompressView 进度展示替换**

将原 `ProgressView(value: progress)` + 百分比文本块（`:103-108`）替换为：

```swift
ProgressLoadingState(phase: AppStrings.compressing, progress: viewModel.progress)
```

压缩成功完成后调用：

```swift
Haptics.operationSuccess()
services.toast.compressed(savedBytes)
```

- [ ] **Step 5：按钮样式统一**

替换 "压缩并替换 / 压缩保存为新" 按钮为 `.primaryActionStyle()` / `.secondaryActionStyle()`（不带 destructive）。

- [ ] **Step 6：编译验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7：commit**

```bash
git add AlbumSlim/Views/Video/VideoSuggestionsView.swift AlbumSlim/Views/Video/VideoCompressView.swift
git commit -m "视频建议/压缩：接入软删除 + 统一按钮/进度/Toast"
```

---

### Task 15：SimilarPhotosView 改造（编辑模式 + 移除 Pro overlay）

**Files:**
- Modify: `AlbumSlim/Views/Photo/SimilarPhotosView.swift`
- Modify: `AlbumSlim/ViewModels/PhotoCleanerViewModel.swift`

- [ ] **Step 1：PhotoCleanerViewModel 删除改软删除**

定位 `PhotoCleanerViewModel.swift:68` 的 `deleteAssets(assets)`：

```swift
services.trash.moveToTrash(assets: assets, source: .similar, mediaType: .photo)
```

如方法被多个分类（相似/废片/连拍/超大）共用，需要按调用上下文传入 `source`。如果只能传一个，给方法加参数 `source: TrashSource`：

```swift
func deleteSelected(services: AppServiceContainer, source: TrashSource) async {
    let phAssets = /* 收集选中的 PHAsset */
    services.trash.moveToTrash(assets: phAssets, source: source, mediaType: .photo)
}
```

调用方相应传入 `.similar` / `.waste` / `.burst` / `.largePhoto`。

- [ ] **Step 2：SimilarPhotosView 改造为编辑模式**

把原"List section header 常驻全选按钮"模式改为统一 SelectionToolbar：

1. 删除原 List section 内的 "选中除最佳外全部" 按钮（保留为编辑模式下的特殊"智能选择"操作或暂时移除）
2. 加 `@State private var isEditing = false`
3. 列表行的勾选圈仅在 `isEditing == true` 时显示
4. 应用 `.selectionToolbar(...)` modifier
5. 底部 ActionBar 在 `isEditing && !selectedIDs.isEmpty` 时显示，仅一个主按钮"移到垃圾桶 X 项"（destructive）

- [ ] **Step 3：移除 Pro overlay，改用 paywall sheet**

删除 `:98-112` 处的"升级 Pro 查看更多相似组" overlay。改为：操作触发时检查 `services.subscription.isPro`，false 则：

```swift
Haptics.proGate()
showPaywall = true
```

并在 body 末尾加 `.sheet(isPresented: $showPaywall) { PaywallView() }`。

- [ ] **Step 4：加 trash toolbar 入口 + GlobalTrashView sheet**

参考 Task 13 Step 3。

- [ ] **Step 5：替换空状态/加载/进度为统一组件**

```swift
// 加载（带进度）
ProgressLoadingState(phase: AppStrings.scanning, progress: viewModel.scanProgress)

// 空状态
EmptyState("相似照片", systemImage: AppIcons.similar, description: "Tap 开始扫描发现可清理项") {
    Button("开始扫描") { Task { await viewModel.scan(services: services) } }
        .primaryActionStyle()
}
```

- [ ] **Step 6：删除原 confirmationDialog**

移除 `:131-136` 的 `.confirmationDialog("确认删除", ...)` 整块。

- [ ] **Step 7：编译验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 8：commit**

```bash
git add AlbumSlim/Views/Photo/SimilarPhotosView.swift AlbumSlim/ViewModels/PhotoCleanerViewModel.swift
git commit -m "相似照片：编辑模式统一 + 软删除 + 移除 Pro overlay"
```

---

### Task 16：WastePhotosView 改造

**Files:**
- Modify: `AlbumSlim/Views/Photo/WastePhotosView.swift`

参考 Task 15 的步骤模板，针对废片模块做相同改造：

- [ ] **Step 1：删除调用改软删除**

把原模块内调用 `viewModel.deleteSelected(services:)` 的地方改为传入 `source: .waste`。
若直接调用 `services.photoLibrary.deleteAssets`，替换为 `services.trash.moveToTrash(assets:..., source: .waste, mediaType: .photo)`。

- [ ] **Step 2：编辑模式改造**

加 `@State isEditing = false`，应用 `.selectionToolbar(...)`，移除 List section 里的"全选/全不选"按钮，行内勾选圈仅编辑模式显示。

- [ ] **Step 3：底部 ActionBar 替换**

```swift
.safeAreaInset(edge: .bottom) {
    if isEditing && !viewModel.selectedIDs.isEmpty {
        ActionBar {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteSelected(services: services, source: .waste)
                    Haptics.moveToTrash()
                    services.toast.movedToTrash(viewModel.selectedIDs.count)
                    viewModel.selectedIDs.removeAll()
                    isEditing = false
                }
            } label: {
                Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedIDs.count))")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle(destructive: true)
        }
    }
}
```

- [ ] **Step 4：trash toolbar 入口 + sheet**

加 `@State private var showTrash = false`，toolbar 中追加：

```swift
ToolbarItem(placement: .topBarTrailing) {
    TrashToolbarButton(count: services.trash.trashedItems.count) {
        showTrash = true
    }
}
```

body 末尾追加：

```swift
.sheet(isPresented: $showTrash) { GlobalTrashView() }
```

- [ ] **Step 5：空状态/加载替换**

```swift
ProgressLoadingState(phase: AppStrings.scanning, progress: viewModel.scanProgress)
EmptyState("废片", systemImage: AppIcons.waste) {
    Button("开始扫描") { Task { await viewModel.scan(services: services) } }
        .primaryActionStyle()
}
```

- [ ] **Step 6：删除原 confirmationDialog**

移除 `:104-109` 处的 `.confirmationDialog("确认删除", ...)`。

- [ ] **Step 7：编译验证 + commit**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
git add AlbumSlim/Views/Photo/WastePhotosView.swift
git commit -m "废片：编辑模式统一 + 软删除"
```

---

### Task 17：BurstPhotosView 改造

**Files:**
- Modify: `AlbumSlim/Views/Photo/BurstPhotosView.swift`

- [ ] **Step 1：删除调用改软删除**

定位 `:125` 的 `try? await services.photoLibrary.deleteAssets(assets)`：

```swift
services.trash.moveToTrash(assets: assets, source: .burst, mediaType: .photo)
Haptics.moveToTrash()
services.toast.movedToTrash(assets.count)
```

- [ ] **Step 2：行内"只保留最佳"按钮改为 ActionBar 触发**

原文件中 `:42-49` 的 Section 内行按钮"只保留最佳"是分组级操作。保留分组级按钮，但样式改为：

```swift
Button {
    // existing logic
} label: {
    Label("只保留最佳", systemImage: AppIcons.checkmarkCircle)
}
.foregroundStyle(.red) // 维持现有 destructive 视觉
```

确保它内部使用新的 `services.trash.moveToTrash(...)` 调用。

- [ ] **Step 3：（可选）增加全模块编辑模式**

如果要支持跨分组多选，加 `isEditing` 状态 + ActionBar。如果只保留分组级"只保留最佳"，跳过此步并在 commit message 里说明。**默认跳过**——保持当前分组级交互。

- [ ] **Step 4：trash toolbar 入口 + sheet**

加 `@State private var showTrash = false`，toolbar 中追加：

```swift
ToolbarItem(placement: .topBarTrailing) {
    TrashToolbarButton(count: services.trash.trashedItems.count) {
        showTrash = true
    }
}
```

body 末尾追加：

```swift
.sheet(isPresented: $showTrash) { GlobalTrashView() }
```

- [ ] **Step 5：删除原 confirmationDialog**

移除 `:64-71` 处的 `.confirmationDialog("确认删除", ...)`。

- [ ] **Step 6：空状态/加载替换**

```swift
LoadingState(AppStrings.scanning)
EmptyState("连拍照片", systemImage: AppIcons.burst)
```

- [ ] **Step 7：编译验证 + commit**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
git add AlbumSlim/Views/Photo/BurstPhotosView.swift
git commit -m "连拍：接入软删除 + 统一空状态/Toast"
```

---

### Task 18：LargePhotosView 改造

**Files:**
- Modify: `AlbumSlim/Views/Photo/LargePhotosView.swift`

- [ ] **Step 1：删除调用改软删除**

定位 `:196` 的 `deleteAssets(assets)`：

```swift
services.trash.moveToTrash(assets: assets, source: .largePhoto, mediaType: .photo)
Haptics.moveToTrash()
services.toast.movedToTrash(assets.count)
```

- [ ] **Step 2：编辑模式改造**

参考 Task 15 Step 2 / Task 16 Step 2 的模板，给 LargePhotosView 加 `isEditing` + SelectionToolbar，移除 List section 里常驻的"全选 / 取消全选"按钮。

- [ ] **Step 3：底部按钮替换**

将原 `safeAreaInset(bottom)` 中的"删除 X 张 · 释放 Y MB"按钮（`:80-92`）替换为：

```swift
ActionBar {
    Button(role: .destructive) {
        Task {
            // ... 原删除逻辑（已改为软删除调用）
            Haptics.moveToTrash()
            services.toast.movedToTrash(selectedCount)
            viewModel.selectedIDs.removeAll()
            isEditing = false
        }
    } label: {
        Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedIDs.count)) · \(AppStrings.releasable(savableBytes))")
            .frame(maxWidth: .infinity)
    }
    .primaryActionStyle(destructive: true)
}
```

- [ ] **Step 4：trash toolbar 入口 + sheet**

加 `@State private var showTrash = false`，toolbar 中追加：

```swift
ToolbarItem(placement: .topBarTrailing) {
    TrashToolbarButton(count: services.trash.trashedItems.count) {
        showTrash = true
    }
}
```

body 末尾追加：

```swift
.sheet(isPresented: $showTrash) { GlobalTrashView() }
```

- [ ] **Step 5：删除原 confirmationDialog**

移除 `:96-100` 处。

- [ ] **Step 6：空状态/加载替换**

```swift
LoadingState(AppStrings.scanning)
EmptyState("超大照片", systemImage: AppIcons.largePhoto) {
    // 保留原来的 threshold picker + 扫描按钮组合（功能特殊）
    // ...
}
```

- [ ] **Step 7：编译验证 + commit**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
git add AlbumSlim/Views/Photo/LargePhotosView.swift
git commit -m "超大照片：编辑模式统一 + 软删除"
```

---

### Task 19：截图模块统一（ScreenshotListView + ScreenshotDetailView + ScreenshotViewModel）

**Files:**
- Modify: `AlbumSlim/ViewModels/ScreenshotViewModel.swift`
- Modify: `AlbumSlim/Views/Screenshot/ScreenshotListView.swift`
- Modify: `AlbumSlim/Views/Screenshot/ScreenshotDetailView.swift`

- [ ] **Step 1：ScreenshotViewModel 调用迁移到新 API**

定位 `:108` 与 `:117` 处的 `services.trash.trash(items)` / `services.trash.trash([item])`：

```swift
// 原:
services.trash.trash(items)

// 改为:
let assets = services.photoLibrary.fetchAssets(for: items.map(\.id))  // 或按 ViewModel 已有方式
services.trash.moveToTrash(assets: assets, source: .screenshot, mediaType: .screenshot)
```

> 如果 ViewModel 持有的是 `MediaItem`，先抽 `assetLocalIdentifier` 列表，再用 `services.photoLibrary` 或 `PHAsset.fetchAssets(withLocalIdentifiers:options:)` 取 PHAsset。如果原 `services.trash.trash(items)` 用法很方便，可以选择保留 deprecated 调用，让 build 通过 warning，待 Wave 3 收尾时清理。

`:52` 处 `let trashedIDs = Set(services.trash.trashedItems.map(\.id))` 改为 `let trashedIDs = services.trash.trashedAssetIDs`。

- [ ] **Step 2：ScreenshotListView 编辑模式 toolbar 统一**

替换原 `:173-184` "编辑/完成 + 全选" toolbar 为：

```swift
.selectionToolbar(
    isEditing: $isEditing,
    selectedCount: viewModel.selectedIDs.count,
    totalCount: viewModel.items.count,
    onSelectAll: { viewModel.selectedIDs = Set(viewModel.items.map(\.id)) },
    onDeselectAll: { viewModel.selectedIDs.removeAll() }
)
```

- [ ] **Step 3：ScreenshotListView 底部按钮替换**

替换 `:237-264` 处底部按钮为：

```swift
.safeAreaInset(edge: .bottom) {
    if isEditing && !viewModel.selectedIDs.isEmpty {
        ActionBar {
            Button(role: .destructive) {
                Task {
                    await viewModel.moveSelectedToTrash(services: services)
                    Haptics.moveToTrash()
                    services.toast.movedToTrash(viewModel.selectedIDs.count)
                    viewModel.selectedIDs.removeAll()
                    isEditing = false
                }
            } label: {
                Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedIDs.count))")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle(destructive: true)
        }
    }
}
```

- [ ] **Step 4：替换原"垃圾桶"NavigationLink 为 sheet 打开 GlobalTrashView**

定位 `:211` 附近 `Label("垃圾桶...", systemImage: "trash")`，把外层 `NavigationLink` 改为按钮：

```swift
ToolbarItem(placement: .topBarTrailing) {
    TrashToolbarButton(count: services.trash.trashedItems.count) {
        showTrash = true
    }
}
```

`@State private var showTrash = false`，body 末尾追加 `.sheet(isPresented: $showTrash) { GlobalTrashView() }`。

- [ ] **Step 5：替换 navigationTitle 模式动态切换为 SelectionToolbar 自带**

删除 `:45-49` 处 navigationBarTitleDisplayMode 的 if/else，因为 `SelectionToolbar` modifier 已统一处理。保留原 `.navigationTitle(...)`。

- [ ] **Step 6：替换空状态、加载、识别进度**

```swift
LoadingState(AppStrings.loading)            // 原"加载截图..."
EmptyState("截图", systemImage: AppIcons.screenshot)    // 原"没有截图"
ProgressLoadingState(phase: AppStrings.recognizing, progress: viewModel.ocrProgress)  // 原"识别中 X%"
```

- [ ] **Step 7：ScreenshotDetailView 删除按钮 + Toast 迁移**

定位 `:159-162` 处的 `confirmationDialog("移入垃圾桶？...")`：删除整块；删除按钮直接软删除：

```swift
services.trash.moveToTrash(assets: [asset], source: .screenshot, mediaType: .screenshot)
Haptics.moveToTrash()
services.toast.movedToTrash(1)
dismiss()  // 详情页关闭
```

定位 `:104-124` 处自定义 toast 块（"已保存"），删除整段，改为：

```swift
services.toast.saved()
```

定位 `:344` 处"识别失败，请重试"，改为：

```swift
services.toast.show(icon: "exclamationmark.triangle.fill", text: "识别失败，请重试", tint: .orange)
```

- [ ] **Step 8：编译验证 + commit**

```bash
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
git add AlbumSlim/ViewModels/ScreenshotViewModel.swift AlbumSlim/Views/Screenshot/ScreenshotListView.swift AlbumSlim/Views/Screenshot/ScreenshotDetailView.swift
git commit -m "截图：迁移到统一软删除 API + Toast/编辑模式统一"
```

---

### Task 20：跨模块过滤规则集成

**Files:**
- Modify: `AlbumSlim/ViewModels/PhotoCleanerViewModel.swift`
- Modify: `AlbumSlim/ViewModels/VideoManagerViewModel.swift`
- Modify: `AlbumSlim/ViewModels/ShuffleFeedViewModel.swift`
- Modify: `AlbumSlim/ViewModels/QuickCleanViewModel.swift`
- Modify: `AlbumSlim/ViewModels/DashboardViewModel.swift`

**目的：** 任何照片/视频列表的数据加载完成后，必须用 `services.trash.trashedAssetIDs` 过滤。否则"删除后还能在其他模块看到"。

- [ ] **Step 1：PhotoCleanerViewModel 加过滤**

找到所有"列表加载完成、产出 items"的方法（如 `loadSimilarGroups`、`loadWaste`、`loadBurst`、`loadLargePhotos`），在赋值前过滤：

```swift
let trashedIDs = services.trash.trashedAssetIDs
let filtered = result.filter { !trashedIDs.contains($0.id) }
self.items = filtered  // 或对应属性
```

> 对于"分组"类（CleanupGroup），需在分组内过滤 items；如果分组过滤后空，整组移除。

- [ ] **Step 2：VideoManagerViewModel 加过滤**

类似 Step 1。

- [ ] **Step 3：ShuffleFeedViewModel 加过滤**

`ShuffleIndexQueue` 喂入候选 asset 列表前先过滤掉 `services.trash.trashedAssetIDs`。

- [ ] **Step 4：QuickCleanViewModel + DashboardViewModel 加过滤**

QuickClean 聚合数据时过滤；Dashboard 计算容量时减去 `services.trash.totalSize`（即把垃圾桶里的算入"可释放"统计而不算"已占用"，按现有 Dashboard 设计调整）。

- [ ] **Step 5：监听 trashedItems 变化触发刷新**

各 View 中加 `.onChange(of: services.trash.trashedItems.count) { _, _ in Task { await viewModel.reload(services: services) } }` 或类似刷新逻辑（Shuffle 已有先例可参考 `ScreenshotListView.swift:74`）。

- [ ] **Step 6：编译 + 模拟器手工验证**

Run: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

手工验证（模拟器）：
- 在"相似照片"中把一张照片移到垃圾桶 → 切到"废片"模块，该照片不应再出现
- 在垃圾桶恢复 → 两个模块都重新出现
- Shuffle 中删除 → 不再出现在浏览流

- [ ] **Step 7：commit**

```bash
git add AlbumSlim/ViewModels/
git commit -m "跨模块过滤：所有列表过滤掉垃圾桶项，监听变化自动刷新"
```

---

## Wave 3：收尾（必须串行）

### Task 21：废弃旧 Screenshot/TrashView，更新 Tab/Category 图标常量

**Files:**
- Delete: `AlbumSlim/Views/Screenshot/TrashView.swift`
- Modify: `AlbumSlim/Views/MainTabView.swift`
- Modify: `AlbumSlim/Views/Screenshot/ScreenshotListView.swift`（清理对旧 TrashView 的 import/引用）

- [ ] **Step 1：确认旧 TrashView 已无引用**

Run: `grep -rn "TrashView\b" AlbumSlim/ --include="*.swift"`
Expected: 仅 `Views/Screenshot/TrashView.swift` 自身定义；任何其他文件应该已经在 Task 19 中改为 `GlobalTrashView`。

如有残留引用，先逐个改为 `GlobalTrashView`。

- [ ] **Step 2：删除旧文件**

```bash
rm AlbumSlim/Views/Screenshot/TrashView.swift
```

- [ ] **Step 3：MainTabView 更新 Tab 图标和 PhotoCleanerCategory 图标**

替换 `Views/MainTabView.swift` 中的 Tab 图标硬编码，全部用 `AppIcons`：

```swift
TabView(selection: $selectedTab) {
    ShuffleFeedView()
        .tabItem { Label("浏览", systemImage: "shuffle") }
        .tag(0)
    VideoListView()
        .tabItem { Label("视频", systemImage: AppIcons.video) }
        .tag(1)
    PhotoCleanerTabView()
        .tabItem { Label("照片", systemImage: "photo.on.rectangle.angled") }
        .tag(2)
    ScreenshotListView()
        .tabItem { Label("截图", systemImage: AppIcons.screenshot) }   // 原 "scissors" → camera.viewfinder
        .tag(3)
    SettingsView()
        .tabItem { Label("设置", systemImage: AppIcons.settings) }
        .tag(4)
}
```

更新 `PhotoCleanerCategory.icon`：

```swift
var icon: String {
    switch self {
    case .similar: AppIcons.similar       // 原 "rectangle.stack.fill"
    case .waste:   AppIcons.waste         // 原 "trash"
    case .burst:   AppIcons.burst
    case .large:   AppIcons.largePhoto
    }
}
```

- [ ] **Step 4：xcodegen + 编译**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5：commit**

```bash
git add -A
git commit -m "废弃旧 Screenshot/TrashView，统一 Tab 与分类图标常量"
```

---

### Task 22：设置 Tab + 快速扫描 + 概览统一

**Files:**
- Modify: `AlbumSlim/Views/Settings/SettingsView.swift`
- Modify: `AlbumSlim/Views/Settings/OverviewSection.swift`
- Modify: `AlbumSlim/Views/QuickCleanView.swift`
- Modify: `AlbumSlim/Views/SavedNotesView.swift`（如果存在）
- Modify: `AlbumSlim/Views/SavedNoteDetailView.swift`（如果存在）

- [ ] **Step 1：SettingsView 加垃圾桶入口条目**

在 SettingsView 的 Form 中合适位置（建议在"统计"上方或"通用"内）插入：

```swift
Section {
    Button {
        showTrash = true
    } label: {
        HStack {
            Image(systemName: AppIcons.trash)
                .foregroundStyle(.red)
            Text("垃圾桶")
            Spacer()
            if !services.trash.trashedItems.isEmpty {
                Text(AppStrings.items(services.trash.trashedItems.count))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
    .foregroundStyle(.primary)
}
```

加 `@State private var showTrash = false`，body 末尾加 `.sheet(isPresented: $showTrash) { GlobalTrashView() }`。

- [ ] **Step 2：SettingsView 缓存清除文案统一**

把"清除缓存"按钮的 confirmationDialog（`:45-52`）按术语表调整：

```swift
.confirmationDialog(
    "清除缓存？",
    isPresented: $showClearCacheConfirm,
    titleVisibility: .visible
) {
    Button("清除", role: .destructive) { ... }
} message: {
    Text("将清除所有分析缓存数据，下次扫描需要重新分析。此操作不会影响您的照片和视频。")
}
```

> 此处 "清除" 是缓存场景（不是相册数据），按术语表它属于"清除缓存"特殊语义，可以保留 "清除"。

- [ ] **Step 3：OverviewSection 文案与图标统一**

定位 `:64-69` 处的 `ProgressView` + "正在分析相册..." 替换为：

```swift
ProgressLoadingState(phase: AppStrings.analyzing, progress: progress)
```

定位 `:15` 处 "无法访问相册" 错误文案 → 保留（特殊语义）。

- [ ] **Step 4：QuickCleanView 图标与文案统一**

`:185-202` 的 category icons 用 AppIcons：

```swift
case .waste: AppIcons.waste              // 原 "xmark.bin.fill"
case .similar: AppIcons.similar
case .burst: AppIcons.burst
case .largePhoto: AppIcons.largePhoto
case .video: AppIcons.video
```

加载文案改为 `AppStrings.analyzing`，空状态：

```swift
EmptyState("可清理项", systemImage: "sparkles", description: "相册很整洁")
```

- [ ] **Step 5：SavedNotesView / SavedNoteDetailView 替换 toast**

定位"已复制到剪贴板" toast 自定义实现，替换为 `services.toast.copied()`，删除原本地 toast state。

- [ ] **Step 6：xcodegen + 编译**

Run: `xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
Expected: BUILD SUCCEEDED

- [ ] **Step 7：commit**

```bash
git add AlbumSlim/Views/Settings/ AlbumSlim/Views/QuickCleanView.swift AlbumSlim/Views/SavedNotesView.swift AlbumSlim/Views/SavedNoteDetailView.swift 2>/dev/null
git commit -m "设置/快速扫描/识别记录：统一图标/文案/Toast，加入垃圾桶入口"
```

---

### Task 23：全局清理 + 编译 + 手工验证

**Files:** （扫描全仓）

- [ ] **Step 1：扫描遗漏的硬编码图标/文案**

```bash
grep -rn "systemImage: \"\|\"trash\"\|\"scissors\"\|\"xmark.bin\"\|\"checkmark.circle\"" \
  AlbumSlim/ --include="*.swift" | grep -v "AppIcons" | grep -v "/Common/" | grep -v "/Trash/"
```

逐个评估：是否应替换为 `AppIcons.*` 常量。如果是模块内特定语义（不在统一表里）可保留硬编码。

```bash
grep -rn "已选 \|加载中\|扫描中\|分析中\|压缩中\|识别中\|删除\|清空\|清理" \
  AlbumSlim/Views --include="*.swift" | grep -v "AppStrings"
```

逐个评估：是否应替换为 `AppStrings.*`。

- [ ] **Step 2：扫描遗漏的旧 deprecated trash() 调用**

```bash
grep -rn "services.trash.trash(" AlbumSlim/ --include="*.swift"
```

如果还有，改为 `moveToTrash(assets:source:mediaType:)` 形式。

- [ ] **Step 3：扫描遗漏的 deleteAssets 直接调用**

```bash
grep -rn "photoLibrary.deleteAssets" AlbumSlim/ --include="*.swift"
```

只允许 `TrashService.permanentlyDelete` 内部使用。其他调用点应该都已经走 `moveToTrash`。

- [ ] **Step 4：移除 deprecated 旧 API**

如果 Step 2 确认无残留旧 `trash(_:)` 调用，从 `TrashService.swift` 删除 `@available(*, deprecated, message: ...)` 修饰的 `trash(_ items: [MediaItem])` 方法。

- [ ] **Step 5：完整测试 + 编译**

```bash
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
```
Expected: 所有测试通过 + BUILD SUCCEEDED

- [ ] **Step 6：模拟器手工验证清单**

启动 app，按以下清单逐项验证：

- [ ] **5 Tab 图标**: 视频/照片/截图/设置 4 个底部图标符合统一表
- [ ] **批量选择交互**: 视频/相似/废片/连拍/超大/截图 都通过右上"选择"进入编辑模式，文字正确显示"完成"，左上"全选/取消全选"，标题切换 inline
- [ ] **底部 ActionBar**: 编辑模式下出现，主按钮红色"移到垃圾桶 X 项"无确认弹窗
- [ ] **Toast 反馈**: 移到垃圾桶后底部出现胶囊 toast "已移到垃圾桶 X 项"
- [ ] **垃圾桶入口**: 每个模块右上 toolbar 都有 trash 图标，有项目时带数字 badge；点击打开 GlobalTrashView
- [ ] **跨模块隐藏**: 在相似照片放入垃圾桶 → 切到废片不再显示同一张
- [ ] **GlobalTrashView 编辑模式**: 进入"选择"模式后底部双按钮"恢复 X 项"、"永久删除 X 项"
- [ ] **永久删除确认**: 弹窗标题"永久删除 X 项？" + Message"此操作无法撤销..."，按钮"永久删除"红色 + "取消"
- [ ] **永久删除流程**: 确认 → 触发 iOS 系统权限弹窗 → 删除完成后 toast "已永久删除 X 项，释放 XX MB"
- [ ] **恢复**: 在垃圾桶里恢复一项 → 原模块重新出现
- [ ] **Pro 门槛**: 非 Pro 用户触发清理 → paywall sheet 弹出，伴随 warning haptic
- [ ] **空状态**: 各模块为空时显示"没有 X" + 对应统一图标
- [ ] **加载文案**: 各模块加载/扫描/分析/压缩/识别文案符合统一表
- [ ] **触觉反馈**: 移到垃圾桶感受到 medium，永久删除感受到 heavy
- [ ] **设置-垃圾桶入口**: 设置页有"垃圾桶"条目，显示数量
- [ ] **数据持久化**: 杀掉 app 重启，垃圾桶内容仍在
- [ ] **旧数据迁移**: 如果有旧测试数据，启动后旧 `trashedScreenshotItems` 中的项应已经迁移到新 key（首次启动后该 UserDefaults key 应被清空）
- [ ] **PHChange 同步**: 在系统相册 app 删一张垃圾桶里的照片 → 回 App 该项应消失

如果某项不通过，回到对应 Task 修复后再次验证。

- [ ] **Step 7：最终 commit + 推送**

```bash
git add -A
git commit -m "Wave 3 收尾：清理遗漏，验证完整通过"
git log --oneline -25  # 检查整体提交历史
```

> 是否推送到 remote 由用户决定，本计划不做 push。

---

## 自审检查表

Wave 1 / Wave 2 / Wave 3 完成后核对：

- [ ] **Spec § 3.1 批量选择**：Wave 2 Task 13/15/16/17/18/19 改造覆盖
- [ ] **Spec § 3.2 全局垃圾桶**：Wave 1 Task 5/6/10 + Wave 2 Task 12-19（删除调用）+ Task 20（过滤）覆盖
- [ ] **Spec § 3.3 术语表**：Wave 1 Task 2 沉淀，Wave 2 + Wave 3 Task 22/23 全面替换
- [ ] **Spec § 3.4 SF Symbol**：Wave 1 Task 1 沉淀，Wave 2 Task 12-19 + Wave 3 Task 21/22/23 全面替换
- [ ] **Spec § 3.5 按钮样式**：Wave 1 Task 4 沉淀，Wave 2 Task 13-19 应用
- [ ] **Spec § 3.6 Toast**：Wave 1 Task 7 + Task 11 挂载 + Wave 2 全面调用
- [ ] **Spec § 3.7 Haptic**：Wave 1 Task 3 + Wave 2 全面调用
- [ ] **Spec § 3.8 加载/空状态**：Wave 1 Task 8 + Wave 2/3 替换
- [ ] **Spec § 3.9 Pro 门槛**：Wave 2 Task 15 移除 overlay，统一 sheet
- [ ] **Spec § 3.10 导航栏**：Wave 1 Task 9 SelectionToolbar 内置切换 inline
- [ ] **Spec § 4.3 数据迁移**：Wave 1 Task 5 自动执行，Wave 3 Task 23 验证
- [ ] **Spec § 5 边界情况**：PHChange 同步（GlobalTrashView 已 `task { reconcileWithLibrary() }`）；跨模块去重（Task 5 内置）；恢复行为（Task 10 内置）

---

## 关键风险提示（执行时务必注意）

1. **Wave 2 任务并行时务必各自独立修改不同文件**，避免合并冲突。Task 20 必须等 Task 12-19 全部完成才开始。
2. **每个 Task 内 Step 顺序不能跳跃**：xcodegen → 编译 → 测试 → commit 缺一不可。
3. **Swift 6 严格并发**：`TrashService` 是 `@MainActor @Observable`。在 PHChange 监听回调中调用其方法时，需确保从主线程触发（`Task { @MainActor in ... }`）。参考 `memory/project_swift6_actor_pitfall.md`。
4. **PhotoCleanerViewModel 可能服务于 4 个分类**：Task 15-18 各自传入不同 `source` 参数，注意不要在某个分类里把别的分类的数据也带过去。
5. **永久删除**调用 `PHPhotoLibrary.deleteAssets` 必然触发 iOS 系统弹窗。这不是 bug。
6. **ScreenshotViewModel 旧 `trash(items)` 调用**：Wave 2 Task 19 改为新 API，Task 23 Step 4 才能安全删 deprecated 方法。


