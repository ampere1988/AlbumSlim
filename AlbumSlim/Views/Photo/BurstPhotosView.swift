import SwiftUI

struct BurstPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var burstGroups: [CleanupGroup] = []
    @State private var isLoading = false

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
                List(burstGroups) { group in
                    Section("连拍组 · \(group.items.count) 张") {
                        MediaGridView(
                            items: group.items,
                            bestItemID: group.bestItemID,
                            services: services
                        )
                    }
                }
            }
        }
    }

    private func loadBursts() async {
        isLoading = true
        defer { isLoading = false }

        let fetchResult = services.photoLibrary.fetchBurstAssets()
        let items = services.photoLibrary.buildMediaItems(from: fetchResult)

        // 按 burstIdentifier 分组
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
}
