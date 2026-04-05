# 后台扫描实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 App 在后台和系统空闲时自动完成照片分析，用户回到前台秒出结果。

**Architecture:** 新增 BackgroundTaskService 管理 BGProcessingTask + beginBackgroundTask；将 CleanupCoordinator.smartScan 拆分为可断点续传的 backgroundAnalyze() 和前台快速组装的 buildCleanupGroups()；通过 ScanProgress 模型持久化扫描进度。

**Tech Stack:** BackgroundTasks (BGProcessingTask), UIKit (beginBackgroundTask), SwiftData, UserDefaults

---

## 文件结构

| 操作 | 文件路径 | 职责 |
|---|---|---|
| 新增 | `AlbumSlim/Models/ScanProgress.swift` | 扫描进度模型，Codable，持久化到 UserDefaults |
| 新增 | `AlbumSlim/Services/BackgroundTaskService.swift` | BGProcessingTask 注册/调度 + beginBackgroundTask 管理 |
| 修改 | `AlbumSlim/Services/CleanupCoordinator.swift` | 拆分 smartScan 为 backgroundAnalyze + buildCleanupGroups |
| 修改 | `AlbumSlim/App/AppServiceContainer.swift` | 新增 backgroundTask 属性 |
| 修改 | `AlbumSlim/App/AlbumSlimApp.swift` | scenePhase 监听 + 后台任务注册 |
| 修改 | `project.yml` | 添加 BGTaskSchedulerPermittedIdentifiers |

---

### Task 1: ScanProgress 模型

**Files:**
- Create: `AlbumSlim/Models/ScanProgress.swift`

- [ ] **Step 1: 创建 ScanProgress 模型**

```swift
import Foundation

struct ScanProgress: Codable {
    enum Phase: String, Codable, CaseIterable {
        case waste      // 废片检测
        case similar    // 特征向量提取（相似照片分析的前置步骤）
        case done       // 完成
    }

    var phase: Phase = .waste
    var processedAssetIDs: Set<String> = []
    var libraryVersion: Int = -1
    var startedAt: Date = .now
    var lastUpdatedAt: Date = .now

    // MARK: - 持久化

    private static let key = "ScanProgressCache"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func load() -> ScanProgress? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ScanProgress.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

- [ ] **Step 2: xcodegen 并编译验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add AlbumSlim/Models/ScanProgress.swift
git commit -m "新增 ScanProgress 扫描进度模型，支持断点续传持久化"
```

---

### Task 2: CleanupCoordinator 拆分

**Files:**
- Modify: `AlbumSlim/Services/CleanupCoordinator.swift`

将现有 `smartScan()` 拆分为 `backgroundAnalyze()` + `buildCleanupGroups()`，保持原有 `smartScan()` 作为前台入口调用这两个方法。

- [ ] **Step 1: 添加 backgroundAnalyze 方法**

在 `CleanupCoordinator` 中添加 `backgroundAnalyze` 方法。这个方法只做 AI 分析并写入缓存，不构建 CleanupGroup。支持通过 ScanProgress 断点续传，通过 `cancelFlag` 支持外部取消。

