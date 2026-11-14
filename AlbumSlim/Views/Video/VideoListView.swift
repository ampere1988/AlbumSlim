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
                        LibrarySummaryHeader(
                            countText: String(localized: "\(viewModel.sortedVideos.count) 个视频"),
                            sizeText: viewModel.totalVideoSize.formattedFileSize,
                            systemImage: AppIcons.video,
                            tint: Theme.video
                        )
                        .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l,
                                                  bottom: Spacing.m, trailing: Spacing.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        ForEach(viewModel.sortedVideos) { video in
                            if isEditing {
                                VideoRow(
                                    item: video,
                                    services: services,
                                    isEditing: true,
                                    isSelected: viewModel.selectedVideos.contains(video.id)
                                )
                                    .padding(.horizontal, Spacing.m)
                                    .glassSurface(radius: Radius.row)
                                    .contentShape(.rect)
                                    .onTapGesture { viewModel.toggleSelection(video.id) }
                                    .cardListRow()
                            } else {
                                NavigationLink(value: video.id) {
                                    VideoRow(item: video, services: services)
                                        .padding(.horizontal, Spacing.m)
                                }
                                .glassSurface(radius: Radius.row)
                                .cardListRow()
                                .swipeActions(edge: .trailing) {
                                    Button(AppStrings.moveToTrash, role: .destructive) {
                                        if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                            let batch = viewModel.deleteVideo(video, services: services)
                                            Haptics.moveToTrash()
                                            services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
                                                services?.trash.restore(batch.ids)
                                                services?.toast.restored(batch.ids.count)
                                            }
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
                    .cardListStyle()
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
                                        let batch = viewModel.deleteSelected(services: services)
                                        Haptics.moveToTrash()
                                        services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
                                            services?.trash.restore(batch.ids)
                                            services?.toast.restored(batch.ids.count)
                                        }
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
            .onChange(of: services.trash.trashedItems.count) { _, _ in
                if services.trash.lastChangeKind == .permanentDelete { return }
                Task { await viewModel.reload(services: services) }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showTrash) { GlobalTrashView() }
        }
    }
}
