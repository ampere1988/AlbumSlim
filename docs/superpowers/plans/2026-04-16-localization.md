# AlbumSlim 多语言本地化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 AlbumSlim 添加英文本地化支持，使用 String Catalog (.xcstrings) 方案，中文简体为开发语言。

**Architecture:** 利用 SwiftUI 自动字符串提取覆盖大部分 View 层字符串；自定义组件参数改为 `LocalizedStringKey` 类型实现自动提取；非 SwiftUI 场景（Services/ViewModels/Utils）使用 `String(localized:)` 显式包裹；枚举添加 `localizedName` 计算属性。

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, String Catalog (.xcstrings), iOS 17+

**Spec:** `docs/superpowers/specs/2026-04-16-localization-design.md`

---

## File Map

**新建文件：**
- `AlbumSlim/Localizable.xcstrings` — 主 App 所有 UI 字符串的 String Catalog
- `AlbumSlim/InfoPlist.xcstrings` — App 名称 + 权限说明本地化

**修改文件：**
- `project.yml` — 添加 knownRegions、developmentLanguage
- `AlbumSlim/Views/Dashboard/DashboardView.swift` — StatCard 参数类型改为 LocalizedStringKey
- `AlbumSlim/Views/Settings/PaywallView.swift` — featureRow 参数类型改为 LocalizedStringKey
- `AlbumSlim/Views/Onboarding/OnboardingView.swift` — featureRow/privacyRow 参数类型
- `AlbumSlim/Services/VideoCompressionService.swift` — 枚举 localizedName + String(localized:)
- `AlbumSlim/Services/ReminderService.swift` — 枚举 localizedName + String(localized:)
- `AlbumSlim/Services/CleanupCoordinator.swift` — 枚举 localizedName
- `AlbumSlim/Services/SubscriptionService.swift` — String(localized:)
- `AlbumSlim/Services/AchievementService.swift` — String(localized:)
- `AlbumSlim/Services/VideoAnalysisService.swift` — 枚举 localizedName + String(localized:)
- `AlbumSlim/Services/NotesExportService.swift` — String(localized:)
- `AlbumSlim/Services/OCRService.swift` — 枚举 localizedName
- `AlbumSlim/ViewModels/VideoManagerViewModel.swift` — 枚举 localizedName + String(localized:)
- `AlbumSlim/ViewModels/ScreenshotViewModel.swift` — 枚举 localizedName
- `AlbumSlim/ViewModels/DashboardViewModel.swift` — String(localized:)
- `AlbumSlim/ViewModels/PhotoCleanerViewModel.swift` — String(localized:)
- `AlbumSlim/Utils/PermissionManager.swift` — String(localized:)
- `AlbumSlim/App/AppConstants.swift` — String(localized:)
- `AlbumSlim/Views/Settings/SettingsView.swift` — String(localized:) for email

---

### Task 1: Infrastructure Setup

**Files:**
- Modify: `project.yml`
- Create: `AlbumSlim/Localizable.xcstrings`
- Create: `AlbumSlim/InfoPlist.xcstrings`

- [ ] **Step 1: Update project.yml — add knownRegions and developmentLanguage**

在 `options:` 下添加两个配置项：

```yaml
options:
  bundleIdPrefix: com.hao.doushan
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true
  developmentLanguage: zh-Hans
  knownRegions:
    - zh-Hans
    - en
```

仅添加 `developmentLanguage: zh-Hans` 和 `knownRegions:` 块，其他选项保持不变。

- [ ] **Step 2: Create Localizable.xcstrings**