```swift
/// 纯分析：废片检测 + 特征向量提取，写入 SwiftData 缓存，支持断点续传
/// 后台安全：不持有 CleanupGroup / PHAsset 引用
/// - Parameter cancelFlag: 外部可设为 true 以请求停止
func backgroundAnalyze(services: AppServiceContainer, cancelFlag: UnsafeMutablePointer<Bool>? = nil) async {
    let photoLibrary = services.photoLibrary
    let engine = services.aiEngine
    let cache = services.analysisCache
    let batchSize = AppConstants.Analysis.batchSize
    let thumbSize = CGSize(width: 300, height: 300)

    // 加载或创建进度
    var progress = ScanProgress.load() ?? ScanProgress()

    // 相册版本变了，重置进度
    if progress.libraryVersion != photoLibrary.libraryVersion {
        progress = ScanProgress()
        progress.libraryVersion = photoLibrary.libraryVersion
    }

    guard progress.phase != .done else { return }

    // Phase 1: 废片检测
    if progress.phase == .waste {
        scanPhase = .waste
        scanProgress = 0

        let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
        let photoTotal = photoFetch.count

        for batchStart in stride(from: 0, to: photoTotal, by: batchSize) {
            if cancelFlag?.pointee == true { progress.save(); return }

            let batchEnd = min(batchStart + batchSize, photoTotal)
            var batchIDs: [String] = []

            autoreleasepool {
                for i in batchStart..<batchEnd {
                    let asset = photoFetch.object(at: i)
                    let assetID = asset.localIdentifier
                    batchIDs.append(assetID)
                }
            }

            // 跳过已处理的
            let cachedIDs = cache.cachedAssetIDs(from: batchIDs)
            for i in batchStart..<batchEnd {
                if cancelFlag?.pointee == true { progress.save(); return }

                let asset = photoFetch.object(at: i)
                let assetID = asset.localIdentifier
                if cachedIDs.contains(assetID) || progress.processedAssetIDs.contains(assetID) {
                    continue
                }

                if let image = await photoLibrary.thumbnail(for: asset, size: thumbSize) {
                    let result = autoreleasepool { engine.detectWaste(image: image) }
                    cache.saveWasteResult(assetID: assetID, isWaste: result.isWaste, reason: result.reason)
                }
                progress.processedAssetIDs.insert(assetID)
            }
            cache.batchSave()
            scanProgress = Double(batchEnd) / Double(photoTotal) * 0.5
            progress.lastUpdatedAt = .now
            progress.save()
            await Task.yield()
        }

        // 进入下一阶段
        progress.phase = .similar
        progress.processedAssetIDs.removeAll()
        progress.save()
    }

    // Phase 2: 特征向量提取
    if progress.phase == .similar {
        scanPhase = .similar
        let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
        let photoTotal = photoFetch.count

        for batchStart in stride(from: 0, to: photoTotal, by: batchSize) {
            if cancelFlag?.pointee == true { progress.save(); return }

            let batchEnd = min(batchStart + batchSize, photoTotal)

            for i in batchStart..<batchEnd {
                if cancelFlag?.pointee == true { progress.save(); return }

                let asset = photoFetch.object(at: i)
                let assetID = asset.localIdentifier

                if progress.processedAssetIDs.contains(assetID) { continue }
                if cache.featurePrintData(for: assetID) != nil {
                    progress.processedAssetIDs.insert(assetID)
                    continue
                }

                if let image = await photoLibrary.thumbnail(for: asset, size: thumbSize) {
                    if let cgImage = image.cgImage {
                        let fp: VNFeaturePrintObservation? = autoreleasepool {
                            engine.featurePrint(for: cgImage)
                        }
                        if let fp, let data = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true) {
                            cache.saveFeaturePrint(assetID: assetID, data: data)
                        }
                    }
                }
                progress.processedAssetIDs.insert(assetID)
            }
            cache.batchSave()
            scanProgress = 0.5 + Double(batchEnd) / Double(photoTotal) * 0.5
            progress.lastUpdatedAt = .now
            progress.save()
            await Task.yield()
        }

        progress.phase = .done
        progress.save()
    }

    scanPhase = .done
    scanProgress = 1.0
}
```

注意：需要在文件顶部添加 `import Vision`。

- [ ] **Step 2: 添加 buildCleanupGroups 方法**

从缓存中读取分析结果，快速构建 CleanupGroup。这个方法只在前台调用。

