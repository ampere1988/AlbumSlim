import SwiftUI

struct SwipeCleanHomeView: View {
    @Environment(AppServiceContainer.self) private var services

    /// 由 AppServiceContainer 持有，切换 Tab 或分类时不会丢失已加载结果。
    private var viewModel: SwipeCleanHomeViewModel { services.swipeCleanHome }

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingState(AppStrings.loading)
            } else if viewModel.buckets.isEmpty && viewModel.appBuckets.isEmpty {
                EmptyState("可清理的照片", systemImage: "rectangle.stack",
                           description: String(localized: "相册为空，或每个月份的照片都少于 5 张"))
            } else {
                list
            }
        }
        .background(Theme.background)
        .task {
            await viewModel.loadBuckets(services: services)
        }
        .onChange(of: services.photoLibrary.libraryVersion) {
            Task { await viewModel.loadBuckets(services: services) }
        }
    }

    private var list: some View {
        List {
            if !viewModel.appBuckets.isEmpty {
                Section {
                    ForEach(viewModel.appBuckets) { bucket in
                        bucketRow(bucket)
                    }
                } header: {
                    SectionHeader(
                        title: "聊天与社交 App 相册",
                        subtitle: "这些相册由对应 App 自动保存，通常是占空间最快的一类",
                        tint: Theme.screenshot
                    )
                    .cardListRow()
                }
            }

            Section {
                ForEach(viewModel.buckets) { bucket in
                    bucketRow(bucket)
                }
            } header: {
                SectionHeader(
                    title: "按月份逐堆清理",
                    subtitle: "左滑删除，右滑保留；删除的照片先进垃圾桶，可随时恢复",
                    tint: Theme.accent
                )
                .cardListRow()
            }
        }
        .cardListStyle()
    }

    private func bucketRow(_ bucket: SwipeCleanBucket) -> some View {
        NavigationLink {
            SwipeCleanSessionView(bucket: bucket)
        } label: {
            SwipeBucketRow(
                bucket: bucket,
                remaining: viewModel.remainingCount(for: bucket, services: services),
                iconName: viewModel.iconName(for: bucket),
                services: services
            )
            .padding(Spacing.m)
        }
        .glassSurface(radius: Radius.row)
        .cardListRow()
    }
}
