import SwiftUI

/// 成就行：未解锁是灰色轮廓 + 进度条，解锁后徽章点亮并带光晕。
///
/// 未解锁不做整行降透明度 —— 那会让描述文字掉到对比度线以下；
/// 改为只让徽章本身失色，文案照常可读。
struct AchievementBadgeRow: View {
    let achievement: Achievement
    let isUnlocked: Bool
    let progress: Double

    var body: some View {
        HStack(spacing: Spacing.l) {
            badge

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(achievement.title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(achievement.description)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)

                if !isUnlocked {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.surfaceSunken)
                        Rectangle()
                            .fill(Theme.warning)
                            .scaleEffect(x: min(max(progress, 0), 1), y: 1, anchor: .leading)
                    }
                    .frame(height: 4)
                    .clipShape(.capsule)
                    .padding(.top, Spacing.xs)
                }
            }

            Spacer(minLength: 0)

            if isUnlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.success)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnlocked
                            ? String(localized: "已解锁")
                            : progress.formatted(.percent.precision(.fractionLength(0))))
    }

    @ViewBuilder
    private var badge: some View {
        if isUnlocked {
            GlowIcon(systemImage: achievement.icon, tint: Theme.warning, size: 48)
        } else {
            Image(systemName: achievement.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.surfaceSunken))
                .accessibilityHidden(true)
        }
    }
}