创建 `AlbumSlim/Localizable.xcstrings`，内容为空的 String Catalog 骨架：

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {

  },
  "version" : "1.0"
}
```

此文件位于 `AlbumSlim/` 目录下，XcodeGen 的 `sources: - path: AlbumSlim` 会自动将其纳入 target。

- [ ] **Step 3: Create InfoPlist.xcstrings**

创建 `AlbumSlim/InfoPlist.xcstrings`，包含 App 名称和权限说明的中英文翻译：

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {
    "CFBundleDisplayName" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "AlbumSlim"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "闪图"
          }
        }
      }
    },
    "NSPhotoLibraryUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "AlbumSlim needs access to your photo library to analyze and manage photos and videos. All processing is done locally on your device."
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "闪图需要访问您的照片库来分析和管理照片视频，所有处理均在本地完成。"
          }
        }
      }
    },
    "NSPhotoLibraryAddUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "AlbumSlim needs to save compressed videos to your photo library."
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "闪图需要保存压缩后的视频到您的照片库。"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 4: Run xcodegen and build**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate
xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. 此时 Localizable.xcstrings 可能已被 build 系统填充了从 SwiftUI 代码中自动提取的字符串。

- [ ] **Step 5: Commit**

```bash
git add AlbumSlim/Localizable.xcstrings AlbumSlim/InfoPlist.xcstrings project.yml
git commit -m "添加多语言本地化基础设施：String Catalog + InfoPlist 翻译"
```

---

### Task 2: View Component Parameter Types

将自定义 SwiftUI 组件的纯显示字符串参数从 `String` 改为 `LocalizedStringKey`，使 SwiftUI 自动提取字符串到 String Catalog，无需修改调用方。

**Files:**
- Modify: `AlbumSlim/Views/Dashboard/DashboardView.swift`
- Modify: `AlbumSlim/Views/Settings/PaywallView.swift`
- Modify: `AlbumSlim/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: DashboardView — StatCard title**

读取 `AlbumSlim/Views/Dashboard/DashboardView.swift`，找到 `StatCard` 结构体定义，将 `title` 属性类型从 `String` 改为 `LocalizedStringKey`：

```swift
// 改前:
let title: String
// 改后:
let title: LocalizedStringKey
```

需要在文件顶部添加 `import SwiftUI`（如果尚未导入）。`LocalizedStringKey` 在 SwiftUI 模块中，View 文件通常已导入。

确认 `title` 仅在 `Text(title)` 中使用。如果有其他非显示用途（如比较、日志），则不能改为 `LocalizedStringKey`，应改用 `String(localized:)` 在调用方包裹。

- [ ] **Step 2: PaywallView — featureRow text**

读取 `AlbumSlim/Views/Settings/PaywallView.swift`，找到 `featureRow` 函数定义，将 `text` 参数从 `String` 改为 `LocalizedStringKey`：

```swift
// 改前:
private func featureRow(icon: String, color: Color, text: String) -> some View {
// 改后:
private func featureRow(icon: String, color: Color, text: LocalizedStringKey) -> some View {
```

确认函数内部 `text` 仅用于 `Text(text)` 显示。

- [ ] **Step 3: OnboardingView — featureRow + privacyRow**

读取 `AlbumSlim/Views/Onboarding/OnboardingView.swift`，找到 `featureRow` 和 `privacyRow`（或类似名称的私有函数/组件）。

对于 `featureRow`：
```swift
// 改前:
private func featureRow(icon: String, text: String) -> some View {
// 改后:
private func featureRow(icon: String, text: LocalizedStringKey) -> some View {
```

对于隐私说明行（可能叫 `privacyRow` 或 `privacyCard` 等）：
```swift
// 改前:
... title: String, detail: String ...
// 改后:
... title: LocalizedStringKey, detail: LocalizedStringKey ...
```

读取文件确认函数签名和参数名称，对所有纯显示的 `String` 参数改为 `LocalizedStringKey`。

