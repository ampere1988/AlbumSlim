import SwiftUI

struct SwipeCleanHomeView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = SwipeCleanHomeViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.buckets.isEmpty && viewModel.appBuckets.isEmpty {
                ContentUnavailableView(
                    String(localized: "没有可清理的照片"),
                    systemImage: "rectangle.stack",
                    description: Text(String(localized: "相册为空，或每个月份的照片都少于 5 张"))
                )
            } else {
                List {
                    if !viewModel.appBuckets.isEmpty {
                        Section {
                            ForEach(viewModel.appBuckets) { bucket in
                                bucketRow(bucket)
                            }
                        } header: {
                            Text(String(localized: "聊天与社交 App 相册"))
                        } footer: {
                            Text(String(localized: "这些相册由对应 App 自动保存，通常是占空间最快的一类。"))
                        }
                    }

                    Section {
                        ForEach(viewModel.buckets) { bucket in
                            bucketRow(bucket)
                        }
                    } header: {
                        Text(String(localized: "按月份逐堆清理"))
                    } footer: {
                        Text(String(localized: "左滑删除，右滑保留。删除的照片先进垃圾桶，可随时恢复。"))
                    }
                }
            }
        }
        .task {
            await viewModel.loadBuckets(services: services)
        }
    }

    private func bucketRow(_ bucket: SwipeCleanBucket) -> some View {
        let remaining = viewModel.remainingCount(for: bucket, services: services)
        return NavigationLink {
            SwipeCleanSessionView(bucket: bucket)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.iconName(for: bucket))
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.title)
                        .font(.body.weight(.medium))
                    Text(String(localized: "\(bucket.count) 张 · \(bucket.totalSizeText)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if remaining == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(String(localized: "剩 \(remaining)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(remaining == 0)
    }
}
