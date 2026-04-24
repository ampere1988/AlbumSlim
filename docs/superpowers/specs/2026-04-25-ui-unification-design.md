# AlbumSlim 跨模块 UI 统一化设计

**日期**：2026-04-25
**状态**：设计阶段（待用户审查）

## 1. 背景

AlbumSlim 经过多阶段迭代（MVP → P1 → P2 → 首页改版）后，5 大 Tab 之间的 UI 细节已产生明显不一致：批量选择有 3 套交互、删除确认弹窗有 5 种标题格式、同一语义用了 2-3 个不同 SF Symbol、术语混用（清除/清理/清空/释放/可省）、触觉反馈与 Toast 散乱。本设计在不做视觉重绘的前提下，建立一套全局规范并落地，消除这些不一致。

## 2. 目标与非目标

**目标**
- 建立跨模块统一的交互/视觉/文案规范
- 以"全局垃圾桶 + 软删除"取代当前"直删 + 双重确认"
- 所有模块接入统一的 Toast、Haptic、加载、空状态、按钮样式
- 以一批共享组件沉淀规范，避免后续再度偏离

**非目标**
- 不做视觉风格改版（继续 iOS 原生风格）
- 不引入下拉刷新、分页加载（当前数据量不需要）
- 不改 Shuffle 首页沉浸式浏览的交互（已是独立风格）
- 不调整 Tab 结构与模块划分

## 3. 核心决策

### 3.1 批量选择：统一为"编辑模式"

**交互规范**（对齐 iOS 系统相册）：

- 列表默认状态：只显示内容，**不显示勾选框**
- 右上 toolbar 按钮：`选择` → 进入编辑模式
- 编辑模式下：
  - 列表项显示勾选圈（未选 `circle` / 选中 `checkmark.circle.fill`）
  - 右上 toolbar 按钮：`完成` → 退出
  - 左上 toolbar 按钮：`全选` / `取消全选`
  - 底部出现 action bar（safeAreaInset + .ultraThinMaterial）
  - 中间或底部显示计数：`已选 X 项`
  - 导航栏 `navigationBarTitleDisplayMode` 切换为 `.inline`
- 列表行 swipe action（trailing）：`移到垃圾桶`（不需进入编辑模式即可单项删除）
- 长按 contextMenu：`移到垃圾桶` / 其他查看类操作

**影响模块**：
- 需要改造：相似照片、废片、连拍、超大照片（当前无编辑模式，直接在 List 里显示全选）
- 保持现状并微调：视频列表、截图、垃圾桶（已有编辑模式，统一计数文案）

### 3.2 删除机制：全局垃圾桶（软删除）

**数据层**：

新增 `TrashedItem` SwiftData 模型：
```
- id: UUID
- assetLocalIdentifier: String（PHAsset 唯一 ID）
- sourceModule: TrashSource（.similar/.waste/.burst/.largePhoto/.video/.screenshot/.shuffle/.other）
- movedAt: Date
- mediaType: MediaType（photo/video/livePhoto/screenshot）
- thumbnailData: Data?（缓存缩略图，避免 asset 被系统清理后无法预览）
- byteSizeSnapshot: Int64（放入时的大小，用于显示"可释放"）
```

新增 `TrashService`：统一管理 TrashedItem 的增删查，注入到 `AppServiceContainer`。

**UI 层**：

- 所有模块的"删除"操作改为 `TrashService.moveToTrash(assets:source:)`
- "移到垃圾桶" **无弹窗确认**（已是软操作，用户可随时恢复）
- 触发后：`.medium` haptic + Toast `已移到垃圾桶 X 项`
- **全局隐藏规则**：只要 asset 在 TrashedItem 表中存在（任一 source），**所有模块列表都过滤掉它**。这样避免"以为删了但废片模块还在显示"的疑惑。

**入口**：

- 每个一级模块列表的 toolbar 右上角放 trash 图标按钮：
  - icon：`trash`
  - badge：当 `TrashService.count > 0` 时显示数字（通过 overlay 小红点数字）
  - 点击打开同一个 `GlobalTrashView`（全局垃圾桶视图）
