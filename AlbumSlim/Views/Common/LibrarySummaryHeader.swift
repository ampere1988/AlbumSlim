import SwiftUI

/// 列表页顶部的总量条：数量 + 占用体积。
///
/// 原来是一行灰色小字，混在列表里读不出来；改成带分类色的卡片后，
/// 用户一进页面就知道"这一类到底占了多少"。
struct LibrarySummaryHeader: View {
    let countText: String
    let sizeText: String
    let systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.16)))

            Text(countText)
                .font(AppFont.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .motion(Motion.standard, value: countText)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(sizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .motion(Motion.standard, value: sizeText)
                Text("总占用")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Spacing.m)
        .glassSurface(radius: Radius.row, elevation: .flat)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LibrarySummaryHeader(countText: "128 个视频", sizeText: "4.2 GB",
                         systemImage: "video.fill", tint: Theme.video)
        .padding()
        .background(Theme.background)
}
