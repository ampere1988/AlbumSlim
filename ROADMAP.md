# AlbumSlim 开发路线图

> 最后更新: 2026-04-04

## Phase 1: MVP ✅ (已完成)

### 1.1 项目基础
- [x] Xcode 项目搭建 (XcodeGen + SwiftUI + iOS 17)
- [x] MVVM + AppServiceContainer 依赖注入架构
- [x] Photos Framework 权限管理
- [x] 首次启动引导页 (OnboardingView)
- [x] 主界面 Tab 导航

### 1.2 存储仪表盘
- [x] StorageAnalyzer 扫描所有资源类型和大小
- [x] 环形图展示视频/照片/截图占比 (Swift Charts)
- [x] 分类统计卡片 (点击跳转对应 Tab)
- [x] 预估可释放空间横幅

### 1.3 视频管理
- [x] 视频列表 (缩略图 + 大小 + 时长 + 分辨率)
- [x] 排序: 按大小/时长/日期
- [x] 视频压缩三档 (高/中/省空间)
- [x] 压缩预估 + 实际结果对比
- [x] 保存模式: 替换原视频 / 保存为新视频
- [x] 多选批量压缩
- [x] iCloud 视频 + 慢动作视频兼容
- [x] 临时文件自动清理

### 1.4 照片清理
- [x] 废片检测 (纯黑/纯白/模糊/手指遮挡)
- [x] 废片原因标签 + 保留按钮
- [x] 相似照片 VNFeaturePrint 余弦相似度聚类
- [x] 按5分钟时间窗口预分组优化性能
- [x] 推荐最佳照片 (文件大小最大)
- [x] 连拍照片分组 + 水平滑动 + 只保留最佳
- [x] 统一选择模式 (勾选 + 蓝色覆盖)
- [x] 批量删除 + 确认对话框
- [x] 分批处理 + 进度回调

---

## Phase 2: 功能完善 ✅ (已完成)

> 目标: 补全截图管理、智能推荐、订阅系统，提升付费转化

### 2.1 截图管理 ✅
- [x] 接通 ScreenshotListView ↔ OCRService
- [x] 截图内容分类优化 (新增: 快递、会议、代码、社交媒体)
- [x] 截图详情页: 大图预览 + OCR 全文 + 复制/导出/删除
- [x] 导出到 Apple Notes (mobilenotes:// URL Scheme)
- [x] 批量操作: 编辑模式多选 + 分类筛选 + 批量导出/删除

### 2.2 视频清理建议 ✅
- [x] VideoAnalysisService: 识别超长(>5min)/低质量/大文件(>100MB)/疑似重复
- [x] VideoSuggestionsView: 按类型分 Section 展示 + 多选批量操作
- [x] 集成到 VideoListView 工具栏

### 2.3 智能一键清理 ✅
- [x] CleanupCoordinator.smartScan: 聚合废片+相似+连拍+大视频
- [x] QuickCleanView: 三阶段 UI (扫描→预览→完成动画)
- [x] DashboardView 添加智能清理入口卡片

### 2.4 StoreKit 2 订阅 ✅
- [x] SubscriptionService: StoreKit 2 购买/恢复/状态监听
- [x] PaywallView: 功能对比 + 三档订阅卡片 + 购买流程
- [x] ProFeatureGate: 废片20张/相似3组/压缩/OCR/一键清理限制
- [x] 付费墙集成: WastePhotos/SimilarPhotos/VideoCompress/Screenshot

### 2.5 关键技术文件

| 任务 | 涉及文件 |
|---|---|
| 截图 OCR | `Services/OCRService.swift`, `ViewModels/ScreenshotViewModel.swift`, `Views/Screenshot/ScreenshotListView.swift` |
| 截图导出 | `Services/NotesExportService.swift` |
| 视频建议 | 新建 `Services/VideoAnalysisService.swift`, `ViewModels/VideoManagerViewModel.swift` |
| 一键清理 | `Services/CleanupCoordinator.swift`, 新建 `Views/Dashboard/QuickCleanView.swift` |
| 订阅系统 | 新建 `Services/SubscriptionService.swift`, `Views/Settings/PaywallView.swift` |

---

## Phase 3: 增长优化 ✅ (已完成)

> 目标: 提升留存、扩大用户获取

### 3.1 性能优化 ✅
- [x] 大相册 (10000+ 张) 扫描速度优化
  - StorageStats 缓存到 UserDefaults + App Groups
  - PHPhotoLibraryChangeObserver 增量检测
  - StorageAnalyzer 后台线程扫描 (Task.detached)
  - CachedAnalysis SwiftData 集成 (AnalysisCacheService)
  - autoreleasepool 包裹批处理循环
- [x] 相似度计算优化: VNFeaturePrintObservation 序列化缓存 (NSKeyedArchiver)
- [x] 视频压缩队列: CompressionTask 队列 + 后台处理 + 本地通知完成

### 3.2 Widget + 提醒 ✅
- [x] WidgetKit 小组件: systemSmall/systemMedium 环形图 + 存储统计
- [x] App Groups 数据共享 (group.com.huge.albumslim)
- [x] ReminderService: 每周/每两周/每月清理提醒
- [x] SettingsView: 提醒开关 + 频率选择 + 通知权限管理

### 3.3 社交化 ✅
- [x] 清理成就系统 (10 个成就: 100MB~10GB 空间里程碑 + 清理次数 + 删除数量)
- [x] 分享卡片生成 (ImageRenderer + 渐变背景 + UIActivityViewController)
- [x] App Store 评价引导 (SKStoreReviewController, 清理>=3次 + 90天间隔)

### 3.4 ASO + 营销
- [ ] 关键词覆盖: 清理照片、手机瘦身、释放空间、相册管理
- [ ] App Store 截图 + 预览视频
- [ ] 小红书/抖音内容营销素材

---

## Phase 4: 高级功能

> 目标: 差异化竞争、技术前瞻

### 4.1 Foundation Models (iOS 26+)
- [ ] 端侧大模型总结截图内容
- [ ] 智能相册描述和标签
- [ ] 自然语言清理指令 ("删除去年旅行中的模糊照片")

### 4.2 高级清理
- [ ] Live Photo 优化 (检测无意义视频部分 → 转静态)
- [ ] 微信/QQ 保存图片识别 (mmexport/IMG 文件名规则)
- [ ] 表情包归档 (小尺寸 + GIF/WebP)
- [ ] 证件照安全提醒 (身份证/银行卡/护照检测)

### 4.3 自动化
- [ ] AppIntents / Shortcuts 集成
- [ ] 自动化清理规则 (每周自动扫描 + 建议)

### 4.4 多平台
- [ ] iPad 适配 (多列布局)
- [ ] visionOS 适配 (远期)

---

## 技术债务清单

| 项 | 优先级 | 说明 |
|---|---|---|
| ~~SwiftData 缓存~~ | ~~高~~ | ~~已完成: AnalysisCacheService 集成废片+特征向量缓存~~ |
| ~~增量扫描~~ | ~~高~~ | ~~已完成: PHPhotoLibraryChangeObserver + libraryVersion 版本检测~~ |
| 质量评分优化 | 中 | qualityScore 可用 VNCalculateImageAestheticsScoresRequest (iOS 18+) |
| VNFeaturePrint 距离 | 中 | computeDistance 返回的是欧氏距离不是余弦距离，阈值需真机校准 |
| 错误处理 | 中 | 部分 try? 需要改为 proper error handling + 用户提示 |
| 并发严格性 | 低 | 当前 targeted，后续可升级为 complete |
| 单元测试 | 低 | Services 层需要测试覆盖 |