- 设置页顶部也提供一个入口条目
- 所有入口打开的都是**同一个全局垃圾桶**，不按来源模块分栏展示（列表里每条标注来源标签，用户仍能看到照片来自哪个清理模块）

**全局垃圾桶视图 `GlobalTrashView`**：

- 列表按 `movedAt` 倒序，显示缩略图 + 来源模块标签 + 放入时间 + 大小
- 默认浏览模式，右上角 `选择` 进入编辑模式（与其他模块交互一致）
- 编辑模式下底部 action bar：
  - 次要：`恢复 X 项`（.bordered, .tint(.blue)）— 从 TrashedItem 移除，不做系统删除
  - 主要：`永久删除 X 项`（.borderedProminent, .tint(.red)）— 弹确认 → 调用 `PHPhotoLibrary.deleteAssets` → iOS 系统会再弹一次权限确认
- 非编辑模式下 toolbar 提供 `全部清空` 菜单项（确认后永久删除全部）
- 永久删除确认弹窗（iOS 风格 A）：
  - 标题：`永久删除 X 项？`
  - Message：`此操作无法撤销，相册中将同时移除这些项`
  - 按钮：`永久删除`（destructive） / `取消`
  - 引号统一 `「」`
  - 触觉：`.heavy` impact + `.warning` notification
  - 成功后：Toast `已永久删除 X 项，释放 XX MB`

**PHChange 同步**：

`TrashService` 监听 `PHPhotoLibraryChangeObserver`：asset 在系统相册被删除/丢失时，自动从 TrashedItem 表中剔除对应记录（避免出现无效 asset 占位）。

**旧数据迁移**：

- 当前截图模块已有 `isInTrash` 字段（SwiftData 或本地状态）
- 启动时一次性迁移：所有 `isInTrash == true` 的截图 → 写入 `TrashedItem(sourceModule: .screenshot)`
- 旧 `isInTrash` 字段废弃
- 之前（改造前）通过 PHPhotoLibrary 直接删除的项已在 iOS 系统"最近删除"里，App 无法追溯，不做处理

### 3.3 术语表

| 概念 | 统一用 | 废弃 |
|---|---|---|
| 软删除（进垃圾桶） | **移到垃圾桶** | 删除、移除、放入垃圾桶、移入垃圾桶 |
| 垃圾桶中的真正删除 | **永久删除** | 彻底删除、完全删除 |
| 恢复 | **恢复** | 撤销、还原 |
| 节省空间 | **可释放 X MB** | 可省、释放空间、可清理 |
| 操作完成（软删除） | **已移到垃圾桶** | 删除成功 |
| 操作完成（永久删除） | **已永久删除** | 清理完成 |
| 编辑入口 | **选择** → **完成** | 多选、批量选择、管理 |
| 选中计数 | **已选 X 项** | X 张 / X 个 / X / Y |
| 空状态 | **没有 X** | 未发现 / 暂无 |
| 加载中 | **加载中…** | 正在加载 |
| 扫描中 | **扫描中…** | 正在扫描 / 分析中 |
| 分析中 | **分析中…** | 正在分析 |
| 压缩中 | **压缩中…** | 正在压缩 |
| 识别中 | **识别中…** | 正在识别 |
| 量词 | **项**（统一） | 张 / 个 / 条 |

引号：统一用 `「」`，不用 `""`。

### 3.4 SF Symbol 标准表

**模块语义图标**：

| 语义 | 标准图标 |
|---|---|
| 相似照片 | `square.on.square` |
| 废片 | `photo.badge.exclamationmark` |
| 连拍 | `square.stack.3d.up.fill` |
| 超大照片 | `photo.badge.plus` |
| 截图 | `camera.viewfinder`（原 `scissors` 废弃） |
| 视频 | `video.fill` |

**通用动作图标**：

