import SwiftUI

/// 带进度条加载视图：渐变进度条 + phase 文案 + 百分比
///
/// 百分比用等宽数字并右对齐，数值跳动时左侧文案不会被推着走。
struct ProgressLoadingState: View {
    let phase: String
    let progress: Double

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(phase)
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
            }

            // 填充用 Rectangle + 水平缩放而不是改 frame：不需要 GeometryReader
            // 拿父级宽度，外层的 capsule 裁切又保证了两端圆头不被压扁。
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.surfaceSunken)
                Rectangle()
                    .fill(Theme.accentGradient)
                    .scaleEffect(x: clamped, y: 1, anchor: .leading)
            }
            .frame(height: 8)
            .clipShape(.capsule)
            .motion(Motion.standard, value: clamped)
        }
        .padding(.horizontal, Spacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase)
        .accessibilityValue(clamped.formatted(.percent.precision(.fractionLength(0))))
    }
}

#Preview {
    ProgressLoadingState(phase: "正在分析相册…", progress: 0.42)
        .padding(.vertical, Spacing.xxl)
        .background(Theme.background)
}
