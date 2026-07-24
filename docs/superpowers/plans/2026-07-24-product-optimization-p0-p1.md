# 产品优化 P0+P1 实施计划(付费模式不变)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复已建成但断线的增长/变现组件(Widget、评分、成就、分享),堵住 Pro 门控漏洞,强化清理反馈与召回闭环——不改变付费模式。

**Architecture:** 全部为现有 MVVM + AppServiceContainer 架构内的接线与小改造,无新服务;成就记账口径统一收敛到"永久删除"时点;QuickClean 改为可全局 present 的 sheet 以支撑通知深链与首页导流。

**Tech Stack:** Swift 6 / SwiftUI / iOS 17+ / StoreKit 2 / WidgetKit / UserNotifications / XcodeGen

## Global Constraints

- **付费模式不改**:价格、产品 ID `com.hao.doushan.pro.lifetime`、`ProFeatureGate.canClean(isPro:) -> isPro` 的二元语义均保持不变;只堵漏洞,不加免费额度。
- 所有 `@Observable` 类标 `@MainActor`;Photos 操作走 `PHPhotoLibrary.shared().performChanges` 异步。
- 用户可见字符串一律 `String(localized:)` 或 SwiftUI 自动本地化;**新增字符串的英文翻译统一在 Task 9 补齐**,前面任务只写中文源文案。
- 每个任务完成后必须执行:`xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`,构建通过才能 commit。
- git commit 消息用中文。
- App Group ID 固定为 `group.com.hao.doushan`,Widget 读取 key 固定为 `StorageStatsCache`(见 `AlbumSlimWidget/SharedStorageStats.swift:4-5`)。
- 任务实施前**先 Read 任务列出的每个文件**,以实际代码为准适配锚点(下述行号为写计划时快照)。

---

### Task 1: Widget 数据管线修复

**问题:** 主 app 把 `StorageStats` 写进 `UserDefaults.standard`(`AlbumSlim/Models/StorageStats.swift:36`),Widget 从 App Group `group.com.hao.doushan` 读 `StorageStatsCache`(`AlbumSlimWidget/SharedStorageStats.swift`),且全仓库无 `WidgetCenter.reloadAllTimelines()`——Widget 永远显示占位态。

**Files:**
- Modify: `AlbumSlim/Models/StorageStats.swift`
- Read first: `AlbumSlimWidget/SharedStorageStats.swift`(确认 Widget 端解码字段与 `StorageStats` 的 CodingKeys 完全对齐;如字段名不一致,以主 app 为准修改 Widget 端)
- Test: `AlbumSlimTests/StorageStatsTests.swift`

**Interfaces:**
- Produces: `StorageStats.save()` 同时写 standard 与 App Group suite 并刷新 Widget timeline;`StorageStats.appGroupID = "group.com.hao.doushan"`。

- [ ] **Step 1: 写失败测试**(追加到 `AlbumSlimTests/StorageStatsTests.swift`)

```swift
func testSaveWritesToAppGroupSuite() throws {
    var stats = StorageStats()
    stats.photoSize = 123
    stats.save()
    let suite = try XCTUnwrap(UserDefaults(suiteName: StorageStats.appGroupID))
    let data = try XCTUnwrap(suite.data(forKey: "StorageStatsCache"))
    let decoded = try JSONDecoder().decode(StorageStats.self, from: data)
    XCTAssertEqual(decoded.photoSize, 123)
}
```

- [ ] **Step 2: 运行测试确认失败**(`appGroupID` 不存在,编译失败即为预期失败)

- [ ] **Step 3: 实现**——修改 `StorageStats.swift` 的缓存段:

```swift
import WidgetKit

// MARK: - 缓存

static let appGroupID = "group.com.hao.doushan"
private static let cacheKey = "StorageStatsCache"

func save() {
    guard let data = try? JSONEncoder().encode(self) else { return }
    UserDefaults.standard.set(data, forKey: Self.cacheKey)
    // Widget 从 App Group 容器读取,写完后刷新 timeline
    UserDefaults(suiteName: Self.appGroupID)?.set(data, forKey: Self.cacheKey)
    WidgetCenter.shared.reloadAllTimelines()
}
```

注意:`import WidgetKit` 加到文件顶部;模拟器单测环境 `WidgetCenter` 调用无副作用,安全。

