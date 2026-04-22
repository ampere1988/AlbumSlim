# AlbumSlim (闪图)

利用 iOS 设备端 AI 能力，智能分析相册并释放存储空间。所有处理 100% 本地完成，零隐私风险。

## 技术栈

- **语言**: Swift 6
- **UI**: SwiftUI (iOS 17+)
- **数据**: SwiftData
- **最低版本**: iOS 17.0
- **架构**: MVVM + 服务容器 (依赖注入)
- **构建**: XcodeGen (`project.yml` → `.xcodeproj`)

### 核心框架

| 框架 | 用途 |
|---|---|
| Photos | 相册访问、PHAsset 管理、批量删除 |
| Vision | 图像分类、特征提取(相似度)、质量检测 |
| VisionKit | OCR 文字识别 (中文) |
| AVFoundation | 视频压缩 (AVAssetExportSession) |
| NaturalLanguage | 截图文本分类 |
| StoreKit 2 | 订阅管理 |

## 项目结构

```
AlbumSlim/
├── App/                    # 入口 + 服务容器
├── Models/                 # 数据模型 (MediaItem, AnalysisResult 等)
├── Services/               # 业务服务层
│   ├── PhotoLibraryService       # Photos 框架封装 + PHPhotoLibraryChangeObserver
│   ├── AIAnalysisEngine          # Vision/CoreML 分析引擎
│   ├── VideoCompressionService   # 视频压缩 + 后台队列
│   ├── ImageSimilarityService    # 相似照片 (VNFeaturePrint + 缓存)
│   ├── AnalysisCacheService      # SwiftData 分析结果缓存
│   ├── AchievementService        # 清理成就系统
│   ├── ReminderService           # 定期清理提醒
│   ├── OCRService                # 截图 OCR
│   ├── NotesExportService        # 导出到备忘录
│   ├── StorageAnalyzer           # 存储空间分析 (缓存+后台)
│   └── CleanupCoordinator        # 清理协调器
├── ViewModels/             # 视图模型
├── Views/                  # SwiftUI 视图
│   ├── Onboarding/         # 首次启动引导
│   ├── Dashboard/          # 存储仪表盘
│   ├── Video/              # 视频管理
│   ├── Photo/              # 照片清理
│   ├── Screenshot/         # 截图管理
│   ├── Settings/           # 设置 + 成就页
│   └── Common/             # 通用组件 + 分享卡片
├── Utils/                  # 工具类
AlbumSlimWidget/            # WidgetKit 小组件 (独立 target)
```

## 开发命令

```bash
# 重新生成 Xcode 项目（修改 Swift 文件或 project.yml 后必须执行）
xcodegen generate

# 编译（Debug, iOS Simulator）
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'

# 运行测试
xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'

# 清理构建
xcodebuild clean -project AlbumSlim.xcodeproj -scheme AlbumSlim
```

## 编码规范

- 所有 `@Observable` 类标记 `@MainActor`
- 使用 `@Observable` macro (iOS 17+) 而非 ObservableObject
- 服务层通过 `AppServiceContainer` 注入，View 中用 `@Environment(AppServiceContainer.self)`
- Photos 操作必须通过 `PHPhotoLibrary.shared().performChanges` 异步执行
- 大批量处理分批（每批 100 张 `AppConstants.Analysis.batchSize`），避免 OOM
- 特征向量等耗时计算结果缓存到 SwiftData（`CachedAnalysis` 模型）
- 并发严格性: `SWIFT_STRICT_CONCURRENCY = targeted`
- git commit 消息用中文
- 修改 Swift 文件后需 `xcodegen generate` 重新生成 xcodeproj

### 命名规范

| 类型 | 规则 | 示例 |
|---|---|---|
| Service | `{Domain}Service` 或 `{Domain}Coordinator/Analyzer/Engine` | `PhotoLibraryService`, `CleanupCoordinator` |
| ViewModel | `{Feature}ViewModel` | `PhotoCleanerViewModel`, `DashboardViewModel` |
| Model | 单数名词 | `MediaItem`, `CleanupGroup`, `StorageStats` |
| View | `{Feature}View` | `PhotoCleanerView`, `DashboardView` |
| 枚举 | PascalCase | `WasteReason`, `PhotoQuality`, `GroupType` |

## 服务依赖关系