- [ ] **Step 4: Build verification**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add AlbumSlim/Views/Dashboard/DashboardView.swift AlbumSlim/Views/Settings/PaywallView.swift AlbumSlim/Views/Onboarding/OnboardingView.swift
git commit -m "View 组件参数改为 LocalizedStringKey 以支持自动本地化提取"
```

---

### Task 3: Enum Localization

为所有 rawValue 是中文的枚举添加 `localizedName` 计算属性，并更新 UI 中对 `.rawValue` 的引用。

**核心模式：**

```swift
// 枚举定义中添加：
var localizedName: String {
    switch self {
    case .xxx: return String(localized: "中文")
    case .yyy: return String(localized: "中文")
    }
}
```

UI 代码中 `Text(xxx.rawValue)` 改为 `Text(xxx.localizedName)`。

**Files:**
- Modify: `AlbumSlim/Services/VideoCompressionService.swift`
- Modify: `AlbumSlim/Services/ReminderService.swift`
- Modify: `AlbumSlim/Services/CleanupCoordinator.swift`
- Modify: `AlbumSlim/Services/VideoAnalysisService.swift`
- Modify: `AlbumSlim/Services/OCRService.swift`
- Modify: `AlbumSlim/ViewModels/VideoManagerViewModel.swift`
- Modify: `AlbumSlim/ViewModels/ScreenshotViewModel.swift`
- Modify: 所有引用 `.rawValue` 做 UI 显示的 View 文件

- [ ] **Step 1: CompressionQuality (VideoCompressionService.swift)**

读取文件，找到 `CompressionQuality` 枚举定义。添加 `localizedName`：

```swift
enum CompressionQuality: String, CaseIterable {
    case high   = "高质量"
    case medium = "中质量"
    case low    = "省空间"

    var localizedName: String {
        switch self {
        case .high:   return String(localized: "高质量")
        case .medium: return String(localized: "中质量")
        case .low:    return String(localized: "省空间")
        }
    }
}
```

然后全局搜索 `CompressionQuality` 的 `.rawValue` 在 UI 显示中的引用（如 `Text(quality.rawValue)`），替换为 `.localizedName`。重点检查 `VideoCompressView.swift` 中的 Picker。

- [ ] **Step 2: ReminderInterval (ReminderService.swift)**

```swift
enum ReminderInterval: String, CaseIterable {
    case weekly = "每周"
    case biweekly = "每两周"
    case monthly = "每月"

    var localizedName: String {
        switch self {
        case .weekly:   return String(localized: "每周")
        case .biweekly: return String(localized: "每两周")
        case .monthly:  return String(localized: "每月")
        }
    }
}
```

搜索 `.rawValue` 引用，重点检查 `SettingsView.swift` 中的 Picker。

- [ ] **Step 3: ScanPhase (CleanupCoordinator.swift)**

```swift
// 找到 ScanPhase 枚举，添加：
var localizedName: String {
    switch self {
    case .waste:    return String(localized: "检测废片...")
    case .similar:  return String(localized: "查找相似照片...")
    case .burst:    return String(localized: "分析连拍照片...")
    case .largeVideo: return String(localized: "查找大视频...")
    case .building: return String(localized: "正在整理结果...")
    case .done:     return String(localized: "扫描完成")
    }
}
```

搜索 `.rawValue` 引用，重点检查 `QuickCleanView.swift` 和 `DashboardView.swift`。

- [ ] **Step 4: VideoSortOrder (VideoManagerViewModel.swift)**

```swift
// 找到排序枚举，添加：
var localizedName: String {
    switch self {
    case .size:     return String(localized: "按大小")
    case .duration: return String(localized: "按时长")
    case .date:     return String(localized: "按日期")
    }
}
```

搜索 `.rawValue` 引用，重点检查 `VideoListView.swift`。

- [ ] **Step 5: ScreenshotSortOrder (ScreenshotViewModel.swift)**

```swift
var localizedName: String {
    switch self {
    case .date: return String(localized: "按日期")
    case .size: return String(localized: "按大小")
    }
}
```

搜索 `.rawValue` 引用，重点检查 `ScreenshotListView.swift`。

- [ ] **Step 6: ScreenshotCategory (OCRService.swift)**

```swift
var localizedName: String {
    switch self {
    case .verificationCode: return String(localized: "验证码")
    case .address:          return String(localized: "地址")
    case .chatRecord:       return String(localized: "聊天记录")
    case .article:          return String(localized: "文章")
    case .receipt:          return String(localized: "账单/收据")
    case .delivery:         return String(localized: "快递")
    case .meeting:          return String(localized: "会议")
    case .code:             return String(localized: "代码")
    case .socialMedia:      return String(localized: "社交媒体")
    case .other:            return String(localized: "其他")
    }
}
```

注意：OCRService 中的关键词匹配逻辑（`lower.contains("验证码")`）是内容分析用的，**不要**本地化。只有 UI 显示用的 `.rawValue` 需要改为 `.localizedName`。搜索引用，重点检查 `ScreenshotListView.swift` 和 `ScreenshotDetailView.swift`。

- [ ] **Step 7: VideoSuggestionReason (VideoAnalysisService.swift)**

```swift
var localizedName: String {
    switch self {
    case .tooLong:           return String(localized: "超长视频")
    case .lowQuality:        return String(localized: "低质量")
    case .largeFile:         return String(localized: "大文件")
    case .possibleDuplicate: return String(localized: "疑似重复")
    }
}
```

搜索 `.rawValue` 引用，重点检查 `VideoSuggestionsView.swift`。

- [ ] **Step 8: Update all UI .rawValue references**

对上述所有枚举，全局搜索模式 `\.rawValue` 出现在 `Text()`、`Label()`、`Button()` 等 SwiftUI 视图中的地方，替换为 `.localizedName`。

搜索命令：
```bash
grep -rn '\.rawValue' AlbumSlim/Views/ AlbumSlim/ViewModels/ --include='*.swift'
```

对每个匹配结果判断：如果是 UI 显示用途则替换为 `.localizedName`，如果是序列化/存储/逻辑用途则保持 `.rawValue`。

- [ ] **Step 9: Build verification**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add -A AlbumSlim/Services/ AlbumSlim/ViewModels/ AlbumSlim/Views/
git commit -m "枚举添加 localizedName 计算属性，UI 引用从 rawValue 改为 localizedName"
```

