import SwiftUI
import AVFoundation
import Photos

/// 视频页面：自动播放 + 循环 + 带声；失去 active 时立即暂停并释放 player
struct ShuffleVideoView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let isActive: Bool

    @State private var controller = VideoController()
    @State private var isLoading = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                VideoPlayerLayerView(player: controller.player)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: isActive) {
            if isActive {
                await activate()
            } else {
                controller.pause()
            }
        }
        .onDisappear {
            controller.unload()
            isLoading = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shuffleTabLeft)) { _ in
            controller.pause()
        }
    }

    private func activate() async {
        // 先用缩略图采样 backdrop 亮度，浮动按钮可立即自适应
        let thumb = await services.photoLibrary.thumbnail(
            for: item.asset, size: CGSize(width: 200, height: 200)
        )
        await services.backdrop.sample(image: thumb)

        if !controller.isLoaded {
            isLoading = true
            if let playerItem = await services.photoLibrary.loadPlayerItem(for: item.asset) {
                controller.load(playerItem: playerItem)
            }
            isLoading = false
        }
        controller.play()
    }
}

// MARK: - VideoController

@MainActor
@Observable
final class VideoController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private(set) var isLoaded = false

    init() {
        self.player = AVQueuePlayer()
        self.player.isMuted = false
    }

    func load(playerItem: AVPlayerItem) {
        // AVPlayerLooper 必须强持有才能持续循环
        looper = AVPlayerLooper(player: player, templateItem: playerItem)
        isLoaded = true
    }

    func play() {
        guard isLoaded else { return }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func unload() {
        player.pause()
        player.removeAllItems()
        looper = nil
        isLoaded = false
    }
}

// MARK: - AVPlayerLayer SwiftUI 包装

struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - Notification

extension Notification.Name {
    /// 用户切离浏览 tab(tag 0) 时发送，用于暂停视频/Live Photo 播放
    static let shuffleTabLeft = Notification.Name("shuffleTabLeft")
}
