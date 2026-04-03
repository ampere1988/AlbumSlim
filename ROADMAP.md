# AlbumSlim 开发路线图

> 最后更新: 2026-04-03

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

## Phase 2: 功能完善 (下一阶段)

> 目标: 补全截图管理、智能推荐、订阅系统，提升付费转化

### 2.1 截图管理 (优先)
- [ ] 接通 ScreenshotListView ↔ OCRService
  - ScreenshotViewModel.analyzeScreenshot 已实现，需真机验证 OCR 效果
  - VNRecognizeTextRequest: `recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]`
- [ ] 截图内容分类优化
  - 当前 OCRService.categorize 基于关键词，需增加更多中文场景
  - 添加: 快递单号、会议截图、代码截图 等类别
- [ ] 截图详情页: 显示 OCR 全文 + 分类标签 + 操作按钮
- [ ] 导出到 Apple Notes
  - 当前 NotesExportService 使用 `mobilenotes://` URL Scheme
  - 需真机验证兼容性，备选方案: UIPasteboard + 打开备忘录
- [ ] 批量操作: 全选分析 → 导出有价值内容 → 批量删除截图

### 2.2 视频清理建议
- [ ] 识别超长视频 (>5min) 并建议裁剪或压缩
- [ ] 检测重复录制 (时间相近 + 时长相近 + 采样帧相似)
- [ ] 低质量视频标记 (低分辨率、短时长抖动视频)
- [ ] 视频清理建议页面整合

### 2.3 智能一键清理
- [ ] CleanupCoordinator 聚合: 废片 + 相似多余 + 连拍多余 + 大视频
- [ ] 生成清理方案预览 (分类展示 + 总可释放空间)
- [ ] "一键清理"按钮 → 系统确认 → 执行 → 结果报告
- [ ] 清理结果动画 (显示释放了多少空间)

### 2.4 StoreKit 2 订阅
- [ ] 定义产品 ID: `com.huge.albumslim.monthly` / `.yearly` / `.lifetime`
- [ ] App Store Connect 配置订阅组
- [ ] 付费墙 UI (PaywallView)
  - 功能对比表
  - 推荐年订阅
  - 恢复购买
- [ ] 功能限制逻辑
  - 免费: 废片检测限清理20张，相似照片展示前3组
  - Pro: 解锁全部
- [ ] 订阅状态持久化 (Transaction.currentEntitlements)

### 2.5 关键技术文件

| 任务 | 涉及文件 |
|---|---|
| 截图 OCR | `Services/OCRService.swift`, `ViewModels/ScreenshotViewModel.swift`, `Views/Screenshot/ScreenshotListView.swift` |
| 截图导出 | `Services/NotesExportService.swift` |
| 视频建议 | 新建 `Services/VideoAnalysisService.swift`, `ViewModels/VideoManagerViewModel.swift` |
| 一键清理 | `Services/CleanupCoordinator.swift`, 新建 `Views/Dashboard/QuickCleanView.swift` |
| 订阅系统 | 新建 `Services/SubscriptionService.swift`, `Views/Settings/PaywallView.swift` |

---

## Phase 3: 增长优化

> 目标: 提升留存、扩大用户获取

### 3.1 性能优化
- [ ] 大相册 (10000+ 张) 扫描速度优化
  - 首次扫描结果缓存到 SwiftData (CachedAnalysis)
  - 增量扫描: 只分析新增资源 (PHChange 监听)
  - autoreleasepool 包裹批处理循环
- [ ] 相似度计算优化: 特征向量序列化缓存
- [ ] 视频压缩队列: 后台处理 + 本地通知完成

### 3.2 Widget + 提醒
- [ ] WidgetKit 小组件: 存储空间状态环形图
- [ ] UNUserNotificationCenter: 每周/月清理提醒
- [ ] 提醒文案: "您的相册本周增长了 X，建议清理"

### 3.3 社交化
- [ ] 清理成就系统 (累计 1GB/5GB/10GB 解锁)
- [ ] 分享卡片生成 ("我用相册瘦身释放了 X 空间")
- [ ] App Store 评价引导 (SKStoreReviewController)

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
| SwiftData 缓存 | 高 | CachedAnalysis 模型已定义但未使用，需在分析流程中集成 |
| 增量扫描 | 高 | 当前每次全量扫描，需监听 PHChange 做增量 |
| 质量评分优化 | 中 | qualityScore 可用 VNCalculateImageAestheticsScoresRequest (iOS 18+) |
| VNFeaturePrint 距离 | 中 | computeDistance 返回的是欧氏距离不是余弦距离，阈值需真机校准 |
| 错误处理 | 中 | 部分 try? 需要改为 proper error handling + 用户提示 |
| 并发严格性 | 低 | 当前 targeted，后续可升级为 complete |
| 单元测试 | 低 | Services 层需要测试覆盖 |
