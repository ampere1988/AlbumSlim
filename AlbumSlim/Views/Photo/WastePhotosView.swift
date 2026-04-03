import SwiftUI

struct WastePhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if viewModel.isScanning {
                VStack(spacing: 16) {
                    ProgressView(value: viewModel.scanProgress) {
                        Text("扫描废片...")
                    }
                    Text("\(Int(viewModel.scanProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if viewModel.wasteItems.isEmpty {
                ContentUnavailableView {
                    Label("未发现废片", systemImage: "checkmark.circle")
                } actions: {
                    Button("开始扫描") {
                        Task { await viewModel.scanWastePhotos(services: services) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack {
                    SpaceSavedBanner(
                        count: viewModel.wasteItems.count,
                        size: viewModel.wasteItems.reduce(0) { $0 + $1.fileSize }
                    )

                    MediaGridView(
                        items: viewModel.wasteItems,
                        bestItemID: nil,
                        services: services
                    )

                    Button("删除所有废片", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                .confirmationDialog("确认删除", isPresented: $showDeleteConfirm) {
                    Button("删除 \(viewModel.wasteItems.count) 张废片", role: .destructive) {
                        Task {
                            let assets = viewModel.wasteItems.map(\.asset)
                            try? await services.photoLibrary.deleteAssets(assets)
                            viewModel.wasteItems.removeAll()
                        }
                    }
                }
            }
        }
    }
}
