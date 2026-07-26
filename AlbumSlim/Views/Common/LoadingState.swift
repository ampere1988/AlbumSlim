import SwiftUI

/// 简单加载视图：呼吸光晕 + 文案
struct LoadingState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    let text: String

    init(_ text: String = AppStrings.loading) {
        self.text = text
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 72, height: 72)
                    .blur(radius: 18)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
            }
            Text(text)
                .font(AppFont.meta)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    LoadingState("正在分析相册…")
        .background(Theme.background)
}
