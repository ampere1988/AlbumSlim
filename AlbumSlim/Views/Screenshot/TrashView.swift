import SwiftUI
import Photos

struct TrashView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var isEditing = false
    @State private var selectedIDs: Set<String> = []
    @State private var showDeleteAllConfirmation = false
    @State private var showPermanentDeleteConfirmation = false

    private var gridColumns: [GridItem] {
        let count: Int
        if hSizeClass == .regular {
            count = vSizeClass == .regular ? 5 : 7
        } else {
            count = vSizeClass == .regular ? 3 : 5
        }
        return Array(repeating: GridItem(.flexible(), spacing: 2), count: count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if services.trash.trashedItems.isEmpty {
                    ContentUnavailableView(
                        "垃圾桶为空",
                        systemImage: "trash",
                        description: Text("移入垃圾桶的截图将显示在这里")
                    )
                } else {
                    trashGrid
                }
            }
            .navigationTitle(isEditing
                ? (selectedIDs.isEmpty ? "批量操作" : "已选 \(selectedIDs.count) 张")
                : "垃圾桶"
            )
            .navigationBarTitleDisplayMode(isEditing ? .inline : .large)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if isEditing && !selectedIDs.isEmpty {
                    batchActionBar
                }
            }
            .onAppear {
                services.trash.reconcileWithLibrary()
            }
            .confirmationDialog(
                "永久删除全部 \(services.trash.trashedItems.count) 张截图？此操作无法撤销，照片将从相册永久移除。",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("永久删除全部", role: .destructive) {
                    Task { await services.trash.permanentlyDeleteAll(photoLibrary: services.photoLibrary) }
                }
            }
            .confirmationDialog(
                "永久删除选中的 \(selectedIDs.count) 张截图？此操作无法撤销。",
                isPresented: $showPermanentDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("永久删除", role: .destructive) {
                    Task {
                        await services.trash.permanentlyDelete(selectedIDs, photoLibrary: services.photoLibrary)
                        selectedIDs.removeAll()
                        isEditing = false
                    }
                }
            }
        }
    }

    private var trashGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(services.trash.trashedItems.count) 张截图 · \(services.trash.totalSizeText) 尚未释放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(services.trash.trashedItems) { item in
                        TrashedItemCell(
                            item: item,
                            isEditing: isEditing,
                            isSelected: selectedIDs.contains(item.id),
                            services: services,
                            onRestore: {
                                services.trash.restore([item.id])
                            },
                            onPermanentDelete: {
                                Task {
                                    await services.trash.permanentlyDelete([item.id], photoLibrary: services.photoLibrary)
                                }
                            },
                            onTap: {
                                if isEditing {
                                    if selectedIDs.contains(item.id) {
                                        selectedIDs.remove(item.id)
                                    } else {
                                        selectedIDs.insert(item.id)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.top, 8)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isEditing {
                Button(selectedIDs.count == services.trash.trashedItems.count ? "取消全选" : "全选") {
                    if selectedIDs.count == services.trash.trashedItems.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(services.trash.trashedItems.map(\.id))
                    }
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if isEditing {
                Button("完成") {
                    isEditing = false
                    selectedIDs.removeAll()
                }
            } else {
                Button("批量选择") {
                    isEditing = true
                }

                if !services.trash.trashedItems.isEmpty {
                    Button("全部删除", role: .destructive) {
                        showDeleteAllConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private var batchActionBar: some View {
        let selectedSize = services.trash.trashedItems
            .filter { selectedIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.fileSize }

        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复") {
                    services.trash.restore(selectedIDs)
                    selectedIDs.removeAll()
                    isEditing = false
                }
                .buttonStyle(.bordered)

                Button("永久删除", role: .destructive) {
                    showPermanentDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - 垃圾桶单元格

private struct TrashedItemCell: View {
    let item: TrashedItem
    let isEditing: Bool
    let isSelected: Bool
    let services: AppServiceContainer
    let onRestore: () -> Void
    let onPermanentDelete: () -> Void
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(9.0 / 16.0, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(9.0 / 16.0, contentMode: .fill)
                    .overlay { ProgressView() }
            }

            if isEditing && isSelected {
                Rectangle().fill(.blue.opacity(0.3))
            }

            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(6)
            }

            VStack {
                Spacer()
                HStack {
                    Text(item.fileSizeText)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            if !isEditing {
                Button {
                    onRestore()
                } label: {
                    Label("恢复截图", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("永久删除", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "永久删除此截图？此操作无法撤销，照片将从相册永久移除。",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) { onPermanentDelete() }
        }
        .task {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
            if let asset = result.firstObject {
                image = await services.photoLibrary.thumbnail(
                    for: asset,
                    size: CGSize(width: 200, height: 360)
                )
            }
        }
    }
}
