import SwiftUI

struct WastePhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var showTrash = false

    var body: some View {
        Group {
            if viewModel.isScanning {
                ProgressLoadingState(phase: AppStrings.scanning, progress: viewModel.scanProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.wasteItems.isEmpty {
                EmptyState("废片", systemImage: AppIcons.waste, tint: Theme.danger) {
                    Button("开始扫描", action: scan)
                        .primaryActionStyle()
                        .frame(maxWidth: 240)
                }
            } else {
                list
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
            totalCount: viewModel.wasteItems.count,
            onSelectAll: { viewModel.selectedForDeletion = Set(viewModel.wasteItems.map(\.id)) },
            onDeselectAll: { viewModel.selectedForDeletion.removeAll() }
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .task {
            if viewModel.wasteItems.isEmpty && !viewModel.isScanning {
                await viewModel.scanWastePhotos(services: services)
            }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            if services.trash.lastChangeKind == .permanentDelete { return }
            Task { await viewModel.reloadWaste(services: services) }
        }
    }

    private var list: some View {
        List {
            SpaceSavedBanner(
                count: viewModel.wasteItems.count,
                size: viewModel.wasteItems.reduce(Int64(0)) { $0 + $1.fileSize }
            )
            .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: Spacing.m, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(viewModel.wasteItems) { item in
                WastePhotoRow(
                    item: item,
                    reason: viewModel.wasteReasons[item.id],
                    services: services,
                    isEditing: isEditing,
                    isSelected: viewModel.selectedForDeletion.contains(item.id),
                    onToggle: { viewModel.toggleSelection(item.id) },
                    onKeep: { viewModel.keepItem(item.id) }
                )
                .padding(Spacing.m)
                .glassSurface(radius: Radius.row)
                .cardListRow()
            }
        }
        .cardListStyle()
        .safeAreaInset(edge: .bottom) {
            if isEditing && !viewModel.selectedForDeletion.isEmpty {
                ActionBar {
                    Button(role: .destructive, action: deleteSelected) {
                        Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedForDeletion.count))")
                    }
                    .primaryActionStyle(destructive: true)
                }
            }
        }
    }

    // MARK: - Actions

    private func scan() {
        Task { await viewModel.scanWastePhotos(services: services) }
    }

    private func deleteSelected() {
        guard services.subscription.isPro else {
            Haptics.proGate()
            services.toast.proRequired()
            showPaywall = true
            return
        }
        Task {
            let batch = await viewModel.deleteSelected(services: services, source: .waste)
            Haptics.moveToTrash()
            services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
                services?.trash.restore(batch.ids)
                services?.toast.restored(batch.ids.count)
            }
            isEditing = false
        }
    }
}
