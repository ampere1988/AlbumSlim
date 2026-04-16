import SwiftUI
import Photos

struct VideoSuggestionsView: View {
    @Environment(AppServiceContainer.self) private var services
    @Bindable var viewModel: VideoManagerViewModel
    @State private var selectedIDs: Set<String> = []
    @State private var isEditing = false
    @State private var showDeleteConfirm = false

    private var groupedSuggestions: [(VideoAnalysisService.VideoSuggestion.SuggestionType, [VideoAnalysisService.VideoSuggestion])] {
        let grouped = Dictionary(grouping: viewModel.suggestions, by: \.type)
        return VideoAnalysisService.VideoSuggestion.SuggestionType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    var body: some View {
        Group {
            if viewModel.isAnalyzingSuggestions {
                ProgressView("正在分析视频...")
            } else if viewModel.suggestions.isEmpty {
                ContentUnavailableView("没有清理建议", systemImage: "checkmark.circle", description: Text("您的视频库状态良好"))
            } else {
                List {
                    savingBanner

                    ForEach(groupedSuggestions, id: \.0) { type, items in
                        Section {
                            ForEach(items) { suggestion in
                                suggestionRow(suggestion)
                            }
                        } header: {
                            Label(type.localizedName, systemImage: type.icon)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !selectedIDs.isEmpty {
                        batchActionBar
                    }
                }
            }
        }
        .navigationTitle("清理建议")
        .toolbar {
            if !viewModel.suggestions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "完成" : "选择") {
                        isEditing.toggle()
                        if !isEditing { selectedIDs.removeAll() }
                    }
                }
            }
        }
        .task {
            if viewModel.suggestions.isEmpty {
                await viewModel.analyzeSuggestions(services: services)
            }
        }
        .confirmationDialog("确认删除", isPresented: $showDeleteConfirm) {
            Button("删除选中视频", role: .destructive) {
                deleteSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(selectedIDs.count) 个视频，此操作可在\"最近删除\"中撤回")
        }
    }

    private var savingBanner: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("可优化空间")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalSuggestedSaving.formattedFileSize)
                        .font(.title2.bold())
                }
                Spacer()
                Text("\(viewModel.suggestions.count) 条建议")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func suggestionRow(_ suggestion: VideoAnalysisService.VideoSuggestion) -> some View {
        HStack(spacing: 12) {
            if isEditing {
                Image(systemName: selectedIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(suggestion.id) ? .blue : .secondary)
                    .frame(width: 24)
                    .onTapGesture { toggleSelection(suggestion.id) }
            }

            VideoThumbnail(asset: suggestion.item.asset, services: services)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "未知日期")
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(suggestion.item.fileSizeText)
                    .font(.subheadline.bold())
                Text("可省 \(suggestion.estimatedSaving.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing { toggleSelection(suggestion.id) }
        }
    }

    private var batchActionBar: some View {
        HStack {
            Text("已选 \(selectedIDs.count) 个")
                .font(.subheadline)
            Spacer()
            Button("批量压缩") {
                Task { await compressSelected() }
            }
            .buttonStyle(.bordered)
            Button("删除", role: .destructive) {
                showDeleteConfirm = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func compressSelected() async {
        let items = viewModel.suggestions.filter { selectedIDs.contains($0.id) }.map(\.item)
        for item in items {
            try? await services.videoCompression.compressVideo(asset: item.asset, quality: .high)
        }
        selectedIDs.removeAll()
        isEditing = false
        await viewModel.loadVideos(services: services)
        await viewModel.analyzeSuggestions(services: services)
    }

    private func deleteSelected() {
        let assets = viewModel.suggestions
            .filter { selectedIDs.contains($0.id) }
            .map(\.item.asset)
        viewModel.suggestions.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()
        isEditing = false

        Task {
            try? await services.photoLibrary.deleteAssets(assets)
            await viewModel.loadVideos(services: services)
            await viewModel.analyzeSuggestions(services: services)
        }
    }
}

private struct VideoThumbnail: View {
    let asset: PHAsset
    let services: AppServiceContainer
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 60, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .task {
            thumbnail = await services.photoLibrary.thumbnail(for: asset, size: CGSize(width: 120, height: 88))
        }
    }
}