---

### Task 4: Services Layer String(localized:)

为 Services 层中返回给 UI 的错误消息、通知文本、成就数据等添加 `String(localized:)` 包裹。

**核心模式：**
```swift
// 改前:
errorMessage = "中文错误消息"
// 改后:
errorMessage = String(localized: "中文错误消息")

// 带插值:
// 改前:
"成功压缩 \(completed) 个视频"
// 改后:
String(localized: "成功压缩 \(completed) 个视频")
```

**Files:**
- Modify: `AlbumSlim/Services/SubscriptionService.swift`
- Modify: `AlbumSlim/Services/VideoCompressionService.swift`
- Modify: `AlbumSlim/Services/ReminderService.swift`
- Modify: `AlbumSlim/Services/AchievementService.swift`
- Modify: `AlbumSlim/Services/VideoAnalysisService.swift`
- Modify: `AlbumSlim/Services/NotesExportService.swift`

- [ ] **Step 1: SubscriptionService.swift**

读取文件，找到所有用户可见的中文字符串并包裹：

```swift
// ~行30:
purchaseError = String(localized: "无法加载产品信息")

// ~行48:
purchaseError = String(localized: "购买待确认")

// ~行99 (LocalizedError):
var errorDescription: String? { String(localized: "交易验证失败") }
```

- [ ] **Step 2: VideoCompressionService.swift — 通知和错误**

读取文件，包裹通知内容和 LocalizedError：

```swift
// ~行160 (通知标题):
content.title = String(localized: "视频压缩完成")

// ~行162-163 (通知消息，带插值):
// 改前: "成功压缩 \(completed) 个视频，\(failed) 个失败"
// 改后:
String(localized: "成功压缩 \(completed) 个视频，\(failed) 个失败")

// 改前: "成功压缩 \(completed) 个视频"
// 改后:
String(localized: "成功压缩 \(completed) 个视频")

// ~行221-224 (LocalizedError errorDescription):
case .exportSessionFailed: return String(localized: "无法创建压缩会话")
case .assetNotAvailable: return String(localized: "视频不可用（可能在 iCloud 中）")
case .saveFailed: return String(localized: "保存失败")
case .unknown: return String(localized: "压缩失败")
```

- [ ] **Step 3: ReminderService.swift — 通知**

```swift
// ~行60:
content.title = String(localized: "该清理相册了")

// ~行61:
content.body = String(localized: "您的相册可能积累了不少新照片，打开闪图快速清理一下吧！")
```

注意：通知的 body 文本可能与上面不完全一致，读取文件确认实际内容。

- [ ] **Step 4: AchievementService.swift — 成就数据**

读取文件，找到成就定义数组。每个成就的 `title` 和 `description` 都需要包裹：

