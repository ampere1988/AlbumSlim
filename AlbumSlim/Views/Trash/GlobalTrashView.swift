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
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryActionStyle()

                            Button(role: .destructive) {
                                showPermanentDeleteConfirm = true
                            } label: {
                                Text("\(AppStrings.permanentlyDelete) \(AppStrings.items(selectedIDs.count))")
                                    .frame(maxWidth: .infinity)
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
                            try? await services.trash.permanentlyDelete(toDelete, photoLibrary: services.photoLibrary)
                            await MainActor.run {
                                Haptics.permanentDelete()
                                services.toast.permanentlyDeleted(toDelete.count, freed: freed)
                                selectedIDs.removeAll()
                                if items.isEmpty { isEditing = false }
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
                            try? await services.trash.permanentlyDeleteAll(photoLibrary: services.photoLibrary)
                            await MainActor.run {
                                Haptics.permanentDelete()
                                services.toast.permanentlyDeleted(totalCount, freed: freed)
                            }
                        }
                    }
                } message: {
                    Text(AppStrings.confirmEmptyTrashMessage)
                }
                .task { services.trash.reconcileWithLibrary() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            EmptyState("项目", systemImage: AppIcons.trash, description: "垃圾桶里没有内容")
        } else {
            List {
                Section {
                    Text("\(items.count) 项 · \(services.trash.totalSizeText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                                Task {
                                    try? await services.trash.permanentlyDelete([item.id], photoLibrary: services.photoLibrary)
                                    Haptics.permanentDelete()
                                    services.toast.permanentlyDeleted(1, freed: item.fileSize)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TrashRow: View {
    let item: TrashedItem
    let isEditing: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                Image(systemName: isSelected ? AppIcons.checkmarkCircleFill : AppIcons.circle)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .onTapGesture(perform: onToggle)
            }
            // 缩略图占位（后续可替换为异步加载 PHAsset 缩略图）
            ThumbnailView(localIdentifier: item.id, mediaType: item.mediaType)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceModule.label)
                    .font(.subheadline.weight(.medium))
                Text(item.fileSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = item.creationDate {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing { onToggle() }
        }
    }
}

private struct ThumbnailView: View {
    let localIdentifier: String
    let mediaType: TrashedMediaType

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: mediaType == .video ? AppIcons.video : AppIcons.screenshot)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        let target = CGSize(width: 168, height: 168)
        manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { img, _ in
            Task { @MainActor in self.image = img }
        }
    }
}
