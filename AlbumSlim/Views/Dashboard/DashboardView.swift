import SwiftUI

struct DashboardView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = DashboardViewModel()
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        VStack(spacing: 16) {
                            ProgressView(value: services.storageAnalyzer.progress) {
                                Text("正在分析相册...")
                            }
                            .padding(.horizontal, 40)
                            Text("\(Int(services.storageAnalyzer.progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    } else if let error = viewModel.errorMessage {
                        ContentUnavailableView(
                            "无法访问相册",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text(error)
                        )
                    } else {
                        VStack(spacing: 4) {
                            Text(viewModel.stats.totalSize.formattedFileSize)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            HStack(spacing: 6) {
                                Text("相册总占用")
                                if viewModel.isRefreshing {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)

                        StorageRingChart(stats: viewModel.stats)
                            .frame(height: 240)
                            .padding(.horizontal)

                        LazyVGrid(columns: [.init(), .init()], spacing: 12) {
                            StatCard(title: "视频", count: viewModel.stats.totalVideoCount,
                                     size: viewModel.stats.videoSize, icon: "video.fill", color: .blue)
                                .onTapGesture { postTabSwitch(1) }
                            StatCard(title: "照片", count: viewModel.stats.totalPhotoCount,
                                     size: viewModel.stats.photoSize, icon: "photo.fill", color: .green)
                                .onTapGesture { postTabSwitch(2) }
                            StatCard(title: "截图", count: viewModel.stats.totalScreenshotCount,
                                     size: viewModel.stats.screenshotSize, icon: "scissors", color: .orange)
                                .onTapGesture { postTabSwitch(3) }
                            StatCard(title: "连拍", count: viewModel.stats.totalBurstCount,
                                     size: 0, icon: "square.stack.3d.up.fill", color: .purple)
                                .onTapGesture { postTabSwitch(2) }
                        }
                        .padding(.horizontal)

                        if viewModel.stats.estimatedSavable > 0 {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("预计可释放 \(viewModel.stats.estimatedSavable.formattedFileSize)")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }

                        NavigationLink {
                            QuickCleanView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "wand.and.stars")
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("智能一键清理")
                                        .font(.headline)
                                    Text("自动检测废片、相似照片、连拍和大视频")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(colors: [.orange.opacity(0.15), .red.opacity(0.15)],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)

                        Button {
                            Task { await viewModel.forceRescan(services: services) }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPaywall = true
                    } label: {
                        if services.subscription.isPro {
                            Label("Pro", systemImage: "crown.fill")
                                .foregroundStyle(.yellow)
                        } else {
                            Label("升级 Pro", systemImage: "crown")
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .task { await viewModel.loadStats(services: services) }
        }
    }

    private func postTabSwitch(_ index: Int) {
        NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": index])
    }
}

extension Notification.Name {
    static let switchTab = Notification.Name("switchTab")
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