- [ ] **Step 4: 对齐 Widget 端解码**——Read `AlbumSlimWidget/SharedStorageStats.swift`,确认其 Codable 字段名与 `StorageStats` 的 CodingKeys(totalPhotoCount/totalVideoCount/totalScreenshotCount/totalBurstCount/totalLivePhotoCount/photoSize/videoSize/screenshotSize/estimatedSavable/lastAnalyzedAt)一致且均为 optional-tolerant;不一致则修 Widget 端。

- [ ] **Step 5: 构建 + 跑测试通过,commit**

```bash
git add -A && git commit -m "修复 Widget 数据管线: StorageStats 写入 App Group + 刷新 timeline"
```

---

### Task 2: 订阅体验修复(恢复购买反馈 + isPro 冷启动缓存)

**问题:** `restorePurchases()` 成功/失败均无提示;`isPro` 默认 false、异步校验前已付费用户会短暂看到锁定 UI。

**Files:**
- Modify: `AlbumSlim/Services/SubscriptionService.swift`
- Modify: `AlbumSlim/Views/Settings/PaywallView.swift:132-133`(恢复购买按钮)
- Modify: `AlbumSlim/Views/Settings/SettingsView.swift:112-113`(恢复购买按钮)

**Interfaces:**
- Produces: `func restorePurchases() async -> Bool`(返回恢复后是否为 Pro);`isPro` 初始值来自 UserDefaults 缓存 key `"cachedIsPro"`。

- [ ] **Step 1: 改 SubscriptionService**

```swift
var isPro: Bool = UserDefaults.standard.bool(forKey: "cachedIsPro")

@discardableResult
func restorePurchases() async -> Bool {
    isLoading = true
    defer { isLoading = false }
    try? await AppStore.sync()
    await checkSubscriptionStatus()
    return isPro
}

func checkSubscriptionStatus() async {
    var hasPro = false
    for await result in Transaction.currentEntitlements {
        if let transaction = try? checkVerified(result) {
            if transaction.productID == Self.productID {
                hasPro = true
            }
        }
    }
    isPro = hasPro
    UserDefaults.standard.set(hasPro, forKey: "cachedIsPro")
}
```

- [ ] **Step 2: 两处恢复购买按钮加 toast 反馈**(PaywallView 内如无 `services`,用其已有的 `subscription` 环境对象,toast 通过 `@Environment(AppServiceContainer.self)` 获取;两处逻辑相同):

```swift
Button("恢复购买") {
    Task {
        let restored = await services.subscription.restorePurchases()
        if restored {
            services.toast.show(icon: AppIcons.checkmarkCircleFill, text: String(localized: "已恢复 Pro 权益"), tint: .green)
        } else {
            services.toast.failure(String(localized: "未找到可恢复的购买"))
        }
    }
}
```

注意:PaywallView 以 sheet 形式弹出,`AppToast` 挂在 MainTabView 根部,sheet 之下可能被遮挡——若验证发现 toast 不可见,改为在 PaywallView 内用 `.alert` 呈现同样文案。

- [ ] **Step 3: 构建通过,commit**

```bash
git add -A && git commit -m "订阅体验: 恢复购买结果反馈 + isPro 冷启动缓存"
```

---

### Task 3: Pro 门控堵漏(3 处)

**问题:** 免费用户可绕过付费墙:①视频清理建议批量删除 ②截图详情页删除 ③截图详情页 OCR(Paywall 明列 OCR 为 Pro 卖点)。**本任务是执行既有付费模式,不是改模式。**

**Files:**
- Modify: `AlbumSlim/Views/Video/VideoSuggestionsView.swift`(destructive 按钮,约 :51)
- Modify: `AlbumSlim/Views/Screenshot/ScreenshotDetailView.swift`(`handleTrashCurrent` 约 :192、`handleOCRButtonTap` 约 :152)
- 参照模式: `AlbumSlim/Views/Video/VideoListView.swift:40`(既有门控写法)、`AlbumSlim/Views/Shuffle/ShuffleFeedView.swift:203`

**Interfaces:**
- Consumes: `ProFeatureGate.canClean(isPro:)`、`services.subscription.isPro`、`PaywallView`。

- [ ] **Step 1: VideoSuggestionsView**——给 destructive 按钮加门控。文件顶部加 `@State private var showPaywall = false`,按钮 action 开头加:

```swift
guard ProFeatureGate.canClean(isPro: services.subscription.isPro) else {
    showPaywall = true
    return
}
```

body 末尾(与 `.sheet(isPresented: $showTrash)` 并列)加:

```swift
.sheet(isPresented: $showPaywall) { PaywallView() }
```

(先 Read 其他挂 PaywallView 的视图确认其初始化参数写法,保持一致。)

- [ ] **Step 2: ScreenshotDetailView**——同样加 `@State private var showPaywall = false` + `.sheet`;`handleTrashCurrent()` 与 `handleOCRButtonTap()` 函数体开头各加同样的 guard。

- [ ] **Step 3: 手工验证逻辑**——检查三处:非 Pro 路径全部 `return` 且不执行任何删除/识别副作用。

- [ ] **Step 4: 构建通过,commit**

```bash
git add -A && git commit -m "Pro 门控堵漏: 视频建议批量删除/截图详情删除/OCR 补齐 isPro 检查"
```

---

### Task 4: 软删除反馈统一(toast 带体积 + 撤销按钮)

**问题:** 软删除 toast 只报数量不报体积,无撤销按钮;撤销要跨 tab 找垃圾桶。同时移除两处口径错误的成就记账(记账重构在 Task 5)。

**Files:**
- Modify: `AlbumSlim/Services/TrashService.swift`(`moveToTrash` 返回批次信息)
- Modify: `AlbumSlim/Services/ToastCenter.swift`(ToastMessage 支持 action;`movedToTrash` 带体积与撤销)
- Modify: `AlbumSlim/Views/Common/AppToast.swift`(渲染 action 按钮;先 Read 现有实现)
- Modify: `AlbumSlim/Utils/AppStrings.swift:31`(`movedToTrash` 带体积)
- Modify 全部 8 个软删除调用点: `ShuffleFeedView.swift`(~:209,并**删除 :216 的 `recordCleanup`**)、`LargePhotosView.swift`(~:82,并**删除 :81 的 `recordCleanup`**)、`SimilarPhotosView.swift`、`WastePhotosView.swift`、`BurstPhotosView.swift`(~:134)、`VideoListView.swift`(两处)、`ScreenshotListView.swift`(~:72)、`VideoSuggestionsView.swift`(~:59)、`ScreenshotDetailView.swift`(~:202)
- Test: `AlbumSlimTests/TrashServiceFilterTests.swift`(追加返回值断言)

**Interfaces:**
- Produces:
  - `@discardableResult func moveToTrash(assets: [PHAsset], source: TrashSource, mediaType: TrashedMediaType) -> (ids: Set<String>, totalSize: Int64)`
  - `ToastCenter.movedToTrash(_ count: Int, freed: Int64, onUndo: @escaping () -> Void)`
  - `ToastMessage` 增加 `let actionLabel: String?` 与 `let action: (() -> Void)?`(Equatable 按 id 比较)。

- [ ] **Step 1: 失败测试**(追加到 TrashServiceFilterTests):

```swift
func testMoveToTrashReturnsBatchInfo() {
    let service = TrashService()
    let result = service.moveToTrash(assets: [], source: .waste, mediaType: .photo)
    XCTAssertTrue(result.ids.isEmpty)
    XCTAssertEqual(result.totalSize, 0)
}
```

- [ ] **Step 2: TrashService.moveToTrash 改造**

```swift
@discardableResult
func moveToTrash(assets: [PHAsset], source: TrashSource, mediaType: TrashedMediaType) -> (ids: Set<String>, totalSize: Int64) {
    let now = Date()
    let existingIDs = trashedAssetIDs
    let newItems: [TrashedItem] = assets.compactMap { asset in
        guard !existingIDs.contains(asset.localIdentifier) else { return nil }
        let bytes = asset.estimatedByteSize
        return TrashedItem(
            id: asset.localIdentifier, fileSize: bytes,
            creationDate: asset.creationDate, trashedDate: now,
            sourceModule: source, mediaType: mediaType
        )
    }
    guard !newItems.isEmpty else { return ([], 0) }
    trashedItems.insert(contentsOf: newItems, at: 0)
    lastChangeKind = .insert
    persist()
    return (Set(newItems.map(\.id)), newItems.reduce(0) { $0 + $1.fileSize })
}
```

