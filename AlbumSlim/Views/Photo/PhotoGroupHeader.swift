import SwiftUI

/// 相似组 / 连拍组的区块头。
///
/// 把"能省多少"提到最显眼的位置并用分类色标出来 —— 用户扫一眼就能决定
/// 先处理哪一组，而不是逐组去读一行灰色小字。
struct PhotoGroupHeader: View {
    let index: Int
    let count: Int
    let savableSize: Int64
    var subtitle: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text("\(index + 1)")
                .font(AppFont.metricSmall)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) 张")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .motion(Motion.standard, value: count)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.label)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            MetaChip(text: String(localized: "可省 \(savableSize.formattedFileSize)"),
                     systemImage: "arrow.down.circle", tint: tint)
                .contentTransition(.numericText())
                .motion(Motion.standard, value: savableSize)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    PhotoGroupHeader(index: 0, count: 6, savableSize: 42_000_000,
                     subtitle: "03/14 10:22 ~ 03/14 10:24", tint: Theme.photo)
        .padding()
        .background(Theme.background)
}
