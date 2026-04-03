import SwiftUI

struct DashboardView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView("正在分析相册...")
                    } else if let error = viewModel.errorMessage {
                        ContentUnavailableView(
                            "无法访问相册",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text(error)
                        )
                    } else {
                        StorageRingChart(stats: viewModel.stats)
                            .frame(height: 240)
                            .padding(.horizontal)

                        // 分类统计卡片
                        LazyVGrid(columns: [.init(), .init()], spacing: 12) {
                            StatCard(title: "视频", count: viewModel.stats.totalVideoCount,
                                     size: viewModel.stats.videoSize, icon: "video.fill", color: .blue)
                            StatCard(title: "照片", count: viewModel.stats.totalPhotoCount,
                                     size: viewModel.stats.photoSize, icon: "photo.fill", color: .green)
                            StatCard(title: "截图", count: viewModel.stats.totalScreenshotCount,
                                     size: viewModel.stats.screenshotSize, icon: "scissors", color: .orange)
                            StatCard(title: "连拍", count: viewModel.stats.totalBurstCount,
                                     size: 0, icon: "square.stack.3d.up.fill", color: .purple)
                        }
                        .padding(.horizontal)

                        // 一键扫描按钮
                        Button {
                            Task { await viewModel.loadStats(services: services) }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("相册瘦身")
            .task { await viewModel.loadStats(services: services) }
        }
    }
}

private struct StatCard: View {
    let title: String
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
                .font(.title2.bold())
            if size > 0 {
                Text(size.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
