import SwiftUI
import Photos

struct VideoListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = VideoManagerViewModel()
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var showTrash = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    LoadingState(AppStrings.loading)
                } else if viewModel.sortedVideos.isEmpty {
                    EmptyState("视频", systemImage: AppIcons.video)
                } else {
                    List {
                        Section {
                            HStack {
                                Text("共 \(viewModel.sortedVideos.count) 个视频")
                                Spacer()
                                Text("占用 \(viewModel.totalVideoSize.formattedFileSize)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }

                        ForEach(viewModel.sortedVideos) { video in
                            if isEditing {
                                VideoRow(item: video, services: services, isSelected: viewModel.selectedVideos.contains(video.id))
                                    .onTapGesture { viewModel.toggleSelection(video.id) }
                            } else {
                                NavigationLink(value: video.id) {
                                    VideoRow(item: video, services: services)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(AppStrings.moveToTrash, role: .destructive) {
                                        if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                            let count = 1
                                            viewModel.deleteVideo(video, services: services)
                                            Haptics.moveToTrash()
                                            services.toast.movedToTrash(count)
                                        } else {
                                            Haptics.proGate()
                                            services.toast.proRequired()
                                            showPaywall = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { videoID in
                        if let video = viewModel.sortedVideos.first(where: { $0.id == videoID }) {
                            VideoCompressView(item: video)
                        } else {
                            Color.clear
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if isEditing && !viewModel.selectedVideos.isEmpty {
                            ActionBar {
                                Button {
                                    Haptics.tap()
                                    if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                        Task {
                                            try? await viewModel.compressSelected(services: services)
                                        }
                                    } else {
                                        Haptics.proGate()
                                        services.toast.proRequired()
                                        showPaywall = true
                                    }
                                } label: {
                                    Text("压缩 \(AppStrings.items(viewModel.selectedVideos.count))")
                                        .frame(maxWidth: .infinity)
                                }
                                .secondaryActionStyle()

                                Button(role: .destructive) {
                                    if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                        let count = viewModel.selectedVideos.count
                                        viewModel.deleteSelected(services: services)
                                        Haptics.moveToTrash()
                                        services.toast.movedToTrash(count)
                                        isEditing = false
                                    } else {
                                        Haptics.proGate()
                                        services.toast.proRequired()
                                        showPaywall = true
                                    }
                                } label: {
                                    Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedVideos.count))")
                                        .frame(maxWidth: .infinity)
                                }
                                .primaryActionStyle(destructive: true)
                            }
                        }
                    }
                }
            }
            .navigationTitle("视频管理")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        VideoSuggestionsView(viewModel: viewModel)
                    } label: {
                        Label("清理建议", systemImage: "lightbulb")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                if viewModel.sortOrder == order {
                                    Label(order.localizedName, systemImage: "checkmark")
                                } else {
                                    Text(order.localizedName)
                                }
                            }
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TrashToolbarButton(count: services.trash.trashedItems.count) {
                        showTrash = true
                    }
                }
            }
            .selectionToolbar(
                isEditing: $isEditing,
                selectedCount: viewModel.selectedVideos.count,
                totalCount: viewModel.sortedVideos.count,
                onSelectAll: { viewModel.selectedVideos = Set(viewModel.sortedVideos.map(\.id)) },
                onDeselectAll: { viewModel.selectedVideos.removeAll() }
            )
            .task { await viewModel.loadVideos(services: services) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showTrash) { GlobalTrashView() }
        }
    }
}

private struct VideoRow: View {
    let item: MediaItem
    let services: AppServiceContainer
    var isSelected: Bool = false
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }

            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 60, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.thumb))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "未知日期")
                    .font(.subheadline)
                Text(item.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.fileSizeText)
                    .font(.subheadline.bold())
                Text(formatDuration(item.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            thumbnail = await services.photoLibrary.thumbnail(for: item.asset, size: CGSize(width: 120, height: 88))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