```swift
// 示例模式（实际代码结构可能不同，读取文件确认）:
Achievement(
    id: "first_100mb",
    title: String(localized: "初试身手"),
    description: String(localized: "累计释放 100 MB"),
    ...
)
```

对所有 ~10 个成就的 title 和 description 执行此操作。

同时处理动态格式化字符串：
```swift
// ~行85-86:
case .cleanupCount(let count): return String(localized: "\(count) 次")
case .deletedCount(let count): return String(localized: "\(count) 项")
```

- [ ] **Step 5: VideoAnalysisService.swift — 建议文本**

读取文件，找到分析建议的文本字符串：

```swift
// ~行54:
String(localized: "时长超过5分钟，建议压缩或裁剪")

// ~行76:
String(localized: "文件超过100MB，建议压缩")

// ~行96:
String(localized: "与相邻视频时间和时长相近")
```

读取文件确认所有建议文本的位置并包裹。

- [ ] **Step 6: NotesExportService.swift**

```swift
// ~行40:
String(localized: "未知日期")

// ~行41:
String(localized: "— 由闪图导出")
```

- [ ] **Step 7: Build verification**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add AlbumSlim/Services/
git commit -m "Services 层用户可见字符串添加 String(localized:) 本地化包裹"
```

---

### Task 5: AppConstants, ViewModels, Utils 本地化

**Files:**
- Modify: `AlbumSlim/App/AppConstants.swift`
- Modify: `AlbumSlim/ViewModels/DashboardViewModel.swift`
- Modify: `AlbumSlim/ViewModels/PhotoCleanerViewModel.swift`
- Modify: `AlbumSlim/ViewModels/VideoManagerViewModel.swift`
- Modify: `AlbumSlim/Utils/PermissionManager.swift`
- Modify: `AlbumSlim/Views/Settings/SettingsView.swift`

- [ ] **Step 1: AppConstants.swift**

读取文件，包裹用户可见常量：

```swift
// ~行4:
// 改前: static let appName = "闪图"
// 改后:
static let appName = String(localized: "闪图")

// ~行20-22 (压缩预设 — 元组中的名称):
// 改前: ("高质量", 1920, 1080)
// 改后:
(String(localized: "高质量"), 1920, 1080),
(String(localized: "中质量"), 1280, 720),
(String(localized: "省空间"), 640, 480),
```

注意：如果 `presets` 是 `static let`，`String(localized:)` 的调用发生在首次访问时（lazy），这在 static context 中可能有问题。如果编译报错，改为 `static var presets` 使其成为计算属性，或改为方法。

- [ ] **Step 2: DashboardViewModel.swift**

```swift
// ~行13:
errorMessage = String(localized: "需要相册访问权限才能使用")
```

读取文件确认实际错误消息文本。

- [ ] **Step 3: PhotoCleanerViewModel.swift**

```swift
// ~行59:
// 改前: errorMessage = "删除失败：\(error.localizedDescription)"
// 改后:
errorMessage = String(localized: "删除失败：\(error.localizedDescription)")
```

- [ ] **Step 4: VideoManagerViewModel.swift — 非枚举字符串**

```swift
// ~行59:
errorMessage = String(localized: "删除失败：\(error.localizedDescription)")
```

（枚举 `localizedName` 已在 Task 3 处理）

- [ ] **Step 5: PermissionManager.swift**

读取文件，为所有权限状态描述添加 `String(localized:)`：

```swift
// ~行27-32:
return String(localized: "未请求权限")
return String(localized: "访问受限")
return String(localized: "已拒绝访问")
return String(localized: "已授权完整访问")
return String(localized: "已授权部分访问")
return String(localized: "未知状态")
```

- [ ] **Step 6: SettingsView.swift — 反馈邮件**

读取文件，找到反馈邮件的 subject 和 body：

```swift
// ~行177-178:
// 改前: "[闪图] 用户反馈"
// 改后:
String(localized: "[闪图] 用户反馈")
```

邮件正文模板同理处理。

- [ ] **Step 7: Build verification**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add AlbumSlim/App/AppConstants.swift AlbumSlim/ViewModels/ AlbumSlim/Utils/PermissionManager.swift AlbumSlim/Views/Settings/SettingsView.swift
git commit -m "AppConstants/ViewModels/Utils 层用户可见字符串添加本地化"
```

