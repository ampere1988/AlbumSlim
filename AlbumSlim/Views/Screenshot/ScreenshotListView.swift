import SwiftUI

struct ScreenshotListView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var viewModel = ScreenshotViewModel()
    @State private var showPaywall = false
    @State private var navigationPath = NavigationPath()
    @State private var showSavedNotes = false
    @State private var showTrash = false
    @AppStorage("lastSeenNoteTimestamp") private var lastSeenNoteTimestamp: Double = 0
    @Namespace private var zoomNamespace

    private var gridColumns: [GridItem] {
        let count: Int
        if hSizeClass == .regular {
            count = vSizeClass == .regular ? 5 : 7
        } else {
            count = vSizeClass == .regular ? 3 : 5
        }
        return Array(repeating: GridItem(.flexible(), spacing: 2), count: count)
    }

    private var unreadNotesCount: Int {
        services.notesExport.notes.filter { $0.savedDate.timeIntervalSince1970 > lastSeenNoteTimestamp }.count
    }

    private func markNotesSeen() {
        lastSeenNoteTimestamp = services.notesExport.notes.first?.savedDate.timeIntervalSince1970
            ?? Date().timeIntervalSince1970
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading {
                    LoadingState(AppStrings.loading)
                } else if viewModel.screenshots.isEmpty {
                    EmptyState("截图", systemImage: AppIcons.screenshot)
                } else {
                    screenshotGrid
                }
            }
            .navigationTitle("截图")
            .selectionToolbar(
                isEditing: $viewModel.isEditing,
                selectedCount: viewModel.selectedItems.count,
                totalCount: viewModel.filteredScreenshots.count,
                onSelectAll: { viewModel.selectAll() },
                onDeselectAll: { viewModel.deselectAll() }
            )
            .toolbar { toolbarContent }
            .navigationDestination(for: String.self) { screenshotID in
                ScreenshotDetailView(
                    screenshots: viewModel.filteredScreenshots,
                    currentID: screenshotID,
                    viewModel: viewModel,
                    onTrash: { trashedID in
                        viewModel.removeScreenshotFromUI(trashedID)
                    }
                )
                .zoomNavigationTransition(id: screenshotID, in: zoomNamespace)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isEditing && !viewModel.selectedItems.isEmpty {
                    ActionBar {
                        Button(role: .destructive) {
                            if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                let count = viewModel.selectedItems.count
                                viewModel.trashSelected(services: services)
                                Haptics.moveToTrash()
                                services.toast.movedToTrash(count)
                                viewModel.isEditing = false
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedItems.count))")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryActionStyle(destructive: true)
                    }
                }
            }
            .task {
                services.trash.reconcileWithLibrary()
                if lastSeenNoteTimestamp == 0, !services.notesExport.notes.isEmpty {
                    markNotesSeen()
                }
                await viewModel.loadScreenshots(services: services)
            }
            .onChange(of: services.trash.trashedItems.count) { _, _ in
                Task {
                    viewModel.invalidateCache()
                    await viewModel.loadScreenshots(services: services)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .screenshotTabLeft)) { _ in
                navigationPath = NavigationPath()
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showSavedNotes, onDismiss: {
                markNotesSeen()
            }) {
                SavedNotesView()
                    .environment(services)
            }
            .sheet(isPresented: $showTrash) { GlobalTrashView() }
        }
    }

    private var screenshotGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isAnalyzing {
                    ProgressLoadingState(phase: AppStrings.recognizing, progress: viewModel.analysisProgress)
                        .padding(.vertical, 8)
                }

                categoryFilterBar
                    .padding(.bottom, 8)

                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(viewModel.filteredScreenshots) { screenshot in
                        ScreenshotThumbnailCell(
                            item: screenshot,
                            ocrResult: viewModel.ocrResults[screenshot.id],
                            isEditing: viewModel.isEditing,
                            isSelected: viewModel.selectedItems.contains(screenshot.id),
                            services: services
                        ) {
                            if viewModel.isEditing {
                                viewModel.toggleSelection(screenshot.id)
                            } else {
                                navigationPath.append(screenshot.id)
                            }
                        }
                        .zoomTransitionSource(id: screenshot.id, in: zoomNamespace)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: viewModel.filterCategory == nil) {
                    viewModel.filterCategory = nil
                }

                ForEach(ScreenshotCategory.allCases, id: \.self) { category in
                    let count = viewModel.screenshots.filter { item in
                        viewModel.ocrResults[item.id]?.category == category
                    }.count
                    if count > 0 {
                        FilterChip(
                            title: "\(category.localizedName) \(count)",
                            isSelected: viewModel.filterCategory == category,
                            color: category.color
                        ) {
                            viewModel.filterCategory = viewModel.filterCategory == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !viewModel.isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                TrashToolbarButton(count: services.trash.trashedItems.count) {
                    showTrash = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSavedNotes = true
                } label: {
                    notesButtonLabel
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("排序方式") {
                        ForEach(ScreenshotSortOrder.allCases, id: \.self) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                if viewModel.sortOrder == order {
                                    Label(order.localizedName, systemImage: "checkmark")
                                } else {
                                    Text(order.localizedName)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var notesButtonLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "doc.text")
                .font(.body)
            if unreadNotesCount > 0 {
                Text("\(min(unreadNotesCount, 99))")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.red, in: Capsule())
                    .offset(x: 10, y: -8)
            }
        }
        .padding(.trailing, unreadNotesCount > 0 ? 6 : 0)
    }


}

// MARK: - iOS 18+ Zoom 过渡

private extension View {
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomNavigationTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - 缩略图单元格

private struct ScreenshotThumbnailCell: View {
    let item: MediaItem
    let ocrResult: OCRResult?
    let isEditing: Bool
    let isSelected: Bool
    let services: AppServiceContainer
    let onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(9.0 / 16.0, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(9.0 / 16.0, contentMode: .fill)
                    .overlay { ProgressView() }
            }

            if isEditing && isSelected {
                Rectangle().fill(.blue.opacity(0.3))
            }

            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(6)
            }

            // 底部：文件大小 + 分类标签
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Text(item.fileSizeText)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)

                    if let result = ocrResult {
                        Text(result.category.localizedName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(result.category.color.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                    }

                    Spacer()
                }
                .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: 200, height: 360)
            )
        }
    }
}

// MARK: - 分类过滤 Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.2) : Color(.systemGray6), in: Capsule())
                .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }
}
