import SwiftUI
import Photos

struct LargePhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var allPhotos: [MediaItem] = []
    @State private var isLoading = false
    @State private var selectedIDs: Set<String> = []
    @State private var showPaywall = false
    @State private var showTrash = false
    @State private var isEditing = false
    @State private var thresholdMB: Int = 10

    private static let thresholdOptions = [50, 30, 15, 10, 8, 5, 3]

    private var thresholdBytes: Int64 { Int64(thresholdMB) * 1024 * 1024 }

    private var largePhotos: [MediaItem] {
        allPhotos.filter { $0.fileSize >= thresholdBytes }
    }

    var body: some View {
        Group {
            if isLoading && allPhotos.isEmpty {
                LoadingState(AppStrings.scanning)
            } else if allPhotos.isEmpty {
                EmptyState("超大照片", systemImage: AppIcons.largePhoto,
                           description: "没有超过 \(thresholdMB) MB 的照片",
                           tint: Theme.accentSecondary) {
                    VStack(spacing: Spacing.m) {
                        thresholdPicker
                        Button("开始扫描") {
                            Task { await loadAllPhotos() }
                        }
                        .primaryActionStyle()
                        .frame(maxWidth: 240)
                    }
                }
            } else if largePhotos.isEmpty {
                EmptyState("超大照片", systemImage: AppIcons.largePhoto,
                           description: "没有超过 \(thresholdMB) MB 的照片，试试降低阈值",
                           tint: Theme.accentSecondary) {
                    thresholdPicker
                }
            } else {
                List {
                    HStack {
                        LibrarySummaryHeader(
                            countText: String(localized: "\(largePhotos.count) 张超大照片"),
                            sizeText: totalSize.formattedFileSize,
                            systemImage: AppIcons.largePhoto,
                            tint: Theme.accentSecondary
                        )
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l,
                                              bottom: Spacing.s, trailing: Spacing.l))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    thresholdPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardListRow()

                    ForEach(largePhotos) { item in
                        LargePhotoRow(
                            item: item,
                            isSelected: selectedIDs.contains(item.id),
                            isEditing: isEditing,
                            services: services
                        ) {
                            toggleSelection(item.id)
                        }
                        .padding(Spacing.m)
                        .glassSurface(radius: Radius.row)
                        .cardListRow()
                    }
                }
                .cardListStyle()
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !selectedIDs.isEmpty {
                        let savableBytes = largePhotos
                            .filter { selectedIDs.contains($0.id) }
                            .reduce(Int64(0)) { $0 + $1.fileSize }

                        ActionBar {
                            Button(role: .destructive) {
                                guard services.subscription.isPro else {
                                    Haptics.proGate()
                                    services.toast.proRequired()
                                    showPaywall = true
                                    return
                                }
                                let toDelete = largePhotos.filter { selectedIDs.contains($0.id) }
                                let assets = toDelete.map(\.asset)
                                let batch = services.trash.moveToTrash(assets: assets, source: .largePhoto, mediaType: .photo)
                                Haptics.moveToTrash()
                                services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
                                    services?.trash.restore(batch.ids)
                                    services?.toast.restored(batch.ids.count)
                                }
                                allPhotos.removeAll { selectedIDs.contains($0.id) }
                                selectedIDs.removeAll()
                                isEditing = false
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(selectedIDs.count)) · \(AppStrings.releasable(savableBytes))")
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
            selectedCount: selectedIDs.count,
            totalCount: largePhotos.count,
            onSelectAll: { selectedIDs = Set(largePhotos.map(\.id)) },
            onDeselectAll: { selectedIDs.removeAll() }
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .onChange(of: thresholdMB) {
            selectedIDs = selectedIDs.filter { id in largePhotos.contains { $0.id == id } }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            if services.trash.lastChangeKind == .permanentDelete { return }
            Task { await loadAllPhotos() }
        }
        .task {
            await loadAllPhotos()
        }
        .onChange(of: services.photoLibrary.libraryVersion) {
            Task { await loadAllPhotos() }
        }
    }

    private var thresholdPicker: some View {
        Menu {
            ForEach(Self.thresholdOptions, id: \.self) { mb in
                Button {
                    thresholdMB = mb
                } label: {
                    if mb == thresholdMB {
                        Label("\(mb) MB", systemImage: "checkmark")
                    } else {
                        Text("\(mb) MB")
                    }
                }
            }
        } label: {
            Label("≥ \(thresholdMB) MB", systemImage: "line.3.horizontal.decrease.circle")
                .font(AppFont.label.bold())
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Spacing.m)
                .frame(height: 36)
                .background(Capsule().fill(Theme.accentMuted))
        }
    }

    private var totalSize: Int64 {
        largePhotos.reduce(0) { $0 + $1.fileSize }
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func loadAllPhotos() async {
        guard !isLoading else { return }
        await services.prepareAsync()

        let coordinator = services.cleanupCoordinator
        let version = services.photoLibrary.libraryVersion
        let cachedItems = coordinator.groups(ofType: .largePhoto).flatMap(\.items)
        let trashedIDs = services.trash.trashedAssetIDs
        allPhotos = cachedItems
            .filter { !trashedIDs.contains($0.id) }
            .sorted { $0.fileSize > $1.fileSize }
        if coordinator.isCategoryFresh(.largePhoto, libraryVersion: version) { return }

        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let items = await services.photoLibrary.buildMediaItems(from: fetchResult)

        let minThreshold = Int64(Self.thresholdOptions.last ?? 3) * 1024 * 1024
        allPhotos = items
            .filter { $0.fileSize >= minThreshold && !trashedIDs.contains($0.id) }
            .sorted { $0.fileSize > $1.fileSize }

        if !allPhotos.isEmpty {
            let group = CleanupGroup(type: .largePhoto, items: allPhotos, bestItemID: nil)
            coordinator.replaceGroups([group], ofType: .largePhoto)
        } else {
            coordinator.replaceGroups([], ofType: .largePhoto)
        }
        coordinator.markCategoryScanned(.largePhoto, libraryVersion: version)
    }
}
