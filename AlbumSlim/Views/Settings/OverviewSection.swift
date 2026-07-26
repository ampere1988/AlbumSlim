import SwiftUI

/// 存储概览 Section — 从原 DashboardView 抽出，嵌入到 SettingsView
/// 包含：相册总占用大字 + 环形图 + 4 个分类磁贴 + 智能扫描入口 + 重新扫描按钮
struct OverviewSection: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        Section {
            if viewModel.isLoading {
                loadingRow
                    .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView {
                    VStack(spacing: Spacing.m) {
                        GlowIcon(systemImage: "photo.badge.exclamationmark",
                                 tint: Theme.warning, size: 64)
                        Text("无法访问相册").font(AppFont.sectionTitle)
                    }
                } description: {
                    Text(error)
                }
                .listRowBackground(Color.clear)
            } else {
                totalSizeRow
                    .listRowInsets(EdgeInsets(top: Spacing.l, leading: Spacing.l,
                                              bottom: 0, trailing: Spacing.l))
                    .listRowBackground(Color.clear)

                StorageRingChart(stats: viewModel.stats)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.l,
                                              bottom: Spacing.m, trailing: Spacing.l))
                    .listRowBackground(Color.clear)

                statTilesRow
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.l,
                                              bottom: Spacing.l, trailing: Spacing.l))
                    .listRowBackground(Color.clear)

                NavigationLink {
                    QuickCleanView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("智能扫描")
                                .font(AppFont.rowTitle)
                            Text("检测废片、相似照片、连拍和大视频")
                                .font(AppFont.label)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Theme.accentSecondary)
                    }
                }

                Button(action: rescan) {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("存储概览")
        }
        .task { await viewModel.loadStats(services: services) }
    }

    private var loadingRow: some View {
        ProgressLoadingState(phase: AppStrings.analyzing, progress: services.storageAnalyzer.progress)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
    }

    /// 总占用用渐变大字呈现 —— 这是整个概览里唯一需要一眼看到的数字
    private var totalSizeRow: some View {
        VStack(spacing: Spacing.xs) {
            Text(viewModel.stats.totalSize.formattedFileSize)
                .font(AppFont.display)
                .foregroundStyle(Theme.accentGradient)
            HStack(spacing: Spacing.s) {
                Text("相册总占用")
                if viewModel.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(AppFont.meta)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var statTilesRow: some View {
        LazyVGrid(columns: [.init(), .init()], spacing: Spacing.m) {
            StatTile(title: "视频", count: viewModel.stats.totalVideoCount,
                     size: viewModel.stats.videoSize,
                     systemImage: "video.fill", tint: Theme.video) { postTabSwitch(1) }
            StatTile(title: "照片", count: viewModel.stats.totalPhotoCount,
                     size: viewModel.stats.photoSize,
                     systemImage: "photo.fill", tint: Theme.photo) { postTabSwitch(2) }
            StatTile(title: "截图", count: viewModel.stats.totalScreenshotCount,
                     size: viewModel.stats.screenshotSize,
                     systemImage: "scissors", tint: Theme.screenshot) { postTabSwitch(3) }
            StatTile(title: "连拍", count: viewModel.stats.totalBurstCount,
                     size: 0,
                     systemImage: "square.stack.3d.up.fill", tint: Theme.burst) { postTabSwitch(2) }
        }
    }

    private func rescan() {
        Task { await viewModel.forceRescan(services: services) }
    }

    private func postTabSwitch(_ index: Int) {
        NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": index])
    }
}