- [ ] **Step 3: ToastMessage/ToastCenter/AppToast 支持 action**

```swift
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
    let tint: Color
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
```

`ToastCenter.show` 加可选参数 `actionLabel: String? = nil, action: (() -> Void)? = nil`(带 action 的 toast duration 默认 3.5 秒);语义封装改为:

```swift
func movedToTrash(_ count: Int, freed: Int64, onUndo: @escaping () -> Void) {
    show(
        icon: AppIcons.trash,
        text: AppStrings.movedToTrash(count, freed: freed),
        duration: 3.5,
        actionLabel: String(localized: "撤销"),
        action: onUndo
    )
}
```

`AppStrings.movedToTrash` 改为:

```swift
static func movedToTrash(_ count: Int, freed: Int64) -> String {
    freed > 0
        ? String(localized: "已移到垃圾桶 \(count) 项 · 可释放 \(freed.formattedFileSize)")
        : String(localized: "已移到垃圾桶 \(count) 项")
}
```

`AppToast` 视图在文本右侧渲染 action 按钮(点击执行 `action()` 并立即消掉当前 toast——给 ToastCenter 加 `func dismissCurrent()` 调 `advance()`)。

- [ ] **Step 4: 改造全部调用点为统一模式**(以 ShuffleFeedView 为例,其余同构;顺手删除 ShuffleFeedView:216 与 LargePhotosView:81 的 `recordCleanup` 调用):

```swift
let batch = services.trash.moveToTrash(assets: assets, source: .shuffle, mediaType: mediaType)
Haptics.moveToTrash()
services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
    services?.trash.restore(batch.ids)
    services?.toast.restored(batch.ids.count)
}
```

注意各视图删除后本地数组的剔除逻辑保持不变;撤销后依赖各视图已有的 `onChange(of: trashedItems.count)` 监听自动刷新列表(Read 每个调用点确认该监听存在,ShuffleFeedView 用 `filterTrashedItems` 路径需确认恢复也会触发重载,若不会则在 undo 闭包中补发已有的刷新通知)。

- [ ] **Step 5: 跑全部测试 + 构建通过,commit**

```bash
git add -A && git commit -m "软删除反馈统一: toast 显示可释放体积 + 内联撤销"
```

---

### Task 5: 成就/评分/分享闭环(记账口径修正 + 页面入口 + 解锁庆祝 + 评分接线 + 分享卡接线)

**问题:** `AchievementView` 无入口;解锁无反馈;记账只覆盖 2/8 入口且在软删时虚记;`ReviewPromptManager` 死代码;`ShareCardGenerator` 死代码。

**Files:**
- Modify: `AlbumSlim/Views/Trash/GlobalTrashView.swift`(永久删除成功处,先 Read 全文)
- Modify: `AlbumSlim/Views/Settings/SettingsView.swift`(usageStatsSection 加成就入口,约 :120-132)
- Modify: `AlbumSlim/Views/Settings/AchievementView.swift`(toolbar 加分享按钮,先 Read 全文)
- Consumes: `AchievementService.recordCleanup(freedSpace:deletedCount:) -> [Achievement]`、`ReviewPromptManager.requestReviewIfAppropriate()`、`ShareCardGenerator`(先 Read `AlbumSlim/Utils/ShareCardGenerator.swift` 与 `AlbumSlim/Views/Common/ShareCardView.swift` 确认生成 API 签名)

**Interfaces:**
- Produces: 成就记账唯一时点 = GlobalTrashView 永久删除成功后(freedSpace/deletedCount 取本次被删条目实际值);新解锁 → toast 庆祝;同一时点调用评分引导。

- [ ] **Step 1: GlobalTrashView 永久删除成功回调处**(在 `permanentlyDelete` 成功、`toast.permanentlyDeleted(...)` 附近),加:

```swift
let unlocked = services.achievement.recordCleanup(freedSpace: freedBytes, deletedCount: deletedCount)
for achievement in unlocked {
    services.toast.show(
        icon: achievement.icon,
        text: String(localized: "解锁成就:\(achievement.title)"),
        tint: .yellow,
        duration: 2.5
    )
}
ReviewPromptManager.requestReviewIfAppropriate()
```

