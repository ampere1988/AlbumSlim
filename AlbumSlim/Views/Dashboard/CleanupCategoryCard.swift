import SwiftUI

/// 智能扫描结果里的单个分类卡片。
struct CleanupCategoryCard: View {
    let type: CleanupGroup.GroupType
    let countText: String
    let sizeText: String
    /// 大视频要跳到别的 tab，视觉上用不同的尾部图标暗示"离开当前页"
    var leavesCurrentStack = false

    var body: some View {
        HStack(spacing: Spacing.l) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundStyle(type.tint)
                .frame(width: 46, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: Radius.row)
                        .fill(type.tint.opacity(0.16))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Spacing.xs) {
                    Text(countText)
                    Text("·")
                    Text(sizeText)
                }
                .font(AppFont.meta)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: leavesCurrentStack ? "arrow.up.forward" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Spacing.l)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        CleanupCategoryCard(type: .waste, countText: "42 项", sizeText: "180 MB")
        CleanupCategoryCard(type: .similar, countText: "12 组", sizeText: "1.1 GB")
        CleanupCategoryCard(type: .largeVideo, countText: "6 项", sizeText: "3.4 GB",
                            leavesCurrentStack: true)
    }
    .padding()
    .background(Theme.background)
}
