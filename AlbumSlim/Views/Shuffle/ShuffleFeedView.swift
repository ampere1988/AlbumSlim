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
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: ShuffleItem?
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(items: shareItems)
        }
        .sheet(item: $detailItem) { item in
            ShuffleDetailSheet(item: item)
        }
        .confirmationDialog("删除这个项目？",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("移到「最近删除」", role: .destructive) {
                Task { await performDelete() }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("删除后 30 天内可在系统相册「最近删除」中恢复")
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
            if scrolledID == nil, let first = viewModel.items.first {
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
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showPaywall = true
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pendingDelete = item
        showDeleteConfirm = true
    }

    private func performDelete() async {
        guard let target = pendingDelete else { return }
        pendingDelete = nil
        let size = services.photoLibrary.fileSize(for: target.asset)
        do {
            try await services.photoLibrary.deleteAssets([target.asset])
            services.achievement.recordCleanup(freedSpace: size, deletedCount: 1)
            viewModel.remove(itemID: target.id)
        } catch {
            // 用户在系统弹窗中取消或系统异常，无需特殊处理
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