`freedBytes` = 本次删除条目的 `fileSize` 之和(删除前从 `trashedItems` 过滤被选 ids 求和),`deletedCount` = ids 数。清空垃圾桶路径同样处理。

- [ ] **Step 2: SettingsView 成就入口**——usageStatsSection 内(或其后)加:

```swift
NavigationLink {
    AchievementView()
} label: {
    Label(String(localized: "清理成就"), systemImage: "trophy.fill")
}
```

(确认 SettingsView 在 NavigationStack 内;若不是,包一层或改用 sheet。)

- [ ] **Step 3: AchievementView 分享卡接线**——toolbar 加分享按钮,调用 `ShareCardGenerator` 生成图片后用 `ShareLink(item:preview:)` 或 `UIActivityViewController` 弹出(按 ShareCardGenerator 实际 API 适配;数据用 `services.achievement.totalFreedSpace / totalCleanupCount`)。

- [ ] **Step 4: 构建通过,commit**

```bash
git add -A && git commit -m "成就闭环: 记账收敛到永久删除 + 成就页入口/解锁庆祝 + 评分与分享卡接线"
```

---

### Task 6: QuickClean 入口提级 + 通知深链 + 动态提醒文案

**问题:** 智能扫描深埋 设置→存储概览;通知点击不落地、文案无收益数字。

**Files:**
- Modify: `AlbumSlim/Views/MainTabView.swift`(挂全局 sheet + 响应深链通知)
- Modify: `AlbumSlim/Views/Shuffle/ShuffleFeedView.swift`(顶部导流胶囊)
- Modify: `AlbumSlim/Services/ReminderService.swift`(动态文案)
- Modify: `AlbumSlim/App/AlbumSlimApp.swift`(通知 delegate)
- Create: `AlbumSlim/App/NotificationDelegate.swift`
- Read first: `AlbumSlim/Views/Dashboard/QuickCleanView.swift`(确认可独立 present;必要时包 NavigationStack)、`AlbumSlim/Views/Settings/OverviewSection.swift:35`(原入口保留)

**Interfaces:**
- Produces: `Notification.Name.openQuickClean`;点清理提醒通知 → 打开 QuickClean sheet;Shuffle 顶部胶囊同路径。

- [ ] **Step 1: NotificationDelegate**(新文件):

```swift
import UserNotifications
import Foundation

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.notification.request.identifier == "cleanup-reminder" {
            await MainActor.run {
                NotificationCenter.default.post(name: .openQuickClean, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let openQuickClean = Notification.Name("openQuickClean")
}
```

`AlbumSlimApp.init()` 里注册:`UNUserNotificationCenter.current().delegate = NotificationDelegate.shared`。

- [ ] **Step 2: MainTabView 挂全局 sheet**:

```swift
@State private var showQuickClean = false
// body 修饰符链上:
.onReceive(NotificationCenter.default.publisher(for: .openQuickClean)) { _ in
    showQuickClean = true
}
.sheet(isPresented: $showQuickClean) {
    NavigationStack { QuickCleanView() }
}
```

(若 QuickCleanView 依赖 push 上下文,按其实际实现调整;冷启动场景 post 早于订阅时,改用 delegate 里存 `UserDefaults` 标记 + MainTabView `.task` 检查消费,实施时任选一种可靠方案并验证。)

- [ ] **Step 3: Shuffle 顶部导流胶囊**——ShuffleFeedView 已授权且有内容时,顶部 overlay 一个半透明胶囊(读 `StorageStats.loadCached()?.estimatedSavable`,>100MB 才显示):

```swift
if let savable = StorageStats.loadCached()?.estimatedSavable, savable > 100 * 1024 * 1024 {
    Button {
        NotificationCenter.default.post(name: .openQuickClean, object: nil)
    } label: {
        Label(String(localized: "发现约 \(savable.formattedFileSize) 可清理"), systemImage: "sparkles")
            .font(.footnote.bold())
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
```

放置位置与沉浸式 UI 协调(顶部 safeArea 内、避开状态栏),点击后胶囊短暂隐藏本次会话可用 `@State` 控制。

- [ ] **Step 4: ReminderService 动态文案**——`scheduleReminder()` 中:

