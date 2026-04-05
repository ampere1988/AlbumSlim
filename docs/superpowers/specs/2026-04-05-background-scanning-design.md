# 后台扫描设计方案

## 目标

让 AlbumSlim 在用户切到后台或设备空闲时继续执行照片分析，用户下次打开 App 时可以秒出扫描结果。

## 方案概述

采用**双层后台**架构：

1. **`beginBackgroundTask`** — 用户切后台时，保护当前扫描延长 ~30 秒，保存进度
2. **`BGProcessingTask`** — 系统在设备空闲时自动调度全量分析，支持断点续传

## 架构

```
┌─────────────────────────────────────────┐
│              AlbumSlimApp               │
│  scenePhase 监听 → 触发后台保护/调度     │
└──────────────┬──────────────────────────┘
               │
     ┌─────────▼──────────┐
     │ BackgroundTaskService│  ← 新增
     └─────────┬──────────┘
               │
    ┌──────────┼──────────┐
    ▼          ▼          ▼
StorageAnalyzer  CleanupCoordinator  AnalysisCacheService
                (smartScan 断点续传)   (进度持久化)
```

## 新增组件

### 1. BackgroundTaskService

统一管理后台任务的注册、调度和执行。

```swift
@MainActor @Observable
final class BackgroundTaskService {
    private(set) var isBackgroundScanEnabled = true
    private(set) var lastBackgroundScanAt: Date?

    static let processingTaskID = "com.hao.doushan.analysis"

    func registerBackgroundTasks()
    func handleEnterBackground(services: AppServiceContainer)
    func handleEnterForeground()
    func performBackgroundScan(task: BGProcessingTask, services: AppServiceContainer) async
}
```

**三个时机的行为**：

| 时机 | 动作 |
|---|---|
| App 启动 | `BGTaskScheduler.shared.register(forTaskWithIdentifier:)` 注册处理器 |
| 进入后台 | ① `beginBackgroundTask` 保护当前扫描 30 秒 ② `BGTaskScheduler.shared.submit()` 安排 BGProcessingTask |
| BGProcessingTask 触发 | 加载 ScanProgress，从断点继续执行分析逻辑（仅写缓存） |

**BGProcessingTask 配置**：
- `requiresExternalPower = false`
- `requiresNetworkConnectivity = false`
- 监听 `task.expirationHandler`，收到时保存进度并停止

### 2. ScanProgress

扫描进度模型，持久化到 UserDefaults，支持断点续传。

```swift
struct ScanProgress: Codable {
    var phase: ScanPhase
    var processedAssetIDs: Set<String>
    var startedAt: Date
    var lastUpdatedAt: Date

    enum ScanPhase: String, Codable {
        case waste, similar, burst, largeVideo, done
    }
}
```

**恢复策略**：
- 每完成一个批次（100 张），持久化 `processedAssetIDs`
- 恢复时跳过已处理的 asset
- 废片检测和特征向量的中间结果已缓存在 SwiftData（`CachedAnalysis`），不会重复计算
- 相册变化（`libraryVersion` 变了）时清除进度重新开始

## 现有组件改造

### CleanupCoordinator — smartScan 拆分

将 `smartScan()` 拆分为两层：

```
现在:  smartScan() = 分析 + 构建 CleanupGroup（耦合）

改为:
  ┌─ backgroundAnalyze()  ← 纯分析，写缓存，可断点续传（后台可用）
  └─ buildCleanupGroups() ← 读缓存，构建 CleanupGroup（仅前台）
```

**backgroundAnalyze()**：
1. 废片检测：遍历照片 → `AIAnalysisEngine.detectWaste` → 写入 CachedAnalysis
2. 特征向量提取：遍历照片 → VNFeaturePrint → 写入 CachedAnalysis.featurePrintData
3. 每批次更新 ScanProgress

**buildCleanupGroups()**：
- 从 CachedAnalysis 读取废片 ID → 构建废片 CleanupGroup
- 从 CachedAnalysis 读取特征向量 → 计算相似度 → 构建相似照片 CleanupGroup
- 连拍和大视频直接查询 PHAsset 属性（很快）

**设计决策**：不缓存 CleanupGroup 结果。CleanupGroup 持有 PHAsset 引用（不可序列化），后台扫描的价值是将 AI 分析结果写入 SwiftData，前台回来后 buildCleanupGroups 全部命中缓存，秒出结果。

### AlbumSlimApp

- 添加 `@Environment(\.scenePhase)` 监听
- `init()` 中调用 `registerBackgroundTasks()`
- `.onChange(of: scenePhase)` 中调用 handleEnterBackground / handleEnterForeground

### AppServiceContainer

- 新增 `backgroundTask: BackgroundTaskService` 属性

### project.yml

- 添加 `BGTaskSchedulerPermittedIdentifiers` 到 Info.plist 配置

## 不改动的组件

- **StorageAnalyzer** — 已有缓存机制
- **ImageSimilarityService** — 接口不变
- **AnalysisCacheService** — 接口不变，天然支持断点续传
- **AIAnalysisEngine** — 不改动

## 数据流

```
夜间充电 → 系统调度 BGProcessingTask
  → BackgroundTaskService.performBackgroundScan()
    → CleanupCoordinator.backgroundAnalyze()
      → 废片检测 → CachedAnalysis (SwiftData)
      → 特征向量 → CachedAnalysis (SwiftData)
      → 每批次更新 ScanProgress (UserDefaults)
    → 被中断？保存进度，下次继续

用户打开 App
  → smartScan() 调用 backgroundAnalyze()（跳过已缓存）+ buildCleanupGroups()
  → 全部命中缓存 → 秒出结果
```
