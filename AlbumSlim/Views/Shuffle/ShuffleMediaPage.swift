import SwiftUI

/// 单页 dispatcher：根据 ShuffleItem.kind 路由到具体媒体渲染视图
struct ShuffleMediaPage: View {
    let item: ShuffleItem
    let isActive: Bool
    let viewModel: ShuffleFeedViewModel
    var onZoomStateChanged: (Bool) -> Void = { _ in }

    var body: some View {
        switch item.kind {
        case .video:
            ShuffleVideoView(item: item, isActive: isActive)
        case .livePhoto:
            ShuffleLivePhotoView(
                item: item,
                isActive: isActive,
                onPlaybackDidEnd: { viewModel.markLivePlayed(item.asset.localIdentifier) },
                hasPlayedBefore: viewModel.playedLiveIds.contains(item.asset.localIdentifier),
                onZoomStateChanged: onZoomStateChanged
            )
        case .photo:
            ShufflePhotoView(
                item: item,
                isActive: isActive,
                viewModel: viewModel,
                onZoomStateChanged: onZoomStateChanged
            )
        }
    }
}