```swift
let content = UNMutableNotificationContent()
content.title = String(localized: "该清理相册了")
if let savable = StorageStats.loadCached()?.estimatedSavable, savable > 50 * 1024 * 1024 {
    content.body = String(localized: "闪图预估可为你释放约 \(savable.formattedFileSize),点开看看吧")
} else {
    content.body = String(localized: "您的相册可能积累了不少新照片，来看看有哪些可以清理吧")
}
content.sound = .default
```

- [ ] **Step 5: 构建通过 + 模拟器手工验证**(用 XcodeBuildMCP 装起 app:点 Shuffle 胶囊能弹出 QuickClean),commit

```bash
git add -A && git commit -m "QuickClean 入口提级: 全局 sheet + Shuffle 导流胶囊 + 通知深链与动态文案"
```

---

### Task 7: 扫描进度细化 + 可取消

**问题:** QuickClean 扫描时只显示"分析中… X%",`CleanupCoordinator.ScanPhase` 的细分文案已实现未展示;无取消按钮(底层支持断点续传)。

**Files:**
- Modify: `AlbumSlim/Views/Dashboard/QuickCleanView.swift`
- Read first: `AlbumSlim/ViewModels/QuickCleanViewModel.swift`、`AlbumSlim/Services/CleanupCoordinator.swift`(`scanPhase` 与扫描 Task 的取消语义、`ScanProgress` 断点续传)

**Interfaces:**
- Consumes: `CleanupCoordinator.scanPhase`(细分阶段文案)、扫描 Task 的 `Task.isCancelled` 检查点。
- Produces: QuickCleanViewModel 暴露 `func cancelScan()`(取消当前扫描 Task,保留已保存的 `ScanProgress`)。

- [ ] **Step 1:** QuickCleanViewModel 持有扫描 `Task` 引用,加 `cancelScan()`;扫描 UI 将 `ProgressLoadingState(phase:)` 的 phase 参数改为绑定协调器的 `scanPhase` 实际文案(如"检测废片…/查找相似照片…"),下方加次级"取消"按钮:取消后回到扫描前状态,再次进入可续传。

- [ ] **Step 2:** 模拟器手工验证:扫描中阶段文案会变化;点取消立即停止;重进从进度处续扫。

- [ ] **Step 3: 构建通过,commit**

```bash
git add -A && git commit -m "QuickClean 扫描体验: 展示细分阶段文案 + 支持取消续传"
```

---

### Task 8: 信任细节(.limited 扩容引导 + 永久删除文案如实化)

**Files:**
- Modify: `AlbumSlim/Views/MainTabView.swift`(permissionBanner 区域扩展 limited 分支)
- Modify: `AlbumSlim/Views/Trash/GlobalTrashView.swift`(confirmationDialog 文案,约 :69-108)

- [ ] **Step 1: .limited 引导横幅**——MainTabView `safeAreaInset` 中,`photoAuthStatus == .limited` 且非浏览 tab 时显示:

```swift
if selectedTab != 0, photoAuthStatus == .limited {
    limitedBanner
}
```

```swift
private var limitedBanner: some View {
    HStack(spacing: 10) {
        Image(systemName: "photo.badge.plus")
            .foregroundStyle(.blue)
        Text(String(localized: "仅可访问部分照片,扫描结果可能不完整"))
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Button(String(localized: "选择更多")) {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
            }
        }
        .font(.footnote.bold())
        .controlSize(.small)
    }
    .padding(.horizontal, 14).padding(.vertical, 8)
    .background(.thinMaterial)
}
```

需要 `import Photos`(已有)与 `import UIKit` 语义(SwiftUI 文件里 UIApplication 可用)。加一个 `@AppStorage("limitedBannerDismissed")` + 关闭按钮避免常驻打扰(可选,建议做:X 按钮置右)。

- [ ] **Step 2: 永久删除文案**——GlobalTrashView 的 confirmationDialog 描述从"此操作无法撤销"改为:

```swift
Text(String(localized: "照片将移入系统相册的「最近删除」,30 天内仍可在系统相册中找回"))
```

按钮文案保持破坏性语义(如"永久删除 X 项")。

- [ ] **Step 3: 构建通过,commit**

```bash
git add -A && git commit -m "信任细节: limited 权限扩容引导 + 永久删除文案如实说明系统最近删除"
```

---

### Task 9: 英文本地化补齐(收尾,必须最后执行)

