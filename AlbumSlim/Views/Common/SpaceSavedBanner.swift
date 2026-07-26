import SwiftUI

/// 扫描结果横幅：可释放容量作为主角用大字呈现，数量退到副位。
struct SpaceSavedBanner: View {
    let count: Int
    let size: Int64

    var body: some View {
        HStack(spacing: Spacing.l) {
            GlowIcon(systemImage: "sparkles", tint: Theme.success, size: 48)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("可释放 \(size.formattedFileSize)")
                    .font(AppFont.metric)
                    .foregroundStyle(Theme.textPrimary)
                Text("发现 \(count) 项可清理")
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
        .glassSurface()
        .overlay(alignment: .leading) {
            // 左侧一道成功色，让横幅在长列表里一眼可辨
            Capsule()
                .fill(Theme.success)
                .frame(width: 3)
                .padding(.vertical, Spacing.l)
                .padding(.leading, Spacing.xs)
        }
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SpaceSavedBanner(count: 248, size: 3_400_000_000)
        .padding(.vertical, Spacing.xl)
        .background(Theme.background)
}
