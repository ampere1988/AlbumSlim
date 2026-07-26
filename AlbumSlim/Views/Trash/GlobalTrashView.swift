import SwiftUI
import Photos

struct GlobalTrashView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var selectedIDs: Set<String> = []
    @State private var showPermanentDeleteConfirm = false
    @State private var showEmptyAllConfirm = false

    private var items: [TrashedItem] { services.trash.trashedItems }
    private var selectedItems: [TrashedItem] {
        items.filter { selectedIDs.contains($0.id) }
    }
    private var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("垃圾桶")
                .toolbar {
                    if !items.isEmpty && !isEditing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button(AppStrings.emptyTrash, role: .destructive) {
                                    showEmptyAllConfirm = true
                                }
                            } label: {
                                Image(systemName: AppIcons.more)
                            }
                        }
                    }
                }
                .selectionToolbar(
                    isEditing: $isEditing,
                    selectedCount: selectedIDs.count,
                    totalCount: items.count,
                    onSelectAll: { selectedIDs = Set(items.map(\.id)) },
                    onDeselectAll: { selectedIDs.removeAll() }
                )
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !selectedIDs.isEmpty {
                        ActionBar {
                            Button {
                                Haptics.tap()
                                services.trash.restore(selectedIDs)
                                services.toast.restored(selectedIDs.count)
                                selectedIDs.removeAll()
                            } label: {
                                Text("\(AppStrings.restore) \(AppStrings.items(selectedIDs.count))")
                            }
                            .secondaryActionStyle()

                            Button(role: .destructive) {
                                showPermanentDeleteConfirm = true
                            } label: {
                                Text("\(AppStrings.permanentlyDelete) \(AppStrings.items(selectedIDs.count))")
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
                .confirmationDialog(
                    AppStrings.confirmPermanentDeleteTitle(selectedIDs.count),
                    isPresented: $showPermanentDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button(AppStrings.permanentlyDelete, role: .destructive) {
                        let toDelete = selectedIDs
                        let freed = selectedSize
                        Task {
                            do {
                                try await services.trash.permanentlyDelete(toDelete, photoLibrary: services.photoLibrary)
                            } catch {
                                handlePermanentDeleteFailure(error)
                                return
                            }
                            await MainActor.run {
                                Haptics.permanentDelete()
                                services.toast.permanentlyDeleted(toDelete.count, freed: freed)
                                selectedIDs.removeAll()
                                if items.isEmpty { isEditing = false }
                                recordCleanupAndCelebrate(freedBytes: freed, deletedCount: toDelete.count)
                            }
                        }
                    }
                } message: {
                    Text(AppStrings.confirmPermanentDeleteMessage)
                }
                .confirmationDialog(
                    AppStrings.confirmPermanentDeleteTitle(items.count),
                    isPresented: $showEmptyAllConfirm,
                    titleVisibility: .visible
                ) {
                    Button(AppStrings.emptyTrash, role: .destructive) {
                        let totalCount = items.count
                        let freed = services.trash.totalSize
                        Task {
                            do {
                                try await services.trash.permanentlyDeleteAll(photoLibrary: services.photoLibrary)
                            } catch {
                                handlePermanentDeleteFailure(error)
                                return
                            }
                            await MainActor.run {
                                Haptics.permanentDelete()
                                services.toast.permanentlyDeleted(totalCount, freed: freed)
                                recordCleanupAndCelebrate(freedBytes: freed, deletedCount: totalCount)
                            }
                        }
                    }
                } message: {
                    Text(AppStrings.confirmEmptyTrashMessage)
                }
                .task { services.trash.reconcileWithLibrary() }
        }
    }

    /// 区分用户在系统确认弹窗中点了"不允许"（视为取消，无需提示）与真实删除失败（需要 toast 提示）
    @MainActor
    private func handlePermanentDeleteFailure(_ error: Error) {
        if let phError = error as? PHPhotosError, phError.code == .userCancelled {
            return
        }
        services.toast.failure(String(localized: "删除失败，请重试"))
    }

    @MainActor
    private func recordCleanupAndCelebrate(freedBytes: Int64, deletedCount: Int) {
        let unlocked = services.achievement.recordCleanup(freedSpace: freedBytes, deletedCount: deletedCount)
        for achievement in unlocked {
            services.toast.show(
                icon: achievement.icon,
                text: String(localized: "解锁成就:\(achievement.title)"),
                tint: Theme.warning,
                duration: 2.5
            )
        }
        ReviewPromptManager.requestReviewIfAppropriate()
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            EmptyState("项目", systemImage: AppIcons.trash,
                       description: "垃圾桶里没有内容", tint: Theme.danger)
                .background(Theme.background)
        } else {
            List {
                LibrarySummaryHeader(
                    countText: AppStrings.items(items.count),
                    sizeText: services.trash.totalSizeText,
                    systemImage: AppIcons.trash,
                    tint: Theme.danger
                )
                .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l,
                                          bottom: Spacing.m, trailing: Spacing.l))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    ForEach(items) { item in
                        TrashRow(
                            item: item,
                            isEditing: isEditing,
                            isSelected: selectedIDs.contains(item.id),
                            onToggle: {
                                Haptics.toggleSelect()
                                if selectedIDs.contains(item.id) {
                                    selectedIDs.remove(item.id)
                                } else {
                                    selectedIDs.insert(item.id)
                                }
                            }
                        )
                        .contextMenu {
                            Button(AppStrings.restore, systemImage: AppIcons.restore) {
                                services.trash.restore([item.id])
                                services.toast.restored(1)
                            }
                            Button(AppStrings.permanentlyDelete, systemImage: AppIcons.trashFill, role: .destructive) {
                                let freed = item.fileSize
                                Task {
                                    do {
                                        try await services.trash.permanentlyDelete([item.id], photoLibrary: services.photoLibrary)
                                    } catch {
                                        handlePermanentDeleteFailure(error)
                                        return
                                    }
                                    Haptics.permanentDelete()
                                    services.toast.permanentlyDeleted(1, freed: freed)
                                    recordCleanupAndCelebrate(freedBytes: freed, deletedCount: 1)
                                }
                            }
                        }
                        .padding(Spacing.m)
                        .glassSurface(radius: Radius.row)
                        .cardListRow()
                    }
                }
            }
            .cardListStyle()
        }
    }
}

private struct TrashRow: View {
    let item: TrashedItem
    let isEditing: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            if isEditing {
                Image(systemName: isSelected ? AppIcons.checkmarkCircleFill : AppIcons.circle)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .font(.title3)
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
                    .onTapGesture(perform: onToggle)
            }
            ThumbnailView(localIdentifier: item.id, mediaType: item.mediaType)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: Radius.thumb))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.sourceModule.label)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(item.fileSizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if let date = item.creationDate {
                Text(date, style: .date)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if isEditing { onToggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThumbnailView: View {
    @Environment(AppServiceContainer.self) private var services
    let localIdentifier: String
    let mediaType: TrashedMediaType

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.surfaceSunken
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: mediaType == .video ? AppIcons.video : AppIcons.screenshot)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }
        // 走 PhotoLibraryService 统一的 semaphore 限流入口，
        // 避免垃圾桶列表快速滚动时并发解码不受控触发 jetsam
        image = await services.photoLibrary.thumbnail(
            for: asset, size: CGSize(width: 168, height: 168), contentMode: .aspectFill
        )
    }
}
