import SwiftUI

struct SimilarPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()

    var body: some View {
        Group {
            if viewModel.isScanning {
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.scanProgress) {
                        Text("扫描相似照片...")
                    }
                    Text("\(Int(viewModel.scanProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if viewModel.similarGroups.isEmpty {
                ContentUnavailableView {
                    Label("未发现相似照片", systemImage: "photo.on.rectangle")
                } actions: {
                    Button("开始扫描") {
                        Task { await viewModel.scanSimilarPhotos(services: services) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    SpaceSavedBanner(
                        count: viewModel.similarGroups.flatMap(\.items).count,
                        size: viewModel.similarGroups.reduce(0) { $0 + $1.savableSize }
                    )
                    .listRowInsets(EdgeInsets())

                    ForEach(viewModel.similarGroups) { group in
                        Section("相似组 · \(group.items.count) 张 · 可省 \(group.savableSize.formattedFileSize)") {
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
    }
}
