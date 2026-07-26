import SwiftUI
import Photos

struct VideoSuggestionsView: View {
    @Environment(AppServiceContainer.self) private var services
    @Bindable var viewModel: VideoManagerViewModel
    @State private var selectedIDs: Set<String> = []
    @State private var isEditing = false
    @State private var showTrash = false
    @State private var showPaywall = false

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
                EmptyState("清理建议", systemImage: AppIcons.checkmarkCircle,
                           description: "暂无可清理的视频", tint: Theme.success)
            } else {
                List {
                    savingBanner

                    ForEach(groupedSuggestions, id: \.0) { type, items in
                        Section {
                            ForEach(items) { suggestion in
                                suggestionRow(suggestion)
                                    .padding(Spacing.m)
                                    .glassSurface(radius: Radius.row)
                                    .cardListRow()
                            }
                        } header: {
                            SectionHeader(title: LocalizedStringKey(type.localizedName), tint: Theme.video)
                                .cardListRow()
                        }
                    }
                }
                .cardListStyle()
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !selectedIDs.isEmpty {
                        ActionBar {
                            Button {
                                Haptics.tap()
                                Task { await compressSelected() }
                            } label: {
                                Text("压缩 \(AppStrings.items(selectedIDs.count))")
                            }
                            .secondaryActionStyle()

                            Button(role: .destructive) {
                                guard ProFeatureGate.canClean(isPro: services.subscription.isPro) else {
                                    Haptics.proGate()
                                    showPaywall = true
                                    return
                                }
                                let assets = viewModel.suggestions
                                    .filter { selectedIDs.contains($0.id) }
                                    .map(\.item.asset)
                                viewModel.suggestions.removeAll { selectedIDs.contains($0.id) }
                                selectedIDs.removeAll()
                                isEditing = false
                                let batch = services.trash.moveToTrash(assets: assets, source: .video, mediaType: .video)
                                Haptics.moveToTrash()
                                services.toast.movedToTrash(batch.ids.count, freed: batch.totalSize) { [weak services] in
                                    services?.trash.restore(batch.ids)
                                    services?.toast.restored(batch.ids.count)
                                }
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(selectedIDs.count))")
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
            }
        }
        .background(Theme.background)
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var savingBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("可优化空间")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
                Text(viewModel.totalSuggestedSaving.formattedFileSize)
                    .font(AppFont.metric)
                    .foregroundStyle(Theme.accentGradient)
            }
            Spacer(minLength: 0)
            MetaChip(text: String(localized: "\(viewModel.suggestions.count) 条建议"),
                     systemImage: "lightbulb", tint: Theme.warning)
        }
        .padding(Spacing.l)
        .glassSurface()
        .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l,
                                  bottom: Spacing.m, trailing: Spacing.l))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private func suggestionRow(_ suggestion: VideoAnalysisService.VideoSuggestion) -> some View {
        HStack(spacing: 12) {
            if isEditing {
                Image(systemName: selectedIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(suggestion.id) ? Theme.accent : Theme.textTertiary)
                    .frame(width: 28)
                    .onTapGesture { toggleSelection(suggestion.id) }
            }

            AssetThumbnail(asset: suggestion.item.asset, services: services,
                           targetSize: CGSize(width: 200, height: 140))
                .frame(width: 76, height: 52)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(suggestion.item.creationDate?.formatted(date: .abbreviated, time: .shortened)
                     ?? String(localized: "未知日期"))
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                MetaChip(text: suggestion.reason, tint: Theme.warning)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(suggestion.item.fileSizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
                Text("可省 \(suggestion.estimatedSaving.formattedFileSize)")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.success)
            }
        }
        .contentShape(.rect)
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
