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
            if isEditing {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "取消选择" : "选择")
            }

            AssetThumbnail(asset: item.asset, services: services,
                           targetSize: CGSize(width: 160, height: 160))
                .frame(width: 64, height: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: Spacing.s) {
                if let reason {
                    MetaChip(reason.label, systemImage: reason.icon, tint: reason.tint)
                }
                Text(item.fileSizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer(minLength: 0)

            if !isEditing {
                Button("保留", action: onKeep)
                    .font(AppFont.label.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Spacing.m)
                    .frame(height: 34)
                    .background(Capsule().fill(Theme.surfaceSunken))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if isEditing { onToggle() }
        }
    }
}
