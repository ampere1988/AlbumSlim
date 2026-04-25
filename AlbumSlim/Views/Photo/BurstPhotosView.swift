import SwiftUI
import Photos

struct BurstPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var burstGroups: [CleanupGroup] = []
    @State private var isLoading = false
    @State private var showPaywall = false
    @State private var showTrash = false

    var body: some View {
        Group {
            if isLoading {
                LoadingState(AppStrings.scanning)
            } else if burstGroups.isEmpty {
                EmptyState("连拍照片", systemImage: AppIcons.burst) {
                    Button("开始扫描") {
                        Task { await loadBursts() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(Array(burstGroups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(group.items) { item in
                                        BurstThumbnail(
                                            item: item,
                                            isBest: item.id == group.bestItemID,
                                            services: services
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            Button {
                                if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                    keepOnlyBest(id: group.id)
                                } else {
                                    Haptics.proGate()
                                    services.toast.proRequired()
                                    showPaywall = true
                                }
                            } label: {
                                Label("只保留最佳", systemImage: AppIcons.checkmarkCircle)
                            }
                            .font(.footnote)
                            .foregroundStyle(.red)
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("连拍组 · \(group.items.count) 张 · 可省 \(group.savableSize.formattedFileSize)")
                                if let date = group.items.first?.creationDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .task {
            if burstGroups.isEmpty && !isLoading {
                await loadBursts()
            }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            Task { await loadBursts() }
        }
    }

    private func loadBursts() async {
        let coordinator = services.cleanupCoordinator
        let version = services.photoLibrary.libraryVersion
        if coordinator.isCategoryFresh(.burst, libraryVersion: version) {
            let cached = coordinator.groups(ofType: .burst)
            if !cached.isEmpty {
                let trashedIDs = services.trash.trashedAssetIDs
                burstGroups = cached.compactMap { group in
                    var g = group
                    g.items = g.items.filter { !trashedIDs.contains($0.id) }
                    return g.items.count > 1 ? g : nil
                }
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchBurstAssets()
        let items = await services.photoLibrary.buildMediaItems(from: fetchResult)

        var groups: [String: [MediaItem]] = [:]
        for item in items {
            if let burstID = item.asset.burstIdentifier {
                groups[burstID, default: []].append(item)
            }
        }

        let trashedIDs = services.trash.trashedAssetIDs
        burstGroups = groups.values
            .map { items in items.filter { !trashedIDs.contains($0.id) } }
            .filter { $0.count > 1 }
            .map { items in
                let best = items.max(by: { $0.fileSize < $1.fileSize })
                return CleanupGroup(type: .burst, items: items, bestItemID: best?.id)
            }

        coordinator.markCategoryScanned(.burst, libraryVersion: version)
    }

    private func keepOnlyBest(id: UUID) {
        guard let group = burstGroups.first(where: { $0.id == id }) else { return }
        let toDelete = group.items.filter { $0.id != group.bestItemID }
        guard !toDelete.isEmpty else { return }
        let assets = toDelete.map(\.asset)
        burstGroups.removeAll { $0.id == id }

        services.trash.moveToTrash(assets: assets, source: .burst, mediaType: .photo)
        Haptics.moveToTrash()
        services.toast.movedToTrash(assets.count)
    }
}

private struct BurstThumbnail: View {
    let item: MediaItem
    let isBest: Bool
    let services: AppServiceContainer
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
            } else {
                Rectangle().fill(.quaternary)
                    .frame(width: 100, height: 100)
                    .overlay { ProgressView() }
            }

            if isBest {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .padding(4)
                    .background(.yellow, in: Circle())
                    .padding(4)
            }

            VStack {
                Spacer()
                Text(item.fileSizeText)
                    .font(.caption2)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
        .overlay {
            if isBest {
                RoundedRectangle(cornerRadius: Radius.thumb).stroke(.yellow, lineWidth: 2)
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(for: item.asset, size: CGSize(width: 200, height: 200))
        }
    }
}