---

### Task 6: Build & Populate English Translations

构建项目让 Xcode 自动提取所有字符串到 String Catalog，然后填入英文翻译。

**Files:**
- Modify: `AlbumSlim/Localizable.xcstrings`

- [ ] **Step 1: Clean build to extract strings**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild clean build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Check extracted strings**

读取 `AlbumSlim/Localizable.xcstrings`，查看 build 系统自动提取的字符串 key 列表。

如果 build 系统未自动填充（CLI 构建可能不会写回源文件），则需要手动添加所有字符串 key。

- [ ] **Step 3: Add English translations**

编辑 `AlbumSlim/Localizable.xcstrings`，为每个中文 key 添加英文翻译。

以下是完整的翻译对照表。在 xcstrings JSON 中，每个条目格式为：

```json
"中文key" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "English value"
      }
    }
  }
}
```

**Tab 和导航标题：**

| 中文 Key | English |
|----------|---------|
| 概览 | Overview |
| 视频 | Videos |
| 照片 | Photos |
| 截图 | Screenshots |
| 设置 | Settings |
| 闪图 | AlbumSlim |
| 照片清理 | Photo Cleanup |
| 视频管理 | Video Manager |
| 截图管理 | Screenshot Manager |
| 清理建议 | Suggestions |
| 清理成就 | Achievements |
| 解锁 Pro | Unlock Pro |
| 智能扫描 | Smart Scan |
| 视频压缩 | Video Compress |
| 识别记录 | OCR Records |
| 识别内容 | OCR Content |

**Dashboard：**

| 中文 Key | English |
|----------|---------|
| 正在分析相册... | Analyzing album... |
| 无法访问相册 | Cannot access album |
| 相册总占用 | Total Album Size |
| 连拍 | Bursts |
| 智能分析相册，释放存储空间 | Analyze your album intelligently, free up storage |
| 检测废片、相似照片、连拍和大视频 | Detect bad photos, similar photos, bursts and large videos |
| 重新扫描 | Rescan |
| 升级 Pro | Upgrade to Pro |
| %lld 项 | %lld items |

**Quick Clean：**

| 中文 Key | English |
|----------|---------|
| 正在分析您的相册... | Analyzing your album... |
| 相册很整洁 | Album is clean |
| 未发现需要清理的项目 | No items found to clean up |
| 扫描完成 | Scan complete |
| 上次扫描结果 | Last scan results |
| 点击分类前往对应页面查看详情 | Tap a category to view details |

**Photo Views：**

| 中文 Key | English |
|----------|---------|
| 扫描废片... | Scanning for bad photos... |
| 未发现废片 | No bad photos found |
| 开始扫描 | Start Scan |
| 全选 | Select All |
| 全不选 | Deselect All |
| 取消全选 | Deselect All |
| 保留 | Keep |
| 已选 %lld 张 | %lld selected |
| 删除选中 | Delete Selected |
| 纯黑 | Pure Black |
| 纯白 | Pure White |
| 模糊 | Blurry |
| 遮挡 | Blocked |
| 误拍 | Accidental |
| 扫描相似照片... | Scanning similar photos... |
| 未发现相似照片 | No similar photos found |
| 选中除最佳外全部 | Select All Except Best |
| 升级 Pro 查看更多相似组 | Upgrade to Pro for more groups |
| 解锁 Pro | Unlock Pro |
| 扫描连拍照片... | Scanning burst photos... |
| 未发现连拍照片 | No burst photos found |
| 只保留最佳 | Keep Best Only |
| 扫描超大照片... | Scanning large photos... |
| 未发现超大照片 | No large photos found |
| 相似照片 | Similar Photos |
| 废片 | Bad Photos |
| 超大照片 | Large Photos |

**Video Views：**

