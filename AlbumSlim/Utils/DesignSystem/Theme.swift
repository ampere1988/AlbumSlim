import SwiftUI

/// 全局语义色板。
///
/// 优先使用 UIKit 的系统语义色，让界面自然跟随 iOS 的深浅色、对比度与辅助功能设置。
enum Theme {

    // MARK: - 背景与表面

    /// 页面最底层背景
    static let background = Color(uiColor: .systemGroupedBackground)
    /// 卡片/分组表面
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    /// 抬起一层的表面(浮层、选中态、嵌套卡片)
    static let surfaceRaised = Color(uiColor: .systemBackground)
    /// 沉下去的凹槽(进度条底、输入框底)
    static let surfaceSunken = Color(uiColor: .tertiarySystemGroupedBackground)

    /// 1px 分隔线 / 卡片描边
    static let hairline = Color(uiColor: .separator)
    /// 强调描边(选中卡片、聚焦态)
    static let hairlineStrong = Color(uiColor: .opaqueSeparator)

    // MARK: - 文字

    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    /// 只用于装饰性说明, 不承载关键信息
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    /// 强调色背景上的文字
    static let textOnAccent = Color.white

    // MARK: - 强调色

    /// 主强调色使用系统蓝，交互含义与 iOS 保持一致。
    static let accent = Color(uiColor: .systemBlue)
    static let accentSecondary = Color(uiColor: .systemIndigo)
    /// 强调色的低饱和填充(chip 背景、图标底座)
    static let accentMuted = Color(uiColor: .systemBlue).opacity(0.12)

    /// 保留旧调用接口，但使用单一系统色，避免到处出现装饰性渐变。
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 保留旧调用接口，原生风格下不再铺环境光。
    static var ambientGlow: RadialGradient {
        RadialGradient(colors: [.clear, .clear],
                       center: .center, startRadius: 0, endRadius: 260)
    }

    // MARK: - 状态色

    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)
    static let dangerMuted = Color(uiColor: .systemRed).opacity(0.12)

    // MARK: - 媒体分类色
    //
    // 全 App 统一: 同一类媒体在仪表盘、列表、图表、徽章里必须是同一个颜色。

    static let video = Color(uiColor: .systemBlue)
    static let photo = Color(uiColor: .systemGreen)
    static let screenshot = Color(uiColor: .systemOrange)
    static let burst = Color(uiColor: .systemPurple)
    static let livePhoto = Color(uiColor: .systemPink)
}