| 语义 | 标准图标 |
|---|---|
| 删除（移到垃圾桶） | `trash` |
| 永久删除 | `trash.fill` + 红色 |
| 垃圾桶入口（toolbar） | `trash` + badge |
| 恢复 | `arrow.uturn.backward` |
| 选择 | 文字"选择" |
| 全选 | 文字"全选" / "取消全选" |
| 完成 | 文字"完成" |
| 收藏 | `heart` / `heart.fill` |
| 分享 | `square.and.arrow.up` |
| 更多 | `ellipsis` |
| 关闭（sheet） | `xmark.circle.fill` |
| 信息 | `info.circle` |
| 设置 | `gearshape.fill` |
| 扫描 | `sparkles.magnifyingglass` |
| 压缩 | `rectangle.compress.vertical` |
| OCR 识别 | `text.viewfinder` |
| 成就 | `trophy.fill` |
| Pro 标识 | `crown.fill` |

图标常量沉淀到 `Utils/AppIcons.swift`，所有模块通过常量引用，禁止散落硬编码。

### 3.5 按钮样式

统一的 button role 规范：

**主要操作**（底部 action bar）：
- `.borderedProminent` + `.controlSize(.large)`
- 删除/永久删除：`.tint(.red)` + `role: .destructive`
- 压缩/恢复/保存：`.tint(.blue)`
- 位置：`safeAreaInset(edge: .bottom)`，背景 `.ultraThinMaterial`
- 文字格式：`{动作} {数量} 项`（例如"恢复 3 项"）

**次要操作**（与主要并排）：
- `.bordered` + `.controlSize(.large)`
- 默认 tint

**行内操作**（列表行内小按钮）：
- `.plain` + 前置 SF Symbol
- 语义色（删除用 `.red`，其他用 `.primary`）

**Toolbar 按钮**：
- 纯文字按钮（"选择"、"完成"、"全选"）：使用默认样式
- 图标按钮（垃圾桶入口、分享）：使用默认样式

沉淀到 `Utils/ButtonStyles.swift` 或 View extension。

### 3.6 Toast 反馈（新增统一组件）

新增 `Views/Common/AppToast.swift`：
- 底部浮层，距底部 ~100pt
- 圆角胶囊 + `.ultraThinMaterial` 背景
- SF Symbol + 文案
- 1.5 秒自动消失
- 使用方式：`services.toast.show(.success("已移到垃圾桶 3 项"))`（通过新增的 `ToastCenter` 中心化管理）

标准 Toast 文案：
- 移到垃圾桶：`已移到垃圾桶 X 项`（图标 `trash`）
- 恢复：`已恢复 X 项`（图标 `arrow.uturn.backward`）
- 永久删除：`已永久删除 X 项，释放 XX MB`（图标 `checkmark.circle.fill`）
- 压缩完成：`已压缩，节省 XX MB`（图标 `checkmark.circle.fill`）
- 识别记录保存：`已保存`（现有实现迁移到此）
- 复制：`已复制到剪贴板`（现有实现迁移到此）

### 3.7 触觉反馈（Haptic）

新增 `Utils/Haptics.swift` 统一封装：

| 场景 | 反馈 |
|---|---|
| 普通按钮点击 | `.light` impact |
| 选中/取消选中单项 | `.selection` |
| 移到垃圾桶 | `.medium` impact |
| 永久删除 | `.heavy` impact + `.warning` notification |
| 操作成功（Toast 配套） | `.success` notification |
| Pro 门槛触发 | `.warning` notification |
| 恢复 | `.light` impact |

所有关键操作全部接入，不再只有 Shuffle 有反馈。

### 3.8 加载 / 空状态 / 进度

**空状态**：统一 `ContentUnavailableView`
- 标题：`没有 X`
- systemImage：对应模块统一图标
- description：一句简短引导或触发扫描说明
- 主操作按钮：放在 actions 参数里（例如"开始扫描"）

**简单加载**：
```swift
VStack(spacing: 12) {
    ProgressView()
    Text("加载中…").foregroundStyle(.secondary)
}
```

**带进度的加载**：
```swift
VStack(spacing: 8) {
    ProgressView(value: progress, total: 1.0)
    Text("\(phase) \(Int(progress*100))%").foregroundStyle(.secondary)
}
```

- phase 文案使用统一术语（扫描中/分析中/识别中/压缩中）
- 进度 0-1 归一化

封装为 `Views/Common/LoadingState.swift`。

### 3.9 Pro 门槛