| 中文 Key | English |
|----------|---------|
| 加载视频... | Loading videos... |
| 没有视频 | No videos |
| 删除 | Delete |
| 排序 | Sort |
| 完成 | Done |
| 选择 | Select |
| 未知日期 | Unknown Date |
| 正在分析视频... | Analyzing videos... |
| 没有清理建议 | No suggestions |
| 视频信息 | Video Info |
| 压缩质量 | Compression Quality |
| 预估结果 | Estimated Result |
| 压缩中... | Compressing... |
| 压缩结果 | Compression Result |

**Screenshot Views：**

| 中文 Key | English |
|----------|---------|
| 加载截图... | Loading screenshots... |
| 没有截图 | No screenshots |
| 处理中... | Processing... |
| 识别文字 | Recognized Text |
| 已存储 | Saved |
| 分享 | Share |
| 开始识别 | Start OCR |
| 直接删除 | Delete Now |
| 暂无识别记录 | No OCR records |
| 删除记录 | Delete Record |

**Settings：**

| 中文 Key | English |
|----------|---------|
| 通知权限未开启 | Notification Permission Disabled |
| 去设置 | Open Settings |
| 取消 | Cancel |
| 确认 | Confirm |
| 确认清除缓存 | Confirm Clear Cache |
| Pro | Pro |
| Pro 已激活 | Pro Activated |
| 恢复购买 | Restore Purchase |
| 清理提醒 | Cleanup Reminder |
| 定期提醒清理 | Periodic Cleanup Reminder |
| 提醒频率 | Reminder Frequency |
| 通用 | General |
| 清除分析缓存 | Clear Analysis Cache |
| 关于 | About |
| 版本 | Version |
| 法律信息 | Legal |

**Paywall：**

| 中文 Key | English |
|----------|---------|
| 解锁全部功能 | Unlock All Features |
| 一次购买，永久使用 | One-time purchase, lifetime access |
| 无限废片清理 | Unlimited bad photo cleanup |
| 相似照片去重 | Similar photo deduplication |
| 视频压缩与批量管理 | Video compress & batch management |
| 截图 OCR 文字识别 | Screenshot OCR text recognition |
| 连拍 / 大照片清理 | Burst / large photo cleanup |
| 智能一键扫描清理 | Smart one-tap scan & clean |
| 加载中... | Loading... |
| 无法加载产品信息 | Unable to load product info |
| 重试 | Retry |
| 购买出错 | Purchase Error |
| 确定 | OK |

**Onboarding：**

| 中文 Key | English |
|----------|---------|
| 智能分析相册，释放存储空间 | Intelligently analyze your album, free up storage |
| 所有分析在本地完成，隐私安全 | All analysis done locally, privacy safe |
| 智能压缩视频，画质几乎无损 | Smart video compression, nearly lossless |
| 自动发现相似照片和废片 | Auto-detect similar photos and bad shots |
| 批量管理截图，一键清理 | Batch manage screenshots, one-tap cleanup |
| 需要相册访问权限才能使用 | Photo library access required |
| 前往系统设置 | Open System Settings |
| 授权访问相册 | Grant Album Access |
| 隐私保护承诺 | Privacy Promise |
| 您的相册安全是我们的首要原则 | Your album security is our top priority |
| 100% 本地处理 | 100% Local Processing |
| 零网络传输 | Zero Network Transfer |
| 无隐私追踪 | No Privacy Tracking |
| 数据留在手机 | Data Stays on Device |
| 同意并继续 | Agree & Continue |
| 查看隐私政策 | View Privacy Policy |

**Enums (来自 Task 3 的 String(localized:))：**

| 中文 Key | English |
|----------|---------|
| 高质量 | High Quality |
| 中质量 | Medium Quality |
| 省空间 | Space Saver |
| 每周 | Weekly |
| 每两周 | Biweekly |
| 每月 | Monthly |
| 检测废片... | Detecting bad photos... |
| 查找相似照片... | Finding similar photos... |
| 分析连拍照片... | Analyzing burst photos... |
| 查找大视频... | Finding large videos... |
| 正在整理结果... | Organizing results... |
| 按大小 | By Size |
| 按时长 | By Duration |
| 按日期 | By Date |
| 验证码 | Verification Code |
| 地址 | Address |
| 聊天记录 | Chat Record |
| 文章 | Article |
| 账单/收据 | Bill/Receipt |
| 快递 | Delivery |
| 会议 | Meeting |
| 代码 | Code |
| 社交媒体 | Social Media |
| 其他 | Other |
| 超长视频 | Too Long |
| 低质量 | Low Quality |
| 大文件 | Large File |
| 疑似重复 | Possible Duplicate |

