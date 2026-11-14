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
            AssetThumbnail(
                asset: item.asset,
                services: services,
                targetSize: CGSize(width: 320, height: 240)
            )
                .frame(width: 120, height: 92)
                .overlay(alignment: .topTrailing) {
                    if isEditing {
                        Image(systemName: isSelected ? "checkmark" : "circle")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(isSelected ? Theme.accent : .black.opacity(0.38)))
                            .overlay {
                                if !isSelected {
                                    Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)
                                }
                            }
                            .padding(Spacing.s)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                                      lineWidth: isSelected ? 3 : 1)
                }
                .scaleEffect(isSelected ? 0.985 : 1)
                .motion(Motion.standard, value: isSelected)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(item.fileSizeText)
                    .font(AppFont.metric)
                    .foregroundStyle(Theme.textPrimary)
                MetaChip(text: item.resolution, systemImage: "aspectratio")
                if let date = item.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(AppFont.label)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 92)
        .contentShape(.rect)
        .onTapGesture { if isEditing { onTap() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
