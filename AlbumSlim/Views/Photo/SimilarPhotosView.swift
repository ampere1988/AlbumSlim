import SwiftUI

struct SimilarPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var showTrash = false

    private var allItems: [MediaItem] { viewModel.similarGroups.flatMap(\.items) }
    private var suggestedItems: [MediaItem] {
        viewModel.similarGroups.flatMap { group in
            group.items.filter { $0.id != group.bestItemID }
        }
    }

    var body: some View {
        Group {
            if viewModel.isScanning && viewModel.similarGroups.isEmpty {
                ProgressLoadingState(phase: AppStrings.scanning, progress: viewModel.scanProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.similarGroups.isEmpty {
                EmptyState("相似照片", systemImage: AppIcons.similar, tint: Theme.photo) {
                    Button("开始扫描") {
                        Task { await viewModel.scanSimilarPhotos(services: services) }
                    }
                    .primaryActionStyle()
                    .frame(maxWidth: 240)
                }
            } else {
                List {
                    SpaceSavedBanner(
                        count: allItems.count,
                        size: viewModel.similarGroups.reduce(0) { $0 + $1.savableSize }
                    )
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0,
                                              bottom: Spacing.m, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ForEach(Array(viewModel.similarGroups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            VStack(spacing: Spacing.m) {
                                MediaGridView(
                                    items: group.items,
                                    bestItemID: group.bestItemID,
                                    services: services,
                                    isSelectable: isEditing,
                                    selection: $viewModel.selectedForDeletion
                                )

                                if isEditing {
                                    let isFullySelected = viewModel.isGroupFullySelectedExceptBest(group)
                                    Button(isFullySelected ? "取消选中本组" : "选中除最佳外全部") {
                                        if isFullySelected {
                                            viewModel.deselectGroup(group)
                                        } else {
                                            viewModel.selectAllExceptBest(in: group)
                                        }
                                    }
                                    .font(AppFont.label.bold())
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                            }
                            .padding(Spacing.m)
                            .glassSurface()
                            .cardListRow()
                        } header: {
                            PhotoGroupHeader(
                                index: index,
                                count: group.items.count,
                                savableSize: group.savableSize,
                                subtitle: timeRange(for: group),
                                tint: Theme.photo
                            )
                            .cardListRow()
                        }
                    }
                }
                .cardListStyle()
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !viewModel.selectedForDeletion.isEmpty {
                        ActionBar {
                            Button(role: .destructive) {
                                guard services.subscription.isPro else {
                                    Haptics.proGate()
                                    services.toast.proRequired()
                                    showPaywall = true
                                    return
                                }
                                Task {
                                    let batch = await viewModel.deleteSelected(services: services, source: .similar)
                                    Haptics.moveToTrash()
                                    services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
                                        services?.trash.restore(batch.ids)
                                        services?.toast.restored(batch.ids.count)
                                    }
                                    isEditing = false
                                }
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedForDeletion.count))")
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
            }
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TrashToolbarButton(count: services.trash.trashedItems.count) {
                    showTrash = true
                }
            }
        }
        .selectionToolbar(
            isEditing: $isEditing,
            selectedCount: viewModel.selectedForDeletion.count,
            totalCount: suggestedItems.count,
            onSelectAll: {
                viewModel.selectedForDeletion = Set(suggestedItems.map(\.id))
            },
            onDeselectAll: {
                viewModel.selectedForDeletion.removeAll()
            }
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .onChange(of: isEditing) { _, editing in
            if editing {
                viewModel.autoSelectAllExceptBest()
            } else {
                viewModel.selectedForDeletion.removeAll()
            }
        }
        .task {
            await viewModel.scanSimilarPhotos(services: services)
        }
        .onChange(of: services.photoLibrary.libraryVersion) {
            Task { await viewModel.scanSimilarPhotos(services: services) }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            if services.trash.lastChangeKind == .permanentDelete { return }
            Task { await viewModel.reloadSimilar(services: services) }
        }
    }

    private func timeRange(for group: CleanupGroup) -> String? {
        let dates = group.items.compactMap(\.creationDate).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm"
        return "\(fmt.string(from: first)) ~ \(fmt.string(from: last))"
    }
}
