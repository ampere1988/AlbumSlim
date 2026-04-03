# AlbumSlim (相册瘦身)

利用 iOS 设备端 AI 能力，智能分析相册并释放存储空间。所有处理 100% 本地完成，零隐私风险。

## 技术栈

- **语言**: Swift 6
- **UI**: SwiftUI (iOS 17+)
- **数据**: SwiftData
- **最低版本**: iOS 17.0
- **架构**: MVVM + 服务容器 (依赖注入)

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
│   ├── Dashboard/          # 存储仪表盘
│   ├── Video/              # 视频管理
│   ├── Photo/              # 照片清理
│   ├── Screenshot/         # 截图管理
│   └── Common/             # 通用组件
└── Utils/                  # 工具类
```

## 编码规范

- 使用 `@Observable` macro (iOS 17+) 而非 ObservableObject
- 服务层通过 `AppServiceContainer` 注入，不使用全局单例
- Photos 操作必须通过 `PHPhotoLibrary.shared().performChanges` 异步执行
- 大量资源处理使用 `TaskGroup` 并发，限制并发数 ≤ 4
- 特征向量等耗时计算结果缓存到 SwiftData
- 每批处理 100 张，使用 `autoreleasepool` 避免 OOM
- git commit 消息用中文

## 功能优先级

### P0 - MVP
1. 存储空间仪表盘
2. 视频按大小排序
3. 视频压缩 (HEVC 三档)
4. 废片检测 (黑屏/模糊/遮挡)
5. 相似照片分组
6. 批量删除

### P1
7. 连拍清理
8. 截图 OCR
9. 截图导出备忘录
10. 视频清理建议
11. 一键清理方案

### P2
12. Foundation Models 智能总结 (iOS 26+)
13. Live Photo 优化
14. Widget / 提醒 / 成就系统
15. Shortcuts 集成

## 商业模式

免费 + Pro 订阅 (月￥6 / 年￥38 / 终身￥98)
- 免费: 仪表盘 + 视频排序 + 有限清理
- Pro: 无限清理 + 视频压缩 + OCR + 一键清理
