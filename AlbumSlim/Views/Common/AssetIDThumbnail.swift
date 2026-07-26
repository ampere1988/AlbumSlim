import SwiftUI
import Photos

/// 只知道 localIdentifier 时用的缩略图：先取回 PHAsset，再交给 `AssetThumbnail`。
struct AssetIDThumbnail: View {
    let localIdentifier: String
    let services: AppServiceContainer
    var targetSize = CGSize(width: 240, height: 240)
    var cornerRadius: CGFloat = Radius.thumb

    @State private var asset: PHAsset?

    var body: some View {
        Group {
            if let asset {
                AssetThumbnail(asset: asset, services: services,
                               targetSize: targetSize, cornerRadius: cornerRadius)
            } else {
                Rectangle()
                    .fill(Theme.surfaceSunken)
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .shimmer()
            }
        }
        .task {
            asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
        }
    }
}
