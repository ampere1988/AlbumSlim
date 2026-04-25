import SwiftUI
import Photos
import UIKit

/// 首页：沉浸式随机浏览本地相册
struct ShuffleFeedView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = ShuffleFeedViewModel()
    @State private var scrolledID: ShuffleItem.ID?
    @AppStorage("shuffleSwipeHintShown") private var hintShown = false
    @State private var showHint = false
    /// 当前媒体（照片 / Live Photo）是否处于缩放状态，用于暂停外层分页滚动
    @State private var mediaZoomActive = false

    // Sheets & Alerts
    @State private var showPaywall = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var isPreparingShare = false
    @State private var detailItem: ShuffleItem?

    private var activeItem: ShuffleItem? {
        guard let scrolledID else { return viewModel.items.first }
        return viewModel.items.first(where: { $0.id == scrolledID })
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    feedScroll(size: geo.size)
                    overlay
                    if showHint { swipeHint }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .task {
            await viewModel.bootstrap(services: services)
            if !hintShown, !viewModel.items.isEmpty {
                withAnimation(.easeIn(duration: 0.3)) { showHint = true }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.4)) { showHint = false }
                hintShown = true
            }
        }
        .onChange(of: services.photoLibrary.libraryVersion) { _, _ in
            Task { await viewModel.refreshAfterLibraryChange(services: services) }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            viewModel.filterTrashedItems(services: services)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(items: shareItems)
        }
        .sheet(item: $detailItem) { item in
            ShuffleDetailSheet(item: item)
        }
    }

    // MARK: - Scroll Feed

    private func feedScroll(size: CGSize) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    ShuffleMediaPage(
                        item: item,
                        isActive: scrolledID == item.id,
                        viewModel: viewModel,
                        onZoomStateChanged: { zoomed in
                            guard scrolledID == item.id else { return }
                            mediaZoomActive = zoomed
                        }
                    )
                    .frame(width: size.width, height: size.height)
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(mediaZoomActive)
        .scrollPosition(id: $scrolledID, anchor: .top)
        .onChange(of: scrolledID) { _, newID in
            mediaZoomActive = false
            viewModel.onPageAppeared(itemID: newID)
            viewModel.updatePrefetchWindow(around: newID, services: services)
        }
        .onAppear {
            // 防御：scrolledID 为 nil 或指向已不存在的 item 时，回落到首项
            guard let first = viewModel.items.first else { return }
            if scrolledID == nil || !viewModel.items.contains(where: { $0.id == scrolledID }) {
                scrolledID = first.id
            }
        }
        .onChange(of: viewModel.items.count) { _, newCount in
            // items 因删除/库变化被清空后又补充时，scrolledID 可能指向已移除项
            guard newCount > 0, let first = viewModel.items.first else { return }
            if scrolledID == nil || !viewModel.items.contains(where: { $0.id == scrolledID }) {
                scrolledID = first.id
            }
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if let active = activeItem {
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    ShuffleMetaOverlay(item: active)
                    ShuffleActionsOverlay(
                        item: active,
                        onDelete: { triggerDelete(active) },
                        onShare: { Task { await triggerShare(active) } },
                        onShowDetail: { detailItem = active }
                    )
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 140)
            }
            .id(active.id)
        }
    }

    // MARK: - First-run swipe hint

    private var swipeHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
            Text("上下滑动切换")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Empty / Permission state

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.authStatus {
        case .authorized, .limited:
            if let msg = viewModel.emptyMessage {
                messageView(icon: "photo.on.rectangle", text: msg)
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        case .denied, .restricted:
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.7))
                Text("需要相册访问权限")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("开启后才能随机浏览你的照片和视频")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Button("去设置") {
                    PermissionManager.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        default:
            ProgressView().tint(.white).controlSize(.large)
        }
    }

    private func messageView(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text(text)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Actions

    private func triggerDelete(_ item: ShuffleItem) {
        guard ProFeatureGate.canClean(isPro: services.subscription.isPro) else {
            Haptics.proGate()
            showPaywall = true
            return
        }
        let size = services.photoLibrary.fileSize(for: item.asset)
        services.trash.moveToTrash(
            assets: [item.asset],
            source: .shuffle,
            mediaType: trashMediaType(for: item)
        )
        Haptics.moveToTrash()
        services.toast.movedToTrash(1)
        services.achievement.recordCleanup(freedSpace: size, deletedCount: 1)
        viewModel.remove(itemID: item.id)
    }

    private func trashMediaType(for item: ShuffleItem) -> TrashedMediaType {
        switch item.asset.mediaType {
        case .video: return .video
        case .image:
            return item.asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : .photo
        default: return .photo
        }
    }

    private func triggerShare(_ item: ShuffleItem) async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        if let image = await services.photoLibrary.loadFullImage(
            for: item.asset,
            size: AppConstants.Shuffle.shareImageSize
        ) {
            shareItems = [image]
            showShareSheet = true
        }
    }

}

// MARK: - UIActivityViewController SwiftUI 包装

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
