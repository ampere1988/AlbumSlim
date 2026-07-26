import SwiftUI

/// 逐张清理的月份 / 相册堆。
///
/// 左侧是一叠"卡片"预览 —— 用封面图加两层错位的底card 暗示这是一整堆待处理的
/// 照片，比一个静态图标更能传达"这里有活要干"。
struct SwipeBucketRow: View {
    let bucket: SwipeCleanBucket
    let remaining: Int
    let iconName: String
    let services: AppServiceContainer

    private var isDone: Bool { remaining == 0 }

    var body: some View {
        HStack(spacing: Spacing.l) {
            cover

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(bucket.title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Spacing.s) {
                    MetaChip(text: String(localized: "\(bucket.count) 张"))
                    MetaChip(text: bucket.totalSizeText, systemImage: "internaldrive")
                }
            }

            Spacer(minLength: 0)

            statusMark
        }
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        ZStack {
            // 两层底 card 造出"一叠"的厚度
            RoundedRectangle(cornerRadius: Radius.thumb)
                .fill(Theme.surfaceSunken)
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-8))
                .offset(x: -5)
            RoundedRectangle(cornerRadius: Radius.thumb)
                .fill(Theme.surfaceRaised)
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(-4))
                .offset(x: -2)

            if let coverID = bucket.assetIDs.first {
                AssetIDThumbnail(localIdentifier: coverID, services: services,
                                 targetSize: CGSize(width: 160, height: 160))
                    .frame(width: 56, height: 56)
            } else {
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Theme.accentMuted)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: iconName)
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    }
            }
        }
        .frame(width: 68, height: 60)
        .opacity(isDone ? 0.45 : 1)
    }

    @ViewBuilder
    private var statusMark: some View {
        if isDone {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(Theme.success)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.success.opacity(0.16)))
        } else {
            Text("\(remaining)")
                .font(AppFont.metricSmall)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 30, minHeight: 28)
                .padding(.horizontal, Spacing.xs)
                .background(Capsule().fill(Theme.accentMuted))
        }
    }
}
