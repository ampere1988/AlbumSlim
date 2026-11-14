import SwiftUI

/// 扫描结果横幅：可释放容量作为主角用大字呈现，数量退到副位。
struct SpaceSavedBanner: View {
    let count: Int
    let size: Int64

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "sparkles")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.success)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.success.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text("可释放 \(size.formattedFileSize)")
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .motion(Motion.standard, value: size)
                Text("发现 \(count) 项可清理")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .motion(Motion.standard, value: count)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .glassSurface(radius: Radius.row, elevation: .flat)
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SpaceSavedBanner(count: 248, size: 3_400_000_000)
        .padding(.vertical, Spacing.xl)
        .background(Theme.background)
}
