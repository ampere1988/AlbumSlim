import SwiftUI
import Photos

struct QuickCleanView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = QuickCleanViewModel()

    var body: some View {
        Group {
            if let result = viewModel.cleanupResult {
                cleanupDoneView(result)
            } else if viewModel.isScanning {
                scanningView
            } else if viewModel.cleanupGroups.isEmpty {
                emptyStateView
            } else {
                cleanupPreview
            }
        }
        .navigationTitle("智能清理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.cleanupGroups.isEmpty && !viewModel.isScanning {
                await viewModel.startScan(services: services)
            }
        }
    }

    // MARK: - 扫描中

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: services.cleanupCoordinator.scanProgress) {
                Text("正在分析您的相册...")
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal, 40)

            Text(services.cleanupCoordinator.scanPhase.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .animation(.default, value: services.cleanupCoordinator.scanPhase)

            Text("\(Int(services.cleanupCoordinator.scanProgress * 100))%")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.blue)

            Spacer()
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("相册很整洁", systemImage: "sparkles")
        } description: {
            Text("未发现需要清理的项目")
        }
    }

    // MARK: - 清理方案预览

    private var cleanupPreview: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("可释放")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalSavableSize.formattedFileSize)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            ForEach(sortedTypes, id: \.0) { type, groups in
                Section {
                    DisclosureGroup {
                        ForEach(groups) { group in
                            GroupRowView(group: group, services: services,
                                         isSelected: !viewModel.deselectedGroupIDs.contains(group.id)) {
                                viewModel.toggleGroup(group)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: iconForType(type))
                                .foregroundStyle(colorForType(type))
                                .frame(width: 28)
                            Text(titleForType(type))
                                .font(.headline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(countText(groups))
                                    .font(.subheadline)
                                Text(sizeText(groups))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(action: {
                    Task { await viewModel.executeCleanup(services: services) }
                }) {
                    HStack {
                        if viewModel.isCleaningUp {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(viewModel.isCleaningUp ? "清理中..." : "一键清理")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                }
                .disabled(viewModel.isCleaningUp || viewModel.totalSavableSize == 0)
                .listRowBackground(
                    LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                        .opacity(viewModel.isCleaningUp ? 0.5 : 1)
                )
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - 清理完成

    private func cleanupDoneView(_ result: QuickCleanViewModel.CleanupResult) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: result.freedSpace)

            VStack(spacing: 8) {
                Text("已释放 \(result.freedSpace.formattedFileSize) 空间")
                    .font(.title2.bold())
                Text("已清理 \(result.deletedCount) 个项目")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var sortedTypes: [(CleanupGroup.GroupType, [CleanupGroup])] {
        let order: [CleanupGroup.GroupType] = [.waste, .similar, .burst, .largeVideo]
        return order.compactMap { type in
            guard let groups = viewModel.groupsByType[type], !groups.isEmpty else { return nil }
            return (type, groups)
        }
    }

    private func iconForType(_ type: CleanupGroup.GroupType) -> String {
        switch type {
        case .waste: "xmark.bin.fill"
        case .similar: "square.on.square"
        case .burst: "square.stack.3d.up.fill"
        case .screenshot: "scissors"
        case .largeVideo: "video.fill"
        }
    }

    private func colorForType(_ type: CleanupGroup.GroupType) -> Color {
        switch type {
        case .waste: .red
        case .similar: .green
        case .burst: .purple
        case .screenshot: .orange
        case .largeVideo: .blue
        }
    }

    private func titleForType(_ type: CleanupGroup.GroupType) -> String {
        switch type {
        case .waste: "废片"
        case .similar: "相似照片"
        case .burst: "连拍多余"
        case .screenshot: "截图"
        case .largeVideo: "大视频"
        }
    }

    private func countText(_ groups: [CleanupGroup]) -> String {
        let type = groups.first?.type
        if type == .similar || type == .burst {
            return "\(groups.count) 组"
        }
        let total = groups.reduce(0) { $0 + $1.items.count }
        return "\(total) 项"
    }

    private func sizeText(_ groups: [CleanupGroup]) -> String {
        let total = groups.reduce(Int64(0)) { $0 + $1.savableSize }
        return total.formattedFileSize
    }
}

// MARK: - 分组行视图

private struct GroupRowView: View {
    let group: CleanupGroup
    let services: AppServiceContainer
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                VStack(alignment: .leading, spacing: 4) {
                    if group.type == .similar || group.type == .burst {
                        Text("\(group.items.count) 张 · 可省 \(group.savableSize.formattedFileSize)")
                            .font(.subheadline)
                    } else {
                        Text(group.items.first?.fileSizeText ?? "")
                            .font(.subheadline)
                    }
                }
            }
            .toggleStyle(.switch)
        }
    }
}
