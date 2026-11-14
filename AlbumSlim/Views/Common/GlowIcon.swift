import SwiftUI

/// 系统图标底座 —— 空状态、区块标题、成就徽章共用。
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
                Circle().fill(tint.opacity(0.12))
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
