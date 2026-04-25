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
            if isLoading {
                LoadingState(AppStrings.scanning)
            } else if allPhotos.isEmpty {
                EmptyState("超大照片", systemImage: AppIcons.largePhoto, description: "没有超过 \(thresholdMB) MB 的照片") {
                    VStack(spacing: 12) {
                        thresholdPicker
                        Button("开始扫描") {
                            Task { await loadAllPhotos() }
                        }
                        .primaryActionStyle()
                    }
                }
            } else if largePhotos.isEmpty {
                EmptyState("超大照片", systemImage: AppIcons.largePhoto, description: "没有超过 \(thresholdMB) MB 的照片，试试降低阈值") {
                    thresholdPicker
                }
            } else {
                List {
                    Section {
                        thresholdPicker
                    }

                    Section {
                        Text("共 \(largePhotos.count) 张 · \(totalSize.formattedFileSize)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(largePhotos) { item in
                        LargePhotoRow(
                            item: item,
                            isSelected: selectedIDs.contains(item.id),
                            isEditing: isEditing,
                            services: services
                        ) {
                            toggleSelection(item.id)
                        }
                    }
                }
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
                                let count = selectedIDs.count
                                let toDelete = largePhotos.filter { selectedIDs.contains($0.id) }
                                let assets = toDelete.map(\.asset)
                                let freedSize = toDelete.reduce(Int64(0)) { $0 + $1.fileSize }
                                let _ = services.achievement.recordCleanup(freedSpace: freedSize, deletedCount: count)
                                services.trash.moveToTrash(assets: assets, source: .largePhoto, mediaType: .photo)
                                Haptics.moveToTrash()
                                services.toast.movedToTrash(count)
                                allPhotos.removeAll { selectedIDs.contains($0.id) }
                                selectedIDs.removeAll()
                                isEditing = false
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(selectedIDs.count)) · \(AppStrings.releasable(savableBytes))")
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
            if allPhotos.isEmpty && !isLoading {
                await loadAllPhotos()
            }
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
                .font(.footnote)
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
        let coordinator = services.cleanupCoordinator
        let version = services.photoLibrary.libraryVersion
        if coordinator.isCategoryFresh(.largePhoto, libraryVersion: version) {
            let cached = coordinator.groups(ofType: .largePhoto)
            let cachedItems = cached.flatMap(\.items)
            if !cachedItems.isEmpty {
                let trashedIDs = services.trash.trashedAssetIDs
                allPhotos = cachedItems.filter { !trashedIDs.contains($0.id) }.sorted { $0.fileSize > $1.fileSize }
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let items = await services.photoLibrary.buildMediaItems(from: fetchResult)

        let minThreshold = Int64(Self.thresholdOptions.last ?? 3) * 1024 * 1024
        let trashedIDs = services.trash.trashedAssetIDs
        allPhotos = items
            .filter { $0.fileSize >= minThreshold && !trashedIDs.contains($0.id) }
            .sorted { $0.fileSize > $1.fileSize }

        for group in coordinator.groups(ofType: .largePhoto) {
            coordinator.removeGroup(group)
        }
        if !allPhotos.isEmpty {
            let group = CleanupGroup(type: .largePhoto, items: allPhotos, bestItemID: nil)
            coordinator.addGroups([group])
        }
        coordinator.markCategoryScanned(.largePhoto, libraryVersion: version)
    }
}

private struct LargePhotoRow: View {
    let item: MediaItem
    let isSelected: Bool
    let isEditing: Bool
    let services: AppServiceContainer
    let onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipped()
                } else {
                    Rectangle().fill(.quaternary)
                        .frame(width: 72, height: 72)
                        .overlay { ProgressView() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileSizeText)
                    .font(.headline)
                Text(item.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = item.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .red : .secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEditing { onTap() } }
        .task {
            image = await services.photoLibrary.thumbnail(for: item.asset, size: CGSize(width: 200, height: 200))
        }
    }
}
