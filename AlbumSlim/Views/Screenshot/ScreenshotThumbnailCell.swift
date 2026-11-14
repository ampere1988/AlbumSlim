import SwiftUI

/// 截图网格单元：9:16 竖图 + 底部渐变里的体积与分类标签。
struct ScreenshotThumbnailCell: View {
    let item: MediaItem
    let ocrResult: OCRResult?
    let isEditing: Bool
    let isSelected: Bool
    let services: AppServiceContainer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                AssetThumbnail(
                    asset: item.asset,
                    services: services,
                    targetSize: CGSize(width: 400, height: 712),
                    cornerRadius: 0
                )
                .aspectRatio(9.0 / 16.0, contentMode: .fill)
                .overlay(alignment: .topTrailing) { selectionMark }

                footer
            }
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: Radius.thumb))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                                      lineWidth: isSelected ? 3 : 1)
                }
                .scaleEffect(isSelected ? 0.985 : 1)
                .motion(Motion.standard, value: isSelected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            Text(item.fileSizeText)
                .font(AppFont.label)
                .foregroundStyle(Theme.textSecondary)
            if let result = ocrResult {
                Text(result.category.localizedName)
                    .font(AppFont.label.bold())
                    .foregroundStyle(result.category.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(result.category.color.opacity(0.14)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s)
        .frame(minHeight: 38)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isEditing {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.textOnAccent : .white.opacity(0.85),
                                 isSelected ? Theme.accent : .clear)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .padding(Spacing.s)
        }
    }

    private var accessibilityText: String {
        if let result = ocrResult {
            return "\(result.category.localizedName)，\(item.fileSizeText)"
        }
        return item.fileSizeText
    }
}