**Services (来自 Task 4 的 String(localized:))：**

| 中文 Key | English |
|----------|---------|
| 无法加载产品信息 | Unable to load product info |
| 购买待确认 | Purchase pending |
| 交易验证失败 | Transaction verification failed |
| 视频压缩完成 | Video compression complete |
| 无法创建压缩会话 | Cannot create compression session |
| 视频不可用（可能在 iCloud 中） | Video unavailable (may be in iCloud) |
| 保存失败 | Save failed |
| 压缩失败 | Compression failed |
| 该清理相册了 | Time to clean your album |
| — 由闪图导出 | — Exported by AlbumSlim |
| 需要相册访问权限才能使用 | Photo library access required to use this app |
| 未请求权限 | Not Requested |
| 访问受限 | Access Restricted |
| 已拒绝访问 | Access Denied |
| 已授权完整访问 | Full Access Granted |
| 已授权部分访问 | Limited Access Granted |
| 未知状态 | Unknown Status |

**Achievements (来自 Task 4)：**

| 中文 Key | English |
|----------|---------|
| 初试身手 | First Steps |
| 累计释放 100 MB | Freed 100 MB total |
| 小有成效 | Getting Started |
| 累计释放 500 MB | Freed 500 MB total |
| 空间大师 | Space Master |
| 累计释放 1 GB | Freed 1 GB total |
| 瘦身达人 | Slim Expert |
| 累计释放 5 GB | Freed 5 GB total |
| 传奇清理师 | Legendary Cleaner |
| 累计释放 10 GB | Freed 10 GB total |
| 第一次清理 | First Cleanup |
| 完成首次清理 | Completed first cleanup |
| 清理习惯 | Cleanup Habit |
| 累计清理 10 次 | Cleaned up 10 times |
| 清理达人 | Cleanup Pro |
| 累计清理 50 次 | Cleaned up 50 times |
| 果断决策 | Decisive Action |
| 累计清理 100 个项目 | Cleaned 100 items |
| 大扫除 | Big Cleanup |
| 累计清理 1000 个项目 | Cleaned 1000 items |
| %lld 次 | %lld times |
| %lld 项 | %lld items |

**Share Card：**

| 中文 Key | English |
|----------|---------|
| 本次释放 | Freed This Time |
| 累计释放 | Total Freed |
| 清理次数 | Cleanup Count |
| AlbumSlim - 智能相册管理 | AlbumSlim - Smart Album Manager |

**其他动态字符串（带插值）：** 读取 xcstrings 文件，对照上表为所有已提取的 key 填入英文翻译。如果有遗漏的 key（build 提取了但不在上表中），根据中文含义提供合理的英文翻译。

- [ ] **Step 4: Build verification**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add AlbumSlim/Localizable.xcstrings
git commit -m "添加所有 UI 字符串的英文翻译"
```

---

### Task 7: Final Verification

**Files:** None (read-only verification)

- [ ] **Step 1: Clean build**

```bash
cd /Users/huge/Project/AlbumSlim && xcodegen generate && xcodebuild clean build -project AlbumSlim.xcodeproj -scheme AlbumSlim -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED, no warnings about missing translations.

- [ ] **Step 2: Verify xcstrings completeness**

读取 `AlbumSlim/Localizable.xcstrings`，检查：
1. 所有 key 都有 `en` 翻译条目
2. 没有 `"state": "new"` 的未翻译条目（应全部为 `"translated"`）
3. JSON 格式正确

- [ ] **Step 3: Verify InfoPlist.xcstrings**

读取 `AlbumSlim/InfoPlist.xcstrings`，确认 CFBundleDisplayName 和两个权限说明都有中英文翻译。

- [ ] **Step 4: Final commit (if any fixes needed)**

```bash
git add -A && git commit -m "多语言本地化最终验证和修复"
```
