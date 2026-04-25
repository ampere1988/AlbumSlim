import SwiftUI
import Photos

struct VideoSuggestionsView: View {
    @Environment(AppServiceContainer.self) private var services
    @Bindable var viewModel: VideoManagerViewModel
    @State private var selectedIDs: Set<String> = []
    @State private var isEditing = false
    @State private var showTrash = false

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
                ProgressLoadingState(phase: AppStrings.scanning, progress: 0.5)
            } else if viewModel.suggestions.isEmpty {
                EmptyState("清理建议", systemImage: AppIcons.checkmarkCircle, description: "暂无可清理的视频")
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
                        ActionBar {
                            Button {
                                Haptics.tap()
                                Task { await compressSelected() }
                            } label: {
                                Text("压缩 \(AppStrings.items(selectedIDs.count))")
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryActionStyle()

                            Button(role: .destructive) {
                                let assets = viewModel.suggestions
                                    .filter { selectedIDs.contains($0.id) }
                                    .map(\.item.asset)
                                let count = assets.count
                                viewModel.suggestions.removeAll { selectedIDs.contains($0.id) }
                                selectedIDs.removeAll()
                                isEditing = false
                                services.trash.moveToTrash(assets: assets, source: .video, mediaType: .video)
                                Haptics.moveToTrash()
                                services.toast.movedToTrash(count)
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(selectedIDs.count))")
                                    .frame(maxWidth: .infinity)
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
            }
        }
        .navigationTitle("清理建议")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if !viewModel.suggestions.isEmpty {
                        Button(isEditing ? AppStrings.done : AppStrings.select) {
                            isEditing.toggle()
                            if !isEditing { selectedIDs.removeAll() }
                        }
                    }
                    TrashToolbarButton(count: services.trash.trashedItems.count) {
                        showTrash = true
                    }
                }
            }
        }
        .task {
            if viewModel.suggestions.isEmpty {
                await viewModel.analyzeSuggestions(services: services)
            }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            if services.trash.lastChangeKind == .permanentDelete { return }
            Task { await viewModel.analyzeSuggestions(services: services) }
        }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
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
            _ = try? await services.videoCompression.compressVideo(asset: item.asset, quality: .high)
        }
        selectedIDs.removeAll()
        isEditing = false
        await viewModel.loadVideos(services: services)
        await viewModel.analyzeSuggestions(services: services)
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.thumb))
        .task {
            thumbnail = await services.photoLibrary.thumbnail(for: asset, size: CGSize(width: 120, height: 88))
        }
    }
}
