import SwiftUI

/// 带光晕底座的图标 —— 空状态、区块标题、成就徽章共用。
///
/// 结构是三层: 外圈弥散光 → 低饱和圆底 → 渐变符号。比一个灰色 SF Symbol
/// 有分量得多, 又不至于喧宾夺主。
struct GlowIcon: View {
    let systemImage: String
    var tint: Color = Theme.accent
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                Circle().fill(tint.opacity(0.14))
            }
            .background {
                Circle()
                    .fill(tint.opacity(0.28))
                    .blur(radius: size * 0.32)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Spacing.xl) {
        GlowIcon(systemImage: "photo.stack")
        GlowIcon(systemImage: "video.fill", tint: Theme.video)
        GlowIcon(systemImage: "trash.fill", tint: Theme.danger)
    }
    .padding(Spacing.xxl)
    .background(Theme.background)
}
