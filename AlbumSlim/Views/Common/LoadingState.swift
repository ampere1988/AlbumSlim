import SwiftUI

/// 简单加载视图：居中 ProgressView + 文案
struct LoadingState: View {
    let text: String

    init(_ text: String = AppStrings.loading) {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 带进度条加载视图：进度 0-1 + phase 文案
struct ProgressLoadingState: View {
    let phase: String
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
            Text("\(phase) \(Int(progress * 100))%")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
    }
}
