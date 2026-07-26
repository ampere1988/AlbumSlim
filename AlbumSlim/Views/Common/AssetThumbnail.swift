import SwiftUI
import Photos

/// 统一的资源缩略图：加载中显示骨架，加载完成淡入。
///
/// 之前每个页面各写一份，占位符有的是灰块有的是转圈，圆角也各不相同 ——
/// 全部收敛到这里，缩略图在哪儿看都是一个样。
struct AssetThumbnail: View {
    let asset: PHAsset
    let services: AppServiceContainer
    var targetSize = CGSize(width: 240, height: 240)
    var cornerRadius: CGFloat = Radius.thumb

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(Theme.surfaceSunken)
                    .shimmer()
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .motion(Motion.standard, value: image != nil)
        .accessibilityHidden(true)
        .task {
            image = await services.photoLibrary.thumbnail(for: asset, size: targetSize)
        }
    }
}
