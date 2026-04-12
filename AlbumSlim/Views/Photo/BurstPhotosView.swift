import SwiftUI
import Photos

struct BurstPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var burstGroups: [CleanupGroup] = []
    @State private var isLoading = false
    @State private var showDeleteConfirm = false
    @State private var pendingGroupID: UUID?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("扫描连拍照片...")
            } else if burstGroups.isEmpty {
                ContentUnavailableView {
                    Label("未发现连拍照片", systemImage: "square.stack.3d.up")
                } actions: {
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

                            Button("只保留最佳") {
                                pendingGroupID = group.id
                                showDeleteConfirm = true
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
                .confirmationDialog("确认删除", isPresented: $showDeleteConfirm) {
                    if let id = pendingGroupID,
                       let group = burstGroups.first(where: { $0.id == id }) {
                        let count = group.items.count - 1
                        Button("删除 \(count) 张，只保留最佳", role: .destructive) {
                            Task { await keepOnlyBest(id: id) }
                        }
                    }
                }
            }
        }
    }

    private func loadBursts() async {
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
            .filter { $0.count > 1 }
            .map { items in
                let best = items.max(by: { $0.fileSize < $1.fileSize })
                return CleanupGroup(type: .burst, items: items, bestItemID: best?.id)
            }
    }

    private func keepOnlyBest(id: UUID) async {
        guard let group = burstGroups.first(where: { $0.id == id }) else { return }
        let toDelete = group.items.filter { $0.id != group.bestItemID }
        guard !toDelete.isEmpty else { return }
        try? await services.photoLibrary.deleteAssets(toDelete.map(\.asset))
        burstGroups.removeAll { $0.id == id }
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
                    .font(.system(size: 9))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isBest {
                RoundedRectangle(cornerRadius: 6).stroke(.yellow, lineWidth: 2)
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(for: item.asset, size: CGSize(width: 200, height: 200))
        }
    }
}
