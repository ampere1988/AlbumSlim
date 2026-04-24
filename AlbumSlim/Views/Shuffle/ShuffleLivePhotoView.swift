import SwiftUI
import PhotosUI
import Photos

/// Live Photo 页面：
/// - 首次进入自动播放一次（带音效），播完定格到关键帧
/// - 长按屏幕（≥0.35s）可再次播放，次数不限
/// - 全程走 ZoomableLivePhotoView，支持双指缩放浏览细节
struct ShuffleLivePhotoView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let isActive: Bool
    /// 回调给 ViewModel 记录"已播放过"，避免回滑后重播
    let onPlaybackDidEnd: () -> Void
    /// ViewModel 告知本 item 之前是否已播放过
    let hasPlayedBefore: Bool
    var onZoomStateChanged: (Bool) -> Void = { _ in }

    @State private var livePhoto: PHLivePhoto?
    @State private var isLoading = true
    @State private var playTrigger: Int = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let livePhoto {
                    ZoomableLivePhotoView(
                        livePhoto: livePhoto,
                        playTrigger: playTrigger,
                        onPlaybackEnded: onPlaybackDidEnd,
                        onLongPress: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            playTrigger &+= 1
                        },
                        onZoomStateChanged: onZoomStateChanged
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                if isLoading {
                    ProgressView().tint(.white).controlSize(.large)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: isActive) {
            if isActive {
                await activate()
            } else {
                playTrigger = 0
                onZoomStateChanged(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            playTrigger = 0
        }
    }

    private func activate() async {
        // 先用缩略图采样 backdrop 亮度，浮动按钮立即自适应
        let thumb = await services.photoLibrary.thumbnail(
            for: item.asset, size: CGSize(width: 200, height: 200)
        )
        await services.backdrop.sample(image: thumb)

        if livePhoto == nil {
            isLoading = true
            livePhoto = await services.photoLibrary.loadLivePhoto(
                for: item.asset,
                targetSize: AppConstants.Shuffle.fullImageTargetSize
            )
            isLoading = false
        }
        if !hasPlayedBefore {
            playTrigger &+= 1
        }
    }
}