- 统一使用 `PaywallView` sheet（废弃相似照片里的 overlay "升级 Pro" 按钮）
- 触发时：`.warning` haptic
- 所有模块 Pro 检查通过 `services.subscription.isPro` 判断
- 文案：需要 Pro 时，Toast 或 paywall 内统一为 `此功能需要 Pro`

### 3.10 导航栏

- 所有一级列表：默认 `.navigationBarTitleDisplayMode` 为系统默认（large）
- 进入编辑模式时：切换为 `.inline`（更多空间给 toolbar）
- 详情页 sheet：`.inline`
- 统一不使用自定义返回按钮，依赖 NavigationStack 默认

## 4. 架构改动

### 4.1 新增文件

```
AlbumSlim/
├── Models/
│   └── TrashedItem.swift                    # SwiftData 模型
├── Services/
│   └── TrashService.swift                   # 全局垃圾桶服务
├── Views/
│   ├── Trash/
│   │   └── GlobalTrashView.swift            # 全局垃圾桶 View
│   └── Common/
│       ├── AppToast.swift                   # Toast 组件 + ToastCenter
│       ├── LoadingState.swift               # 统一加载视图
│       ├── EmptyState.swift                 # 统一空状态 wrapper
│       ├── SelectionToolbar.swift           # 编辑模式 toolbar 封装
│       ├── TrashToolbarButton.swift         # toolbar trash + badge
│       ├── ActionBar.swift                  # 底部 action bar 容器
│       └── ConfirmDialog.swift              # 永久删除确认对话框 wrapper
└── Utils/
    ├── AppIcons.swift                       # SF Symbol 常量
    ├── AppStrings.swift                     # 文案常量（术语表沉淀）
    ├── ButtonStyles.swift                   # 按钮样式 extension
    └── Haptics.swift                        # 触觉反馈统一封装
```

### 4.2 修改文件

**重构类**（接入新规范）：
- `Services/PhotoLibraryService.swift`：所有 `deleteAssets` 调用路径改为通过 `TrashService.moveToTrash`；真正的 `deleteAssets` 只在 `TrashService.permanentlyDelete` 内部使用
- `App/AppServiceContainer.swift`：注册 `TrashService` 和 `ToastCenter`
- `ViewModels/ScreenshotListViewModel`（如有）：迁移 `isInTrash` 到 `TrashService`
- 所有模块 ViewModel：删除逻辑改为调用 `TrashService.moveToTrash(...)`

**影响 View 文件**（接入新规范）：
- `Views/MainTabView.swift`：Tab icon 使用 `AppIcons` 常量
- `Views/Shuffle/ShuffleFeedView.swift`：删除改为移到垃圾桶，接入 Toast
- `Views/Video/VideoListView.swift`：文案/按钮/toolbar 统一
- `Views/Video/VideoSuggestionsView.swift`：同上
- `Views/Video/VideoCompressView.swift`：删除改软删除，文案统一
- `Views/Photo/LargePhotosView.swift`：改造编辑模式 + 接入新规范
- `Views/Photo/SimilarPhotosView.swift`：改造编辑模式 + 废弃 overlay Pro 门槛 + 接入新规范
- `Views/Photo/WastePhotosView.swift`：改造编辑模式 + 接入新规范
- `Views/Photo/BurstPhotosView.swift`：改造编辑模式 + 接入新规范
- `Views/Screenshot/ScreenshotListView.swift`：文案/按钮统一；旧 TrashView 逻辑迁移
- `Views/Screenshot/ScreenshotDetailView.swift`：Toast 迁移到统一组件
- `Views/Screenshot/TrashView.swift`：**废弃**（由 GlobalTrashView 取代），代码保留作参考后删除
- `Views/Settings/SettingsView.swift`：新增全局垃圾桶入口条目
- `Views/QuickCleanView.swift`：图标/文案统一
- `Views/OverviewSection.swift`：文案统一

### 4.3 数据迁移

App 启动时在 `AppServiceContainer.init` 或专用 migrator 中：
1. 检查是否存在旧截图 `isInTrash` 字段数据
2. 若有，为每条创建 `TrashedItem(sourceModule: .screenshot, movedAt: 迁移时刻)`
3. 清除旧字段或标记"已迁移"