```swift
/// 从缓存构建清理分组（前台使用，读取 backgroundAnalyze 的缓存结果）
func buildCleanupGroups(services: AppServiceContainer) async -> [CleanupGroup] {
    var allGroups: [CleanupGroup] = []
    let photoLibrary = services.photoLibrary
    let cache = services.analysisCache

    // 1. 废片（从缓存读取）
    let wasteIDs = cache.allCachedWasteIDs()
    if !wasteIDs.isEmpty {
        let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
        var wasteItems: [MediaItem] = []
        let batchSize = AppConstants.Analysis.batchSize
        for batchStart in stride(from: 0, to: photoFetch.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, photoFetch.count)
            autoreleasepool {
                for i in batchStart..<batchEnd {
                    let asset = photoFetch.object(at: i)
                    if wasteIDs.contains(asset.localIdentifier) {
                        let size = photoLibrary.fileSize(for: asset)
                        wasteItems.append(MediaItem(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: size,
                            creationDate: asset.creationDate
                        ))
                    }
                }
            }
        }
        if !wasteItems.isEmpty {
            allGroups.append(CleanupGroup(type: .waste, items: wasteItems, bestItemID: nil))
        }
    }

    // 2. 相似照片（利用缓存的特征向量，计算极快）
    let photoFetch = photoLibrary.fetchAllAssets(mediaType: .image)
    let allPhotoItems = await photoLibrary.buildMediaItems(from: photoFetch)
    let similarGroups = await services.imageSimilarity.findSimilarGroups(
        from: allPhotoItems,
        using: photoLibrary,
        cache: cache,
        onProgress: { _ in }
    )
    allGroups.append(contentsOf: similarGroups)

    // 3. 连拍
    let burstFetch = photoLibrary.fetchBurstAssets()
    let burstItems = await photoLibrary.buildMediaItems(from: burstFetch)
    var burstMap: [String: [MediaItem]] = [:]
    for item in burstItems {
        if let burstID = item.asset.burstIdentifier {
            burstMap[burstID, default: []].append(item)
        }
    }
    let burstGroups = burstMap.values
        .filter { $0.count > 1 }
        .map { items in
            let best = items.max(by: { $0.fileSize < $1.fileSize })
            return CleanupGroup(type: .burst, items: items, bestItemID: best?.id)
        }
    allGroups.append(contentsOf: burstGroups)

    // 4. 大视频 (>100MB)
    let videoFetch = photoLibrary.fetchAllAssets(mediaType: .video)
    let largeVideoThreshold: Int64 = 100 * 1024 * 1024
    var largeVideos: [MediaItem] = []
    let batchSize = AppConstants.Analysis.batchSize
    for batchStart in stride(from: 0, to: videoFetch.count, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, videoFetch.count)
        autoreleasepool {
            for i in batchStart..<batchEnd {
                let asset = videoFetch.object(at: i)
                let size = photoLibrary.fileSize(for: asset)
                if size > largeVideoThreshold {
                    largeVideos.append(MediaItem(
                        id: asset.localIdentifier,
                        asset: asset,
                        fileSize: size,
                        creationDate: asset.creationDate
                    ))
                }
            }
        }
    }
    if !largeVideos.isEmpty {
        allGroups.append(CleanupGroup(type: .largeVideo, items: largeVideos, bestItemID: nil))
    }

    return allGroups
}
```

- [ ] **Step 3: 重构 smartScan 调用新方法**

将现有 `smartScan` 改为调用 `backgroundAnalyze` + `buildCleanupGroups`：

```swift
func smartScan(services: AppServiceContainer) async -> [CleanupGroup] {
    clearAll()

    // Phase 1: 分析（写缓存，支持断点续传）
    await backgroundAnalyze(services: services)

    // Phase 2: 组装结果（读缓存，构建 CleanupGroup）
    let allGroups = await buildCleanupGroups(services: services)

    addGroups(allGroups)
    return allGroups
}
```

删除旧的 smartScan 实现（第 78-214 行的整个方法体）。

- [ ] **Step 4: xcodegen 并编译验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: 提交**

```bash
git add AlbumSlim/Services/CleanupCoordinator.swift
git commit -m "重构 smartScan：拆分为 backgroundAnalyze + buildCleanupGroups，支持断点续传"
```

---

### Task 3: BackgroundTaskService

**Files:**
- Create: `AlbumSlim/Services/BackgroundTaskService.swift`

- [ ] **Step 1: 创建 BackgroundTaskService**