```
AppServiceContainer（统一容器，所有服务在 init 时创建）
│
├── PhotoLibraryService          # 基础层 — 无依赖
├── AIAnalysisEngine             # 基础层 — 无依赖
├── OCRService                   # 基础层 — 无依赖
├── VideoAnalysisService         # 基础层 — 无依赖
├── AchievementService           # 基础层 — 仅 UserDefaults
├── NotesExportService           # 基础层 — 仅 UserDefaults
├── ReminderService              # 基础层 — 无依赖
├── SubscriptionService          # 基础层 — StoreKit
├── AnalysisCacheService         # 基础层 — SwiftData
│
├── StorageAnalyzer              → PhotoLibraryService
├── ImageSimilarityService       → PhotoLibraryService, AnalysisCacheService
├── VideoCompressionService      # 独立 — AVFoundation
├── CleanupCoordinator           → PhotoLibraryService, AIAnalysisEngine,
│                                  AnalysisCacheService, ImageSimilarityService
└── BackgroundTaskService        → AppServiceContainer (调用 cleanupCoordinator)
```

## ViewModel 模式

ViewModel **不通过构造函数注入服务**，而是在异步方法中接收 `AppServiceContainer`：

```swift
@MainActor @Observable
final class SomeFeatureViewModel {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?

    func load(services: AppServiceContainer) async {
        isLoading = true
        defer { isLoading = false }
        // 通过 services.xxx 访问具体服务
    }

    func delete(ids: Set<String>, services: AppServiceContainer) async {
        // Pro 功能检查: services.subscription.isPro
        // 删除操作: services.photoLibrary.deleteAssets(...)
        // 成就记录: services.achievement.recordCleanup(...)
    }
}
```

View 中获取容器: `@Environment(AppServiceContainer.self) var services`

## 添加新功能指南

1. **Model** — 在 `Models/` 定义数据模型，遵循 `Identifiable`
2. **Service**（如需要）— 在 `Services/` 创建，注册到 `AppServiceContainer`
3. **ViewModel** — 在 `ViewModels/` 创建，`@MainActor @Observable`，方法接收 `services: AppServiceContainer`
4. **View** — 在 `Views/{Feature}/` 创建，用 `@Environment(AppServiceContainer.self)` 获取容器
5. **Pro 限制** — 清理/删除操作需 `ProFeatureGate` 包裹或检查 `services.subscription.isPro`
6. **构建验证** — `xcodegen generate && xcodebuild build ...`

## 开发进度

### ✅ P0 - MVP (已完成)
1. ~~存储空间仪表盘~~ — 环形图 + 分类统计 + 预估可释放
2. ~~视频按大小排序~~ — 缩略图 + 排序(大小/时长/日期) + 多选
3. ~~视频压缩~~ — HEVC 三档 + 替换原视频/保存新视频
4. ~~废片检测~~ — 纯黑/纯白/模糊/手指遮挡 + 原因标签
5. ~~相似照片分组~~ — VNFeaturePrint 余弦相似度 + 推荐最佳
6. ~~批量删除~~ — 选择模式 + 确认对话框
7. ~~首次启动引导~~ — 权限请求 + 隐私说明
8. ~~连拍清理~~ — 分组展示 + 只保留最佳

### ✅ P1 - 功能完善 (已完成)
9. ~~截图管理完善~~ — 分类优化 + 详情页 + 批量操作 + Pro 限制
10. ~~视频清理建议~~ — VideoAnalysisService + 超长/低质/大文件/重复识别
11. ~~智能一键清理~~ — smartScan 聚合 + QuickCleanView 三阶段 UI
12. ~~StoreKit 2 订阅~~ — SubscriptionService + PaywallView + ProFeatureGate

### ✅ P2 - 增长优化 (已完成)
13. ~~性能优化~~ — StorageStats 缓存 + PHChange 增量 + 后台扫描 + CachedAnalysis 集成 + 特征向量缓存
14. ~~Widget 小组件~~ — WidgetKit (small/medium) + App Groups + ReminderService + SettingsView
15. ~~社交化~~ — 10 个清理成就 + 分享卡片 (ImageRenderer) + SKStoreReviewController
16. ~~视频压缩队列~~ — CompressionTask 队列 + 后台处理 + 本地通知

### 🔲 P3 - 高级功能
17. Foundation Models 智能总结 (iOS 26+)
18. Live Photo 优化
17. 清理成就系统 + 分享卡片
18. 微信/QQ 图片识别清理
19. 证件照安全提醒
20. Shortcuts / AppIntents 集成
21. ASO 优化 + 营销素材

## 商业模式

免费 + Pro 一次性买断 ($1)
- 免费: 仪表盘 + 扫描浏览（所有模块均可扫描和查看结果）
- Pro: 所有清理/删除/压缩操作（废片清理、相似照片去重、视频压缩、OCR识别、连拍清理、大照片清理、批量删除等）
