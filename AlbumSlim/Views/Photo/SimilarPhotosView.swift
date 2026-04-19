import SwiftUI

struct SimilarPhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false

    private var selectedSize: Int64 {
        let allItems = viewModel.similarGroups.flatMap(\.items)
        return allItems.filter { viewModel.selectedForDeletion.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.fileSize }
    }

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
                VStack(spacing: 0) {
                    List {
                        SpaceSavedBanner(
                            count: viewModel.similarGroups.flatMap(\.items).count,
                            size: viewModel.similarGroups.reduce(0) { $0 + $1.savableSize }
                        )
                        .listRowInsets(EdgeInsets())

                        ForEach(Array(viewModel.similarGroups.enumerated()), id: \.element.id) { index, group in
                            let locked = !ProFeatureGate.canClean(isPro: services.subscription.isPro)
                            Section {
                                if locked {
                                    lockedGroupOverlay
                                } else {
                                    MediaGridView(
                                        items: group.items,
                                        bestItemID: group.bestItemID,
                                        services: services,
                                        isSelectable: true,
                                        selection: $viewModel.selectedForDeletion
                                    )

                                    let isFullySelected = viewModel.isGroupFullySelectedExceptBest(group)
                                    Button(isFullySelected ? "取消选中本组" : "选中除最佳外全部") {
                                        if isFullySelected {
                                            viewModel.deselectGroup(group)
                                        } else {
                                            viewModel.selectAllExceptBest(in: group)
                                        }
                                    }
                                    .font(.footnote)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("相似组 · \(group.items.count) 张 · 可省 \(group.savableSize.formattedFileSize)")
                                    if let range = timeRange(for: group) {
                                        Text(range)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // 底部操作栏
                    if !viewModel.selectedForDeletion.isEmpty {
                        bottomBar
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task {
            if viewModel.similarGroups.isEmpty && !viewModel.isScanning {
                await viewModel.scanSimilarPhotos(services: services)
                viewModel.autoSelectAllExceptBest(isPro: services.subscription.isPro)
            }
        }
    }

    private var lockedGroupOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("升级 Pro 查看更多相似组")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("解锁 Pro") { showPaywall = true }
                .font(.footnote)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var bottomBar: some View {
        HStack {
            Text("已选 \(viewModel.selectedForDeletion.count) 张")
            Spacer()
            Text("可释放 \(selectedSize.formattedFileSize)")
                .foregroundStyle(.secondary)
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
            Button("删除 \(viewModel.selectedForDeletion.count) 张照片", role: .destructive) {
                Task {
                    await viewModel.deleteSelected(services: services)
                }
            }
        }
    }

    private func timeRange(for group: CleanupGroup) -> String? {
        let dates = group.items.compactMap(\.creationDate).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm"
        return "\(fmt.string(from: first)) ~ \(fmt.string(from: last))"
    }
}