```swift
import Foundation
import BackgroundTasks
import UIKit

@MainActor @Observable
final class BackgroundTaskService {
    static let processingTaskID = "com.hao.doushan.analysis"

    private(set) var lastBackgroundScanAt: Date? = UserDefaults.standard.object(forKey: "lastBackgroundScanAt") as? Date

    /// 后台任务被要求停止时设为 true
    private var shouldCancel = false

    /// 当前后台延长任务的标识
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - 注册（必须在 App 启动时、didFinishLaunching 返回前调用）

    func registerBackgroundTasks(services: AppServiceContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskID,
            using: nil
        ) { [weak self] task in
            guard let self, let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await self.handleProcessingTask(task, services: services)
            }
        }
    }

    // MARK: - scenePhase 事件

    func handleEnterBackground(services: AppServiceContainer) {
        // 1. beginBackgroundTask 保护当前扫描
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        // 2. 安排 BGProcessingTask
        scheduleProcessingTask()
    }

    func handleEnterForeground() {
        endBackgroundTask()
        shouldCancel = false
    }

    // MARK: - BGProcessingTask 执行

    private func handleProcessingTask(_ task: BGProcessingTask, services: AppServiceContainer) async {
        // 安排下一次
        scheduleProcessingTask()

        shouldCancel = false
        task.expirationHandler = { [weak self] in
            self?.shouldCancel = true
        }

        await withUnsafeMutablePointer(to: &shouldCancel) { cancelPtr in
            await services.cleanupCoordinator.backgroundAnalyze(
                services: services,
                cancelFlag: cancelPtr
            )
        }

        lastBackgroundScanAt = .now
        UserDefaults.standard.set(lastBackgroundScanAt, forKey: "lastBackgroundScanAt")

        task.setTaskCompleted(success: !shouldCancel)
    }

    // MARK: - Private

    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskID)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        // 至少等 15 分钟再调度（避免频繁触发）
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
```

- [ ] **Step 2: xcodegen 并编译验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add AlbumSlim/Services/BackgroundTaskService.swift
git commit -m "新增 BackgroundTaskService：BGProcessingTask 注册调度 + beginBackgroundTask 保护"
```

---

### Task 4: AppServiceContainer + AlbumSlimApp 集成

**Files:**
- Modify: `AlbumSlim/App/AppServiceContainer.swift:6,19-32`
- Modify: `AlbumSlim/App/AlbumSlimApp.swift:4-20`

- [ ] **Step 1: AppServiceContainer 添加 backgroundTask 属性**

在 `AlbumSlim/App/AppServiceContainer.swift` 中添加属性和初始化：

属性声明（在 `let reminder: ReminderService` 之后添加）：
```swift
let backgroundTask: BackgroundTaskService
```

初始化（在 `self.reminder = ReminderService()` 之后添加）：
```swift
self.backgroundTask = BackgroundTaskService()
```

- [ ] **Step 2: AlbumSlimApp 添加 scenePhase 监听和后台任务注册**

将 `AlbumSlim/App/AlbumSlimApp.swift` 修改为：

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

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding && PermissionManager.isAuthorized {
                MainTabView()
                    .environment(services)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .modelContainer(for: CachedAnalysis.self)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                services.backgroundTask.handleEnterBackground(services: services)
            case .active:
                services.backgroundTask.handleEnterForeground()
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 3: xcodegen 并编译验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add AlbumSlim/App/AppServiceContainer.swift AlbumSlim/App/AlbumSlimApp.swift
git commit -m "集成 BackgroundTaskService：scenePhase 监听 + 后台任务注册"
```

---

### Task 5: project.yml 配置 BGTaskSchedulerPermittedIdentifiers

**Files:**
- Modify: `project.yml:29-40`

- [ ] **Step 1: 添加 Info.plist 配置**

在 `project.yml` 的 AlbumSlim target 的 `settings.base` 中添加 `BGTaskSchedulerPermittedIdentifiers`。

由于 XcodeGen 的 `INFOPLIST_KEY_` 前缀不支持数组类型的 plist key，需要改用 `info` 字段。在 AlbumSlim target 的 `settings` 之后、`dependencies` 之前添加：

```yaml
    info:
      properties:
        BGTaskSchedulerPermittedIdentifiers:
          - com.hao.doushan.analysis
        UIBackgroundModes:
          - processing
```

- [ ] **Step 2: xcodegen 并编译验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add project.yml
git commit -m "配置 BGTaskSchedulerPermittedIdentifiers 和 UIBackgroundModes"
```

---

### Task 6: 编译验证 + 最终提交

**Files:** 无新文件

- [ ] **Step 1: 全量编译验证**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: 检查所有改动**

```bash
git log --oneline -5
```

预期看到 5 个新 commit：
1. ScanProgress 模型
2. CleanupCoordinator 拆分
3. BackgroundTaskService
4. AppServiceContainer + AlbumSlimApp 集成
5. project.yml 配置
