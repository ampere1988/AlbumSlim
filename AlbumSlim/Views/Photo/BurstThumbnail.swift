import SwiftUI

/// 连拍横向胶片里的单帧。最佳帧用琥珀描边 + 星标标出。
struct BurstThumbnail: View {
    let item: MediaItem
    let isBest: Bool
    let services: AppServiceContainer

    var body: some View {
        AssetThumbnail(asset: item.asset, services: services,
                       targetSize: CGSize(width: 240, height: 240))
            .frame(width: 104, height: 104)
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
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .padding(Spacing.xs)
    }

    @ViewBuilder
    private var bestBadge: some View {
        if isBest {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.warning))
                .padding(Spacing.xs)
        }
    }
}
