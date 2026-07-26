import SwiftUI

/// 网格缩略图单元。
///
/// 选中态用"内缩 + 强调色描边 + 角标"表达，而不是盖一层半透明蓝色 ——
/// 蒙版会把照片本身弄脏，正好是清理类 App 最不该做的事。
struct ThumbnailCell: View {
    let item: MediaItem
    let isBest: Bool
    let isSelectable: Bool
    let isSelected: Bool
    let services: AppServiceContainer
    var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?

    var body: some View {
        Button(action: handleTap) {
            thumbnail
                .aspectRatio(1, contentMode: .fill)
                .clipShape(.rect(cornerRadius: Radius.thumb))
                .overlay(alignment: .bottomLeading) { sizeLabel }
                .overlay(alignment: .topTrailing) { badge }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .strokeBorder(borderStyle, lineWidth: borderWidth)
                }
                .padding(isSelected ? Spacing.xs : 0)
                .motion(Motion.standard, value: isSelected)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!isSelectable)
        .accessibilityLabel(item.fileSizeText)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: 320, height: 320)
            )
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Theme.surfaceSunken)
                .shimmer()
        }
    }

    /// 底部渐变压暗，保证浅色照片上的白字也读得清
    private var sizeLabel: some View {
        Text(item.fileSizeText)
            .font(AppFont.label)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 48)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var badge: some View {
        if isSelectable && isSelected {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(Theme.textOnAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent))
                .padding(Spacing.s)
                .transition(.scale.combined(with: .opacity))
        } else if isBest {
            Image(systemName: "star.fill")
                .font(.caption2.bold())
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.warning))
                .padding(Spacing.s)
        }
    }

    private var borderStyle: Color {
        if isSelected { Theme.accent }
        else if isBest { Theme.warning }
        else { Theme.hairline }
    }

    private var borderWidth: CGFloat {
        isSelected || isBest ? 2 : 1
    }

    private func handleTap() {
        guard isSelectable else { return }
        onTap()
    }
}
