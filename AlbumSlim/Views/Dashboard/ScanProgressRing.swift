import SwiftUI

/// 扫描进度环: 渐变描边 + 中心百分比 + 阶段文案。
///
/// 比一根线性进度条更有"正在干活"的分量，也更适合放在空旷的扫描页中央。
struct ScanProgressRing: View {
    let phase: String
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haloPulse = false

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .blur(radius: 32)
                    .scaleEffect(haloPulse ? 1.1 : 0.9)

                Circle()
                    .stroke(Theme.surfaceSunken, lineWidth: 12)

                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            colors: [Theme.accent, Theme.accentSecondary, Theme.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .motion(Motion.standard, value: clamped)

                Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                    .font(AppFont.display)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 180, height: 180)

            Text(phase)
                .font(AppFont.meta)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase)
        .accessibilityValue(clamped.formatted(.percent.precision(.fractionLength(0))))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                haloPulse = true
            }
        }
    }
}

#Preview {
    ScanProgressRing(phase: "正在比对相似照片…", progress: 0.62)
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
}
