import SwiftUI

/// 区块标题: 左侧竖向强调条 + 标题 + 可选副标题。
///
/// 用在非 List 的自定义滚动页里，替代系统 `Section` 的灰色小标题。
struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: Spacing.m) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.label)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    SectionHeader(title: "按月份逐堆清理", subtitle: "左滑删除，右滑保留")
        .padding()
        .background(Theme.background)
}
