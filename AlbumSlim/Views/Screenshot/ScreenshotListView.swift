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
                    ProgressView("加载截图...")
                } else if viewModel.screenshots.isEmpty {
                    ContentUnavailableView("没有截图", systemImage: "scissors")
                } else {
                    screenshotGrid
                }
            }
            .navigationTitle(viewModel.isEditing
                ? (viewModel.selectedItems.isEmpty ? "批量删除" : "已选 \(viewModel.selectedItems.count) 项")
                : "截图"
            )
            .navigationBarTitleDisplayMode(viewModel.isEditing ? .inline : .large)
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
                    batchActionBar
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
            .sheet(isPresented: $showTrash) {
                TrashView()
                    .environment(services)
            }
        }
    }

    private var screenshotGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isAnalyzing {
                    ProgressView(value: viewModel.analysisProgress) {
                        Text("识别中 \(Int(viewModel.analysisProgress * 100))%")
                            .font(.caption)
                    }
                    .padding(.horizontal)
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
        ToolbarItem(placement: .topBarLeading) {
            if viewModel.isEditing {
                Button(viewModel.selectedItems.count == viewModel.filteredScreenshots.count ? "取消全选" : "全选") {
                    if viewModel.selectedItems.count == viewModel.filteredScreenshots.count {
                        viewModel.deselectAll()
                    } else {
                        viewModel.selectAll()
                    }
                }
            } else {
                Button("批量删除") {
                    viewModel.isEditing = true
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.isEditing {
                Button("完成") {
                    viewModel.isEditing = false
                    viewModel.deselectAll()
                }
            } else {
                // 识别记录（带 badge）
                Button {
                    showSavedNotes = true
                } label: {
                    notesButtonLabel
                }

                // ··· 菜单
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
                    Button {
                        showTrash = true
                    } label: {
                        Label("垃圾桶\(services.trash.trashedItems.isEmpty ? "" : " (\(services.trash.trashedItems.count))")", systemImage: "trash")
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.red, in: Capsule())
                    .offset(x: 10, y: -8)
            }
        }
        .padding(.trailing, unreadNotesCount > 0 ? 6 : 0)
    }

    private var batchActionBar: some View {
        let selectedSize = viewModel.screenshots
            .filter { viewModel.selectedItems.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.fileSize }

        return VStack(spacing: 0) {
            Divider()
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("移入垃圾桶", role: .destructive) {
                    if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                        viewModel.trashSelected(services: services)
                        viewModel.isEditing = false
                    } else {
                        showPaywall = true
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
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
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)

                    if let result = ocrResult {
                        Text(result.category.localizedName)
                            .font(.system(size: 9))
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
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
