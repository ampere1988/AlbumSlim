# AlbumSlim 多语言本地化设计方案

## 概述

为 AlbumSlim（闪图）添加英文本地化支持，使应用面向国际市场用户。采用 Xcode String Catalog（.xcstrings）方案，中文简体为开发语言，英文为首个翻译语言。后续其他语言通过批量翻译本地化文件扩展。

## 决策记录

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 首批语言 | 中文简体 + 英文 | 最小可行方案，覆盖最大用户群 |
| 技术方案 | String Catalog (.xcstrings) | iOS 17+ 项目，SwiftUI 原生支持，单文件管理 |
| 开发语言 | 中文简体 (zh-Hans) | 保持现有代码不变，改动量最小 |
| App 英文名 | AlbumSlim（暂定） | 后续可调整 |

## 基础设施

### 文件结构

```
AlbumSlim/
├── Localizable.xcstrings          # 主 App 所有 UI 字符串（zh-Hans + en）
├── InfoPlist.xcstrings            # App 名称 + 权限说明
AlbumSlimWidget/
├── Localizable.xcstrings          # Widget 独立字符串（后续迭代）
```

### project.yml 配置

- 添加 `knownRegions: [zh-Hans, en]`
- 设置 `DEVELOPMENT_LANGUAGE: zh-Hans`
- 将 `Localizable.xcstrings` 和 `InfoPlist.xcstrings` 加入主 target 的 sources

### InfoPlist.xcstrings 内容

需本地化的 Info.plist 键：

| 键 | 中文（开发语言） | 英文 |
|----|-----------------|------|
| CFBundleDisplayName | 闪图 | AlbumSlim |
| NSPhotoLibraryUsageDescription | 闪图需要访问您的照片库来分析和管理照片视频，所有处理均在本地完成。 | AlbumSlim needs access to your photo library to analyze and manage photos and videos. All processing is done locally on your device. |
| NSPhotoLibraryAddUsageDescription | 闪图需要保存压缩后的视频到您的照片库。 | AlbumSlim needs to save compressed videos to your photo library. |

## 字符串处理策略

### 类型 1：SwiftUI 自动提取（无需改代码）

SwiftUI 中的以下 API 会被 Xcode 自动识别为可本地化字符串：

- `Text("xxx")`
- `Label("xxx", systemImage:)`
- `Button("xxx")`
- `.navigationTitle("xxx")`
- `.alert("xxx", ...)`
- `.confirmationDialog("xxx", ...)`
- `Section("xxx")`
- `Toggle("xxx", ...)`
- `.tabItem { Label("xxx", ...) }`

覆盖范围：Views 文件夹 21 个文件中的绝大部分字符串。不需要修改 Swift 源代码，只需在 String Catalog 中填入英文翻译。

### 类型 2：需要 `String(localized:)` 包裹

以下场景的字符串不会被自动提取，需要手动用 `String(localized:)` 包裹：

- **Services 层**返回给 UI 的错误消息/状态文本
  - 例：`purchaseError = "无法加载产品信息"` → `purchaseError = String(localized: "无法加载产品信息")`
- **AppConstants** 中用户可见的常量
  - 例：压缩预设名称 `"高质量"` → `String(localized: "高质量")`
- **ViewModel** 中构造的用户可见字符串
- **本地通知**的 title/body
- **成就**名称/描述

### 类型 3：字符串插值

- SwiftUI Text 中自动支持：`Text("已释放 \(size) 空间")`
- 非 SwiftUI 场景：`String(localized: "已释放 \(size) 空间")`

### 类型 4：不需要本地化

- 日志/调试输出（`print`、`Logger` 调用）
- 代码注释
- SwiftData 模型内部标识符
- 纯逻辑用途字符串（文件名、路径拼接）
- 单元测试字符串

## 实施范围

### 初步版本（本次实施）

| 优先级 | 内容 | 文件数 | 工作方式 |
|--------|------|--------|----------|
| P0 | InfoPlist（App名称 + 权限说明） | 2 个新文件 | 创建 InfoPlist.xcstrings |
| P1 | Views 层 UI 字符串 | 21 个文件 | SwiftUI 自动提取，填翻译 |
| P2 | Services 层用户可见消息 | ~14 个文件 | `String(localized:)` 包裹 |
| P3 | AppConstants 用户可见常量 | 1 个文件 | `String(localized:)` 包裹 |

### 后续迭代

| 优先级 | 内容 |
|--------|------|
| P4 | ViewModels 层构造的文本（~5 个文件） |
| P5 | Widget 字符串（独立 xcstrings） |
| P6 | 更多语言支持（日文、韩文等） |

## 构建流程

修改 project.yml 和创建 .xcstrings 文件后，需要执行 `xcodegen generate` 重新生成 .xcodeproj，然后用 `xcodebuild build` 验证编译通过。首次 build 后 Xcode 会自动提取 SwiftUI 字符串到 String Catalog。

## 英文翻译原则

- 保持简洁自然，符合英文 App 表达习惯
- 按钮/标签用动词或短语
- 专业术语保持一致
- 数字格式和单位跟随系统 locale

### 核心术语对照表

| 中文 | 英文 |
|------|------|
| 闪图 | AlbumSlim |
| 概览 | Overview |
| 视频 | Videos |
| 照片 | Photos |
| 截图 | Screenshots |
| 设置 | Settings |
| 废片 | Bad Photos |
| 相似照片 | Similar Photos |
| 连拍 | Bursts |
| 大照片 | Large Photos |
| 一键清理 | Quick Clean |
| 视频压缩 | Video Compress |
| 高质量 | High Quality |
| 中质量 | Medium Quality |
| 省空间 | Space Saver |
| 已释放 | Freed |
| 可释放 | Can Free |
| Pro 解锁 | Unlock Pro |
| 存储空间 | Storage |
| 清理 | Clean |
| 删除 | Delete |
| 压缩 | Compress |
| 扫描 | Scan |
| 分析 | Analyze |
| 全选 | Select All |
| 取消 | Cancel |
| 确认 | Confirm |
| 完成 | Done |
