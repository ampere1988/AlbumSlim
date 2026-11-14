import SwiftUI

/// 连拍横向胶片里的单帧。最佳帧用琥珀描边 + 星标标出。
struct BurstThumbnail: View {
    let item: MediaItem
    let isBest: Bool
    let services: AppServiceContainer

    var body: some View {
        AssetThumbnail(asset: item.asset, services: services,
                       targetSize: CGSize(width: 320, height: 400))
            .frame(width: 144, height: 180)
            .overlay(alignment: .bottomLeading) { sizeLabel }
            .overlay(alignment: .topTrailing) { bestBadge }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .strokeBorder(isBest ? Theme.warning : Theme.hairline,
                                  lineWidth: isBest ? 2 : 1)
            }
            .accessibilityElement()
            .accessibilityLabel(isBest
                                ? String(localized: "最佳帧，\(item.fileSizeText)")
                                : item.fileSizeText)
    }

    private var sizeLabel: some View {
        Text(item.fileSizeText)
            .font(AppFont.label)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .padding(Spacing.xs)
    }

    @ViewBuilder
    private var bestBadge: some View {
        if isBest {
            Label("保留", systemImage: "sparkles")
                .font(AppFont.label.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.s)
                .frame(height: 26)
                .background(Capsule().fill(Theme.success))
                .padding(Spacing.s)
        }
    }
}
