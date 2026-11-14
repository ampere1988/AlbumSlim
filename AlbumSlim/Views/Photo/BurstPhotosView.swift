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
            if isLoading && burstGroups.isEmpty {
                LoadingState(AppStrings.scanning)
            } else if burstGroups.isEmpty {
                EmptyState("连拍照片", systemImage: AppIcons.burst, tint: Theme.burst) {
                    Button("开始扫描") {
                        Task { await loadBursts() }
                    }
                    .primaryActionStyle()
                    .frame(maxWidth: 240)
                }
            } else {
                List {
                    ForEach(Array(burstGroups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            VStack(spacing: Spacing.m) {
                                ScrollView(.horizontal) {
                                    HStack(spacing: Spacing.s) {
                                        ForEach(group.items) { item in
                                            BurstThumbnail(
                                                item: item,
                                                isBest: item.id == group.bestItemID,
                                                services: services
                                            )
                                        }
                                    }
                                }
                                .scrollIndicators(.hidden)

                                Button {
                                    keepOnlyBestGated(group: group)
                                } label: {
                                    Label("只保留最佳", systemImage: AppIcons.checkmarkCircle)
                                        .font(AppFont.label.bold())
                                        .foregroundStyle(Theme.danger)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background {
                                            RoundedRectangle(cornerRadius: Radius.row)
                                                .fill(Theme.dangerMuted)
                                        }
                                }
                                .buttonStyle(PressableCardStyle())
                            }
                            .padding(Spacing.m)
                            .glassSurface()
                            .cardListRow()
                        } header: {
                            PhotoGroupHeader(
                                index: index,
                                count: group.items.count,
                                savableSize: group.savableSize,
                                subtitle: group.items.first?.creationDate?
                                    .formatted(date: .abbreviated, time: .shortened),
                                tint: Theme.burst
                            )
                            .cardListRow()
                        }
                    }
                }
                .cardListStyle()
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .task {
            await loadBursts()
        }
        .onChange(of: services.photoLibrary.libraryVersion) {
            Task { await loadBursts() }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            if services.trash.lastChangeKind == .permanentDelete { return }
            Task { await loadBursts() }
        }
    }

    private func loadBursts() async {
        guard !isLoading else { return }
        await services.prepareAsync()

        let coordinator = services.cleanupCoordinator
        let version = services.photoLibrary.libraryVersion
        let cached = coordinator.groups(ofType: .burst)
        let trashedIDs = services.trash.trashedAssetIDs
        burstGroups = cached.compactMap { group in
            var g = group
            g.items = g.items.filter { !trashedIDs.contains($0.id) }
            return g.items.count > 1 ? g : nil
        }
        if coordinator.isCategoryFresh(.burst, libraryVersion: version) { return }

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

        burstGroups = groups.values
            .map { items in items.filter { !trashedIDs.contains($0.id) } }
            .filter { $0.count > 1 }
            .map { items in
                let best = items.max(by: { $0.fileSize < $1.fileSize })
                return CleanupGroup(type: .burst, items: items, bestItemID: best?.id)
            }

        coordinator.replaceGroups(burstGroups, ofType: .burst)
        coordinator.markCategoryScanned(.burst, libraryVersion: version)
    }

    private func keepOnlyBestGated(group: CleanupGroup) {
        guard ProFeatureGate.canClean(isPro: services.subscription.isPro) else {
            Haptics.proGate()
            services.toast.proRequired()
            showPaywall = true
            return
        }
        keepOnlyBest(id: group.id)
    }

    private func keepOnlyBest(id: UUID) {
        guard let group = burstGroups.first(where: { $0.id == id }) else { return }
        let toDelete = group.items.filter { $0.id != group.bestItemID }
        guard !toDelete.isEmpty else { return }
        let assets = toDelete.map(\.asset)
        burstGroups.removeAll { $0.id == id }

        let batch = services.trash.moveToTrash(assets: assets, source: .burst, mediaType: .photo)
        Haptics.moveToTrash()
        services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
            services?.trash.restore(batch.ids)
            services?.toast.restored(batch.ids.count)
        }
    }
}
