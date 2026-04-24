import SwiftUI
import Photos

/// 静态图页面：
/// - 横竖屏均 aspectFit（不裁切），横屏贴左右，竖屏贴上下
/// - 优先从 ViewModel 全图缓存命中，否则先展示 thumbnail，高清到达后无缝替换
/// - 全程走 ZoomableImageView，用户随时可双指缩放
struct ShufflePhotoView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let isActive: Bool
    let viewModel: ShuffleFeedViewModel
    var onZoomStateChanged: (Bool) -> Void = { _ in }

    @State private var displayImage: UIImage?
    @State private var hasFullImage = false
    @State private var downloadProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let displayImage {
                    ZoomableImageView(
                        image: displayImage,
                        initialMode: .fit,
                        onZoomStateChanged: onZoomStateChanged
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView(value: downloadProgress == 0 ? nil : downloadProgress)
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: isActive) {
            if isActive {
                await load()
                await services.backdrop.sample(image: displayImage)
            } else {
                displayImage = nil
                hasFullImage = false
                downloadProgress = 0
                onZoomStateChanged(false)
            }
        }
    }

    private func load() async {
        // 0. 高清 UIImage 已预加载到内存 → 直接展示，跳过 thumbnail + loadFullImage
        if displayImage == nil,
           let cachedFull = viewModel.cachedFullImage(for: item.asset.localIdentifier) {
            displayImage = cachedFull
            hasFullImage = true
            return
        }

        // 1. thumbnail 缓存命中 → 立即显示占位图
        if displayImage == nil,
           let cached = viewModel.cachedThumbnail(for: item.asset.localIdentifier) {
            displayImage = cached
        }

        // 2. 没命中就就地请求 thumbnail
        if displayImage == nil {
            let thumb = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: AppConstants.Shuffle.thumbnailSize,
                contentMode: .aspectFit
            )
            if !Task.isCancelled, let thumb, !hasFullImage {
                displayImage = thumb
            }
        }

        // 3. 加载高清图替换（PHCachingImageManager 已预热系统缓存，通常很快）
        guard !hasFullImage else { return }
        let full = await services.photoLibrary.loadFullImage(
            for: item.asset,
            size: AppConstants.Shuffle.fullImageTargetSize
        ) { progress in
            downloadProgress = progress
        }
        if !Task.isCancelled, let full {
            displayImage = full
            hasFullImage = true
        }
    }
}
