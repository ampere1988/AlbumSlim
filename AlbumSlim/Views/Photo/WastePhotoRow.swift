import SwiftUI

/// 废片列表行：缩略图 + 原因标签 + 体积，编辑态左侧出选择圈。
struct WastePhotoRow: View {
    let item: MediaItem
    let reason: WasteReason?
    let services: AppServiceContainer
    let isEditing: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            AssetThumbnail(asset: item.asset, services: services,
                           targetSize: CGSize(width: 280, height: 280))
                .frame(width: 112, height: 112)
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
                if let reason {
                    MetaChip(reason.label, systemImage: reason.icon, tint: reason.tint)
                }
                Text(item.fileSizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
                if let date = item.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.label)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if !isEditing {
                Button("保留", action: onKeep)
                    .font(AppFont.label.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Spacing.m)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.surfaceSunken))
                    .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 112)
        .contentShape(.rect)
        .onTapGesture {
            if isEditing { onToggle() }
        }
    }
}
