import SwiftUI
import Photos

struct WastePhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false

    private var selectedSize: Int64 {
        viewModel.wasteItems
            .filter { viewModel.selectedForDeletion.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.fileSize }
    }

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
                VStack(spacing: 0) {
                    List {
                        SpaceSavedBanner(
                            count: viewModel.wasteItems.count,
                            size: viewModel.wasteItems.reduce(0) { $0 + $1.fileSize }
                        )
                        .listRowInsets(EdgeInsets())

                        HStack {
                            Button("全选") {
                                for item in viewModel.wasteItems {
                                    viewModel.selectedForDeletion.insert(item.id)
                                }
                            }
                            Button("全不选") {
                                viewModel.selectedForDeletion.removeAll()
                            }
                        }
                        .font(.footnote)

                        ForEach(viewModel.wasteItems) { item in
                            HStack(spacing: 12) {
                                // 勾选框
                                Image(systemName: viewModel.selectedForDeletion.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedForDeletion.contains(item.id) ? .blue : .secondary)
                                    .onTapGesture { viewModel.toggleSelection(item.id) }

                                AsyncThumbnail(asset: item.asset, services: services)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))

                                VStack(alignment: .leading, spacing: 4) {
                                    if let reason = viewModel.wasteReasons[item.id] {
                                        reasonTag(reason)
                                    }
                                    Text(item.fileSizeText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("保留") {
                                    viewModel.keepItem(item.id)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if !viewModel.selectedForDeletion.isEmpty {
                        HStack {
                            Text("已选 \(viewModel.selectedForDeletion.count) 张")
                            Spacer()
                            Button("删除选中", role: .destructive) {
                                if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                    showDeleteConfirm = true
                                } else {
                                    showPaywall = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(.bar)
                        .confirmationDialog("确认删除", isPresented: $showDeleteConfirm) {
                            Button("删除 \(viewModel.selectedForDeletion.count) 张废片", role: .destructive) {
                                Task {
                                    await viewModel.deleteSelected(services: services, source: .waste)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task {
            if viewModel.wasteItems.isEmpty && !viewModel.isScanning {
                await viewModel.scanWastePhotos(services: services)
            }
        }
    }

    @ViewBuilder
    private func reasonTag(_ reason: WasteReason) -> some View {
        let (text, color): (String, Color) = switch reason {
        case .pureBlack: ("纯黑", .gray)
        case .pureWhite: ("纯白", .gray)
        case .blurry: ("模糊", .orange)
        case .fingerBlock: ("遮挡", .red)
        case .accidental: ("误拍", .purple)
        }
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct AsyncThumbnail: View {
    let asset: PHAsset
    let services: AppServiceContainer
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { ProgressView() }
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(for: asset, size: CGSize(width: 120, height: 120))
        }
    }
}
