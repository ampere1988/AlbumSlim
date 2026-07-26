import SwiftUI
import Photos

/// 仅授权部分照片时的顶部提示条。
struct LimitedAccessBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "photo.badge.plus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.accentMuted))

            Text("仅可访问部分照片，扫描结果可能不完整")
                .font(AppFont.label)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 0)

            Button("选择更多", action: presentLimitedLibraryPicker)
                .font(AppFont.label.bold())
                .foregroundStyle(Theme.accent)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}

#Preview {
    LimitedAccessBanner(onDismiss: {})
}