## 5. 边界情况处理

- **asset 已被系统相册删除**：PHChange 触发时 `TrashService` 自动从 TrashedItem 表清理
- **asset 被系统相册修改但未删除**：不影响 TrashedItem 关联（保持 localIdentifier 不变）
- **照片在多个分析模块都命中**（例如相似+废片）：放入垃圾桶时只记录一次（按 assetLocalIdentifier 去重），sourceModule 记录第一次触发的模块
- **垃圾桶中 asset 被系统「最近删除」清空**：30 天后 iOS 自动清理，PHChange 会通知，App 从 TrashedItem 表移除
- **从垃圾桶恢复的 asset**：只是把 TrashedItem 记录删除，asset 本身一直在系统相册里未动
- **软删除时 asset 大小获取失败**：`byteSizeSnapshot` 设 0，显示"可释放 --"

## 6. 测试要点

由于项目现状没有 UI 测试框架，验证方式以**xcodebuild build** 编译通过 + 手动模拟器验证为主：

- 编译通过（严格并发 `SWIFT_STRICT_CONCURRENCY = targeted`）
- 5 大 Tab 每个都能进入编辑模式、选中、底部 action bar 正常
- 软删除流程：列表项减少 → 垃圾桶 badge +1 → 进垃圾桶能看到 → Toast 出现
- 恢复流程：垃圾桶项消失 → 原模块重新出现
- 永久删除流程：确认对话框 → 系统权限弹窗 → 最终消失
- PHChange 同步：在系统相册 app 删除一张 App 垃圾桶里的照片，回 App 时该项应消失
- 跨模块隐藏规则：废片+相似同时命中时，任一模块放入垃圾桶，另一模块也隐藏
- 旧截图 `isInTrash` 数据启动后迁移到 TrashedItem

## 7. 实施顺序建议

本次改造量大，需要拆解并可并行。大致分 3 波：

**Wave 1（基础设施，必须先做）**
- TrashedItem 模型 + TrashService + 迁移逻辑
- AppIcons / AppStrings / Haptics / ButtonStyles 工具类
- AppToast / LoadingState / EmptyState / ConfirmDialog / ActionBar / SelectionToolbar / TrashToolbarButton 共享组件
- GlobalTrashView 视图
- AppServiceContainer 注册新服务

**Wave 2（模块接入，可并行）**
- 视频 Tab 三视图（列表 / 建议 / 压缩）
- 照片 Tab 四视图（相似 / 废片 / 连拍 / 超大）
- 截图 Tab（列表 / 详情），迁移旧 TrashView 数据
- Shuffle 首页
- 设置 Tab + 快速扫描 + 概览

**Wave 3（收尾）**
- 废弃旧 `Views/Screenshot/TrashView.swift`
- 全局搜索废弃文案/图标/硬编码，确认替换到常量
- 编译 + 手工验证
- git 提交

## 8. 风险

- **改造面广**：涉及 ~20+ 文件，需要仔细逐一接入，避免遗漏
- **软删除逻辑渗透到所有 filter**：所有"列表加载"都要过滤 TrashedItem 中的 asset，遗漏会导致"删了但仍显示"
- **PHChange 观察者多重复**：TrashService 自己监听 + PhotoLibraryService 已有监听，需要协调避免循环触发
- **照片模块编辑模式改造**：当前是 List+"全选"常驻，改为 toolbar 编辑模式，会触碰 ViewModel 选中状态管理
- **Swift 6 并发**：TrashService 作为 `@MainActor @Observable`，PHChange 回调线程切换要小心（参考 project_swift6_actor_pitfall 记忆）

## 9. 范围外（不在本次改造中）

- 下拉刷新 / 分页加载
- Widget 的垃圾桶展示
- 深色模式单独优化（保持系统自适应）
- 多语言（当前仅中文）
- 辅助功能（VoiceOver 等）的统一适配

## 10. 后续

设计确认后 → `writing-plans` 技能产出详细实施计划（Wave 拆解为具体任务、文件清单、验证点），并可由 agent 团队并行推进。
