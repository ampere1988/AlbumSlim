import SwiftUI
import Photos

struct VideoListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = VideoManagerViewModel()
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载视频...")
                } else if viewModel.sortedVideos.isEmpty {
                    ContentUnavailableView("没有视频", systemImage: "video.slash")
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
                            if viewModel.isEditing {
                                VideoRow(item: video, services: services, isSelected: viewModel.selectedVideos.contains(video.id))
                                    .onTapGesture { viewModel.toggleSelection(video.id) }
                            } else {
                                NavigationLink(value: video.id) {
                                    VideoRow(item: video, services: services)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("删除", role: .destructive) {
                                        if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                            viewModel.deleteVideo(video, services: services)
                                        } else {
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
                        if viewModel.isEditing && !viewModel.selectedVideos.isEmpty {
                            batchActionBar
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
                    Button(viewModel.isEditing ? "完成" : "选择") {
                        viewModel.isEditing.toggle()
                        if !viewModel.isEditing {
                            viewModel.selectedVideos.removeAll()
                        }
                    }
                }
            }
            .task { await viewModel.loadVideos(services: services) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var batchActionBar: some View {
        HStack {
            Text("已选 \(viewModel.selectedVideos.count) 个")
                .font(.subheadline)
            Spacer()
            Button("批量压缩") {
                if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                    Task {
                        try? await viewModel.compressSelected(services: services)
                    }
                } else {
                    showPaywall = true
                }
            }
            .buttonStyle(.bordered)
            Button("删除", role: .destructive) {
                if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                    showDeleteConfirm = true
                } else {
                    showPaywall = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "确定删除 \(viewModel.selectedVideos.count) 个视频？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                viewModel.deleteSelected(services: services)
            }
        } message: {
            Text("删除后可在\"最近删除\"中恢复")
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

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
