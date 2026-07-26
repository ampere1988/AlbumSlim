import SwiftUI

/// 指标磁贴: 分类图标 + 数量大字 + 体积。用于存储概览等聚合展示。
struct StatTile: View {
    let title: LocalizedStringKey
    let count: Int
    let size: Int64
    let systemImage: String
    let tint: Color
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { tile }
                .pressableCardStyle()
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.16)))
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(count.formatted())
                    .font(AppFont.metric)
                    .foregroundStyle(Theme.textPrimary)
                Text(size > 0 ? size.formattedFileSize : " ")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .glassSurface()
    }
}

#Preview {
    LazyVGrid(columns: [.init(), .init()], spacing: Spacing.m) {
        StatTile(title: "视频", count: 128, size: 4_200_000_000,
                 systemImage: "video.fill", tint: Theme.video) {}
        StatTile(title: "照片", count: 3_920, size: 12_400_000_000,
                 systemImage: "photo.fill", tint: Theme.photo) {}
    }
    .padding()
    .background(Theme.background)
}
