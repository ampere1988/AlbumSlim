import SwiftUI
import Photos

struct LargePhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var allPhotos: [MediaItem] = []
    @State private var isLoading = false
    @State private var selectedIDs: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var thresholdMB: Int = 10

    private static let thresholdOptions = [50, 30, 15, 10, 8, 5, 3]

    private var thresholdBytes: Int64 { Int64(thresholdMB) * 1024 * 1024 }

    private var largePhotos: [MediaItem] {
        allPhotos.filter { $0.fileSize >= thresholdBytes }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("扫描超大照片...")
            } else if allPhotos.isEmpty {
                ContentUnavailableView {
                    Label("未发现超大照片", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("没有超过 \(thresholdMB) MB 的照片")
                } actions: {
                    thresholdPicker
                        .padding(.bottom, 8)
                    Button("开始扫描") {
                        Task { await loadAllPhotos() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if largePhotos.isEmpty {
                ContentUnavailableView {
                    Label("未发现超大照片", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("没有超过 \(thresholdMB) MB 的照片，试试降低阈值")
                } actions: {
                    thresholdPicker
                }
            } else {
                List {
                    Section {
                        HStack {
                            thresholdPicker
                            Spacer()
                            if selectedIDs.isEmpty {
                                Button("全选") { selectedIDs = Set(largePhotos.map(\.id)) }
                                    .font(.footnote)
                            } else {
                                Button("取消全选") { selectedIDs.removeAll() }
                                    .font(.footnote)
                            }
                        }
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
                            services: services
                        ) {
                            toggleSelection(item.id)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("删除 \(selectedIDs.count) 张 · 释放 \(selectedSize.formattedFileSize)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .padding()
                        .background(.bar)
                    }
                }
                .confirmationDialog("确认删除", isPresented: $showDeleteConfirm) {
                    Button("删除 \(selectedIDs.count) 张照片", role: .destructive) {
                        deleteSelected()
                    }
                }
            }
        }
        .onChange(of: thresholdMB) {
            selectedIDs = selectedIDs.filter { id in largePhotos.contains { $0.id == id } }
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

    private var selectedSize: Int64 {
        largePhotos.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.fileSize }
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
                allPhotos = cachedItems.sorted { $0.fileSize > $1.fileSize }
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchAllAssets(mediaType: .image)
        let items = await services.photoLibrary.buildMediaItems(from: fetchResult)

        // 缓存所有 ≥ 最小阈值的照片，切换阈值时本地过滤
        let minThreshold = Int64(Self.thresholdOptions.last ?? 3) * 1024 * 1024
        allPhotos = items
            .filter { $0.fileSize >= minThreshold }
            .sorted { $0.fileSize > $1.fileSize }

        // 先移除旧的 .largePhoto 组，再添加新的，避免重复
        for group in coordinator.groups(ofType: .largePhoto) {
            coordinator.removeGroup(group)
        }
        if !allPhotos.isEmpty {
            let group = CleanupGroup(type: .largePhoto, items: allPhotos, bestItemID: nil)
            coordinator.addGroups([group])
        }
        coordinator.markCategoryScanned(.largePhoto, libraryVersion: version)
    }

    private func deleteSelected() {
        let toDelete = allPhotos.filter { selectedIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        let freedSize = toDelete.reduce(Int64(0)) { $0 + $1.fileSize }
        let assets = toDelete.map(\.asset)

        let _ = services.achievement.recordCleanup(freedSpace: freedSize, deletedCount: toDelete.count)
        allPhotos.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()

        Task {
            try? await services.photoLibrary.deleteAssets(assets)
        }
    }
}

private struct LargePhotoRow: View {
    let item: MediaItem
    let isSelected: Bool
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
            .clipShape(RoundedRectangle(cornerRadius: 8))

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

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .red : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .task {
            image = await services.photoLibrary.thumbnail(for: item.asset, size: CGSize(width: 200, height: 200))
        }
    }
}
