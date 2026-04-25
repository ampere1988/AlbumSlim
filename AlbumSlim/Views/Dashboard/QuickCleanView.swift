import SwiftUI

struct QuickCleanView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = QuickCleanViewModel()

    var body: some View {
        Group {
            if viewModel.isScanning {
                scanningView
            } else if viewModel.cleanupGroups.isEmpty {
                emptyStateView
            } else {
                resultSummary
            }
        }
        .navigationTitle("智能扫描")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 等待骨架恢复完成，避免重启后 pendingGroups 尚未加载就触发 fullScan
            await services.prepareAsync()
            if viewModel.cleanupGroups.isEmpty && !viewModel.isScanning {
                await viewModel.loadOrScan(services: services)
            }
        }
    }

    // MARK: - 扫描中

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressLoadingState(phase: AppStrings.analyzing, progress: services.cleanupCoordinator.scanProgress)
            Spacer()
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        EmptyState("可清理项", systemImage: "sparkles", description: "相册很整洁")
    }

    // MARK: - 扫描结果总览

    private var resultSummary: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 头部
                VStack(spacing: 8) {
                    Image(systemName: viewModel.hasCompletedScan ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(viewModel.hasCompletedScan ? .green : .secondary)
                    Text(viewModel.hasCompletedScan ? "扫描完成" : "上次扫描结果")
                        .font(.title2.bold())
                    Text("点击分类前往对应页面查看详情")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 8)

                // 分类卡片
                ForEach(sortedTypes, id: \.0) { type, groups in
                    categoryCard(type: type, groups: groups)
                }

                // 重新扫描
                Button {
                    Task { await viewModel.forceRescan(services: services) }
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - 分类卡片

    @ViewBuilder
    private func categoryCard(type: CleanupGroup.GroupType, groups: [CleanupGroup]) -> some View {
        let label = cardLabel(type: type, groups: groups)

        switch type {
        case .waste:
            NavigationLink {
                WastePhotosView()
                    .navigationTitle("废片检测")
            } label: { label }
            .buttonStyle(.plain)
        case .similar:
            NavigationLink {
                SimilarPhotosView()
                    .navigationTitle("相似照片")
            } label: { label }
            .buttonStyle(.plain)
        case .burst:
            NavigationLink {
                BurstPhotosView()
                    .navigationTitle("连拍清理")
            } label: { label }
            .buttonStyle(.plain)
        case .largePhoto:
            NavigationLink {
                LargePhotosView()
                    .navigationTitle("超大照片")
            } label: { label }
            .buttonStyle(.plain)
        case .largeVideo:
            Button { switchToVideoTab() } label: { label }
            .buttonStyle(.plain)
        case .screenshot:
            EmptyView()
        }
    }

    private func cardLabel(type: CleanupGroup.GroupType, groups: [CleanupGroup]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconForType(type))
                .font(.title2)
                .foregroundStyle(colorForType(type))
                .frame(width: 44, height: 44)
                .background(colorForType(type).opacity(0.15), in: RoundedRectangle(cornerRadius: Radius.thumb))

            VStack(alignment: .leading, spacing: 4) {
                Text(titleForType(type))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(countText(type, groups)) · \(sizeText(groups))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: type == .largeVideo ? "arrow.right.square" : "chevron.right")

                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: - Helpers

    private var sortedTypes: [(CleanupGroup.GroupType, [CleanupGroup])] {
        let order: [CleanupGroup.GroupType] = [.waste, .similar, .burst, .largePhoto, .largeVideo]
        return order.compactMap { type in
            guard let groups = viewModel.groupsByType[type], !groups.isEmpty else { return nil }
            return (type, groups)
        }
    }

    private func switchToVideoTab() {
        NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": 1])
    }

    private func iconForType(_ type: CleanupGroup.GroupType) -> String {
        switch type {
        case .waste: AppIcons.waste
        case .similar: AppIcons.similar
        case .burst: AppIcons.burst
        case .screenshot: AppIcons.screenshot
        case .largePhoto: AppIcons.largePhoto
        case .largeVideo: AppIcons.video
        }
    }

    private func colorForType(_ type: CleanupGroup.GroupType) -> Color {
        switch type {
        case .waste: .red
        case .similar: .green
        case .burst: .purple
        case .screenshot: .orange
        case .largePhoto: .indigo
        case .largeVideo: .blue
        }
    }

    private func titleForType(_ type: CleanupGroup.GroupType) -> String {
        switch type {
        case .waste: "废片"
        case .similar: "相似照片"
        case .burst: "连拍多余"
        case .screenshot: "截图"
        case .largePhoto: "超大照片"
        case .largeVideo: "大视频"
        }
    }

    private func countText(_ type: CleanupGroup.GroupType, _ groups: [CleanupGroup]) -> String {
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
