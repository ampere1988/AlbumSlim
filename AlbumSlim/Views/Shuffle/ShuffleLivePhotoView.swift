import SwiftUI
import PhotosUI
import Photos

/// Live Photo 页面：首次进入自动播放一次（带音效），播完定格到关键帧
struct ShuffleLivePhotoView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let isActive: Bool
    /// 回调给 ViewModel 记录"已播放过"，避免回滑后重播
    let onPlaybackDidEnd: () -> Void
    /// ViewModel 告知本 item 之前是否已播放过
    let hasPlayedBefore: Bool

    @State private var livePhoto: PHLivePhoto?
    @State private var isLoading = true
    @State private var shouldAutoPlay = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let livePhoto {
                    LivePhotoRepresentable(
                        livePhoto: livePhoto,
                        shouldPlay: shouldAutoPlay,
                        onPlaybackEnded: handlePlaybackEnded
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
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
                shouldAutoPlay = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            shouldAutoPlay = false
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
            let scale = UIScreen.main.scale
            let bounds = UIScreen.main.bounds.size
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            livePhoto = await services.photoLibrary.loadLivePhoto(for: item.asset, targetSize: size)
            isLoading = false
        }
        if !hasPlayedBefore {
            shouldAutoPlay = true
        }
    }

    private func handlePlaybackEnded() {
        shouldAutoPlay = false
        onPlaybackDidEnd()
    }
}

// MARK: - PHLivePhotoView SwiftUI 包装

private struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let shouldPlay: Bool
    let onPlaybackEnded: () -> Void

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isMuted = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        if shouldPlay, !context.coordinator.hasStarted {
            context.coordinator.hasStarted = true
            uiView.startPlayback(with: .full)
        } else if !shouldPlay {
            uiView.stopPlayback()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackEnded: onPlaybackEnded)
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var onPlaybackEnded: () -> Void
        var hasStarted = false

        init(onPlaybackEnded: @escaping () -> Void) {
            self.onPlaybackEnded = onPlaybackEnded
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView,
                           didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            onPlaybackEnded()
        }
    }
}
