import SwiftUI

/// 全局语义色板 —— 深色影廊风 (Modern Dark / Cinema Mobile)
///
/// 设计原则:
/// - 深色为主场景, 浅色为完整备选, 两套都独立调过对比度(正文 ≥ 4.5:1, 次要 ≥ 3:1)
/// - 背景避开纯黑 #000000, 防止 OLED 拖影, 同时给玻璃层留出可感知的层次
/// - 所有页面只允许引用这里的语义 token, 禁止在 View 里写裸 hex / 系统色
enum Theme {

    // MARK: - 背景与表面

    /// 页面最底层背景
    static let background = Color.dynamic(light: 0xFAFAFC, dark: 0x0B0B0F)
    /// 卡片/分组表面
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x16161C)
    /// 抬起一层的表面(浮层、选中态、嵌套卡片)
    static let surfaceRaised = Color.dynamic(light: 0xFFFFFF, dark: 0x1F1F28)
    /// 沉下去的凹槽(进度条底、输入框底)
    static let surfaceSunken = Color.dynamic(light: 0xEFEFF3, dark: 0x101015)

    /// 1px 分隔线 / 卡片描边
    static let hairline = Color.dynamic(light: 0x000000, lightAlpha: 0.08,
                                        dark: 0xFFFFFF, darkAlpha: 0.10)
    /// 强调描边(选中卡片、聚焦态)
    static let hairlineStrong = Color.dynamic(light: 0x000000, lightAlpha: 0.16,
                                              dark: 0xFFFFFF, darkAlpha: 0.22)

    // MARK: - 文字

    static let textPrimary = Color.dynamic(light: 0x0B0B0F, dark: 0xF5F5F7)
    static let textSecondary = Color.dynamic(light: 0x52525B, dark: 0xA1A1AA)
    /// 只用于装饰性说明, 不承载关键信息
    static let textTertiary = Color.dynamic(light: 0x8E8E96, dark: 0x71717A)
    /// 强调色背景上的文字
    static let textOnAccent = Color.white

    // MARK: - 强调色

    /// 主强调色: 靛蓝。浅色模式下加深一档保证 4.5:1
    static let accent = Color.dynamic(light: 0x4F46E5, dark: 0x6366F1)
    /// 副强调色: 紫。用于渐变尾端与次级高亮
    static let accentSecondary = Color.dynamic(light: 0x9333EA, dark: 0xA855F7)
    /// 强调色的低饱和填充(chip 背景、图标底座)
    static let accentMuted = Color.dynamic(light: 0x4F46E5, lightAlpha: 0.12,
                                           dark: 0x6366F1, darkAlpha: 0.18)

    /// 主渐变: 靛蓝 → 紫, 用于 CTA、环形图、大数字
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 环境光晕: 铺在背景上制造"影厅"氛围。
    ///
    /// 浅色模式下必须压到极低 —— 白底上的紫色弥散很快就会从"氛围"变成"脏",
    /// 所以两套模式用不同的不透明度而不是同一个值。
    private static let glowTint = Color.dynamic(light: 0x9333EA, lightAlpha: 0.09,
                                                dark: 0xA855F7, darkAlpha: 0.24)

    static var ambientGlow: RadialGradient {
        RadialGradient(colors: [glowTint, .clear],
                       center: .center, startRadius: 0, endRadius: 260)
    }

    // MARK: - 状态色

    static let success = Color.dynamic(light: 0x059669, dark: 0x34D399)
    static let warning = Color.dynamic(light: 0xB45309, dark: 0xFBBF24)
    static let danger = Color.dynamic(light: 0xDC2626, dark: 0xFF5A5F)
    static let dangerMuted = Color.dynamic(light: 0xDC2626, lightAlpha: 0.12,
                                           dark: 0xFF5A5F, darkAlpha: 0.18)

    // MARK: - 媒体分类色
    //
    // 全 App 统一: 同一类媒体在仪表盘、列表、图表、徽章里必须是同一个颜色。

    static let video = Color.dynamic(light: 0x0284C7, dark: 0x38BDF8)
    static let photo = Color.dynamic(light: 0x059669, dark: 0x34D399)
    static let screenshot = Color.dynamic(light: 0xB45309, dark: 0xFBBF24)
    static let burst = Color.dynamic(light: 0x9333EA, dark: 0xC084FC)
    static let livePhoto = Color.dynamic(light: 0xDB2777, dark: 0xF472B6)
}

// MARK: - 动态颜色构造

extension Color {
    /// 按当前深浅色模式解析的动态颜色。
    ///
    /// SwiftUI 没有在 View 之外构造随 colorScheme 变化的 `Color` 的原生方式,
    /// 因此这里是全项目**唯一**允许出现 `UIColor` 的位置 —— 所有页面消费的都是
    /// 上面 `Theme` 里的语义 token, 不直接碰这个构造器。
    static func dynamic(light: UInt32, lightAlpha: Double = 1,
                        dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
