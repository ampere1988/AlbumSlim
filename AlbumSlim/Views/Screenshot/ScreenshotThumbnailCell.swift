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
            AssetThumbnail(asset: item.asset, services: services,
                           targetSize: CGSize(width: 240, height: 420))
                .aspectRatio(9.0 / 16.0, contentMode: .fill)
                .overlay(alignment: .bottomLeading) { footer }
                .overlay(alignment: .topLeading) { selectionMark }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                                      lineWidth: isSelected ? 2 : 1)
                }
                .padding(isSelected ? 2 : 0)
                .motion(Motion.standard, value: isSelected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            Text(item.fileSizeText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
            if let result = ocrResult {
                Text(result.category.localizedName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(result.category.color))
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.xs)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 44)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        }
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