**问题:** `Localizable.xcstrings` 中 28 条无英文(含付费墙核心文案"一次购买,终身使用"、"%@ 解锁 Pro"等),加上 Task 1-8 新增的全部中文字符串。

**Files:**
- Modify: `AlbumSlim/Localizable.xcstrings`

- [ ] **Step 1:** 先构建一次让 Xcode 字符串目录收集新 key:`xcodegen generate && xcodebuild build ...`

- [ ] **Step 2:** 用脚本列出所有无 `en` localization 的 key(参考:python3 读 JSON 过滤),逐条补 `en` 翻译。已知必须补的存量条目(节选,以脚本输出为准):
  - `一次购买，终身使用` → "One-time purchase, yours forever"
  - `一次性付费，不自动续费。购买后在当前 Apple ID 下长期解锁所有 Pro 功能。` → "Pay once — no subscription. Unlocks all Pro features permanently on your Apple ID."
  - `%@ 解锁 Pro` → "Unlock Pro for %@"
  - `需要相册访问权限` → "Photo Library Access Required"
  - `未授权相册访问` → "Photo access not granted"
  - `开启权限后才能扫描和清理` → "Grant access to scan and clean"
  - `开启后才能随机浏览你的照片和视频` → "Grant access to browse your photos and videos"
  - `正在从 iCloud 下载 %@%%` → "Downloading from iCloud %@%%"
  - `正在识别文字...` → "Recognizing text..."
  - `识别失败，请重试` → "Recognition failed. Try again"
  - `暂无识别结果` → "No text recognized"
  - `发现 %@ 项可清理` → "Found %@ items to clean"
  - `相似组 · %@ 张 · 可省 %@` → "Similar · %@ photos · save %@"
  - `连拍组 · %@ 张 · 可省 %@` → "Burst · %@ photos · save %@"
  - `共 %@ 个视频` → "%@ videos"
  - `共 %@ 张 · %@` → "%@ items · %@"
  - `压缩 %@` → "Compress %@"
  - `%@ 项` → "%@ items";`%@ 项 · %@` → "%@ items · %@"
  - `请从后台完全关闭闪图后重新打开，新的语言设置即可生效` → "Quit AlbumSlim from the App Switcher and reopen it to apply the new language"
  - 纯格式符(`·`、`%@`、`%@ · %@`、`%@ MB`、`English` 等)设 `"shouldTranslate": false`
  - Task 1-8 新增:`已恢复 Pro 权益` → "Pro restored";`未找到可恢复的购买` → "No purchase found to restore";`撤销` → "Undo";`已移到垃圾桶 %@ 项 · 可释放 %@` → "Moved %@ items to trash · frees %@";`解锁成就:%@` → "Achievement unlocked: %@";`清理成就` → "Achievements";`发现约 %@ 可清理` → "About %@ ready to clean";`闪图预估可为你释放约 %@，点开看看吧` → "AlbumSlim can free up about %@ — take a look";`仅可访问部分照片,扫描结果可能不完整` → "Only some photos are accessible — results may be incomplete";`选择更多` → "Select More";`照片将移入系统相册的「最近删除」,30 天内仍可在系统相册中找回` → "Items go to the system Recently Deleted album and can be recovered within 30 days"

- [ ] **Step 3:** 复跑统计脚本确认 0 条缺失(排除 shouldTranslate=false),构建通过,commit

```bash
git add -A && git commit -m "英文本地化补齐: 付费墙/权限/新增文案全覆盖"
```

---

### Task 10: 最终回归验证

- [ ] 跑全部单测:`xcodebuild test -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`
- [ ] 模拟器冒烟(XcodeBuildMCP):启动 → Shuffle 胶囊 → QuickClean 扫描(阶段文案/取消)→ 软删除(toast 体积+撤销)→ 垃圾桶永久删除(新文案/成就 toast)→ 设置(成就页/恢复购买反馈)
- [ ] 确认非 Pro 路径:视频建议删除/截图详情删除/OCR 均弹 Paywall
- [ ] commit 收尾(如有修补)

---

## 明确不做(本轮范围外)

- 免费额度 / 价格 / Paywall 转化优化(付费模式不改)
- 新增日韩等语种(仅补英文)
- 埋点/崩溃上报(涉及隐私承诺决策)
- 相似度阈值真机校准(需真机)
- App Store 截图/预览视频等 ASO 素材(非代码)
