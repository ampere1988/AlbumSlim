import SwiftUI

/// 存储概览 Section — 从原 DashboardView 抽出，嵌入到 SettingsView
/// 包含：相册总占用大字 + 环形图 + 4 个分类 StatCard + 智能扫描入口 + 重新扫描按钮
struct OverviewSection: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        Section("存储概览") {
            if viewModel.isLoading {
                loadingRow
                    .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "无法访问相册",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text(error)
                )
                .listRowBackground(Color.clear)
            } else {
                totalSizeRow
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)

                StorageRingChart(stats: viewModel.stats)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)

                statCardsRow
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)

                NavigationLink {
                    QuickCleanView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("智能扫描")
                                .font(.headline)
                            Text("检测废片、相似照片、连拍和大视频")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.orange)
                    }
                }

                Button {
                    Task { await viewModel.forceRescan(services: services) }
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await viewModel.loadStats(services: services) }
    }

    private var loadingRow: some View {
        ProgressLoadingState(phase: AppStrings.analyzing, progress: services.storageAnalyzer.progress)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private var totalSizeRow: some View {
        VStack(spacing: 4) {
            Text(viewModel.stats.totalSize.formattedFileSize)
                .font(.system(size: 40, weight: .bold, design: .rounded))
            HStack(spacing: 6) {
                Text("相册总占用")
                if viewModel.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statCardsRow: some View {
        LazyVGrid(columns: [.init(), .init()], spacing: 12) {
            StorageStatCard(title: "视频", count: viewModel.stats.totalVideoCount,
                            size: viewModel.stats.videoSize, icon: "video.fill", color: .blue)
                .onTapGesture { postTabSwitch(1) }
            StorageStatCard(title: "照片", count: viewModel.stats.totalPhotoCount,
                            size: viewModel.stats.photoSize, icon: "photo.fill", color: .green)
                .onTapGesture { postTabSwitch(2) }
            StorageStatCard(title: "截图", count: viewModel.stats.totalScreenshotCount,
                            size: viewModel.stats.screenshotSize, icon: "scissors", color: .orange)
                .onTapGesture { postTabSwitch(3) }
            StorageStatCard(title: "连拍", count: viewModel.stats.totalBurstCount,
                            size: 0, icon: "square.stack.3d.up.fill", color: .purple)
                .onTapGesture { postTabSwitch(2) }
        }
    }

    private func postTabSwitch(_ index: Int) {
        NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": index])
    }
}

private struct StorageStatCard: View {
    let title: LocalizedStringKey
    let count: Int
    let size: Int64
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
            Text("\(count) 项")
                .font(.title3.bold())
            if size > 0 {
                Text(size.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
    }
}
