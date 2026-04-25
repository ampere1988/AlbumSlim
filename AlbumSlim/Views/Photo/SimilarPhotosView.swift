import SwiftUI

struct SimilarPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var showTrash = false

    private var allItems: [MediaItem] { viewModel.similarGroups.flatMap(\.items) }

    var body: some View {
        Group {
            if viewModel.isScanning {
                ProgressLoadingState(phase: AppStrings.scanning, progress: viewModel.scanProgress)
            } else if viewModel.similarGroups.isEmpty {
                EmptyState("相似照片", systemImage: AppIcons.similar) {
                    Button("开始扫描") {
                        Task { await viewModel.scanSimilarPhotos(services: services) }
                    }
                    .primaryActionStyle()
                }
            } else {
                List {
                    SpaceSavedBanner(
                        count: allItems.count,
                        size: viewModel.similarGroups.reduce(0) { $0 + $1.savableSize }
                    )
                    .listRowInsets(EdgeInsets())

                    ForEach(Array(viewModel.similarGroups.enumerated()), id: \.element.id) { _, group in
                        Section {
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
                                .font(.footnote)
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("相似组 · \(group.items.count) 张 · 可省 \(group.savableSize.formattedFileSize)")
                                if let range = timeRange(for: group) {
                                    Text(range)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
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
                                let count = viewModel.selectedForDeletion.count
                                Task {
                                    await viewModel.deleteSelected(services: services, source: .similar)
                                    Haptics.moveToTrash()
                                    services.toast.movedToTrash(count)
                                    isEditing = false
                                }
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedForDeletion.count))")
                                    .frame(maxWidth: .infinity)
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
            }
        }
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
            totalCount: allItems.count,
            onSelectAll: {
                viewModel.selectedForDeletion = Set(allItems.map(\.id))
            },
            onDeselectAll: {
                viewModel.selectedForDeletion.removeAll()
            }
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .task {
            if viewModel.similarGroups.isEmpty && !viewModel.isScanning {
                await viewModel.scanSimilarPhotos(services: services)
            }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
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
