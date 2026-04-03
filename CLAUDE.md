# AlbumSlim (相册瘦身)

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
│   ├── PhotoLibraryService       # Photos 框架封装
│   ├── AIAnalysisEngine          # Vision/CoreML 分析引擎
│   ├── VideoCompressionService   # 视频压缩
│   ├── ImageSimilarityService    # 相似照片 (VNFeaturePrint)
│   ├── OCRService                # 截图 OCR
│   ├── NotesExportService        # 导出到备忘录
│   ├── StorageAnalyzer           # 存储空间分析
│   └── CleanupCoordinator        # 清理协调器
├── ViewModels/             # 视图模型
├── Views/                  # SwiftUI 视图
│   ├── Onboarding/         # 首次启动引导
│   ├── Dashboard/          # 存储仪表盘
│   ├── Video/              # 视频管理
│   ├── Photo/              # 照片清理
│   ├── Screenshot/         # 截图管理
│   └── Common/             # 通用组件
└── Utils/                  # 工具类
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
- 编译验证: `xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`

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

### 🔲 P2 - 增长优化
14. Foundation Models 智能总结 (iOS 26+)
15. Live Photo 优化
16. Widget 小组件 + 定期清理提醒
17. 清理成就系统 + 分享卡片
18. 微信/QQ 图片识别清理
19. 证件照安全提醒
20. Shortcuts / AppIntents 集成
21. ASO 优化 + 营销素材

## 商业模式

免费 + Pro 订阅 (月￥6 / 年￥38 / 终身￥98)
- 免费: 仪表盘 + 视频排序 + 废片检测(限20张) + 相似照片(前3组)
- Pro: 无限清理 + 视频压缩 + OCR + 一键清理 + 所有新功能
