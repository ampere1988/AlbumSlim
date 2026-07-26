import SwiftUI

/// 未授权相册访问时的顶部提示条。
struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.warning.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text("未授权相册访问")
                    .font(AppFont.label.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("开启权限后才能扫描和清理")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Button("去设置", action: PermissionManager.openSettings)
                .font(AppFont.label.bold())
                .foregroundStyle(Theme.textOnAccent)
                .padding(.horizontal, Spacing.m)
                .frame(height: 32)
                .background(Capsule().fill(Theme.accent))
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

#Preview {
    PermissionBanner()
}
