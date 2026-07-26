import SwiftUI

/// 超大照片列表行：体积是主角，分辨率与日期退到副位。
struct LargePhotoRow: View {
    let item: MediaItem
    let isSelected: Bool
    let isEditing: Bool
    let services: AppServiceContainer
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            AssetThumbnail(asset: item.asset, services: services)
                .frame(width: 72, height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                                      lineWidth: isSelected ? 2 : 1)
                }

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(item.fileSizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Spacing.s) {
                    MetaChip(text: item.resolution, systemImage: "aspectratio")
                    if let date = item.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppFont.label)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .motion(Motion.standard, value: isSelected)
            }
        }
        .contentShape(.rect)
        .onTapGesture { if isEditing { onTap() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
