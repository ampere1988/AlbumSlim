import SwiftUI

struct VideoListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = VideoManagerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载视频...")
                } else if viewModel.videos.isEmpty {
                    ContentUnavailableView("没有视频", systemImage: "video.slash")
                } else {
                    List(viewModel.videos) { video in
                        NavigationLink(value: video.id) {
                            VideoRow(item: video)
                        }
                    }
                    .navigationDestination(for: String.self) { videoID in
                        if let video = viewModel.videos.first(where: { $0.id == videoID }) {
                            VideoCompressView(item: video)
                        }
                    }
                }
            }
            .navigationTitle("视频管理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("共 \(viewModel.videos.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { viewModel.loadVideos(services: services) }
        }
    }
}

private struct VideoRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "未知日期")
                    .font(.subheadline)
                Text(item.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.fileSizeText)
                    .font(.subheadline.bold())
                Text(formatDuration(item.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
