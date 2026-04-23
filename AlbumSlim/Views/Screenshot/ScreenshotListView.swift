import SwiftUI

struct ScreenshotListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = ScreenshotViewModel()
    @State private var showPaywall = false
    @State private var exportToast: String?
    @State private var navigationPath = NavigationPath()
    @State private var showSavedNotes = false
    @Namespace private var zoomNamespace

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载截图...")
                } else if viewModel.screenshots.isEmpty {
                    ContentUnavailableView("没有截图", systemImage: "scissors")
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if viewModel.isAnalyzing {
                                ProgressView(value: viewModel.analysisProgress) {
                                    Text("处理中...")
                                }
                                .padding(.horizontal)
                            }

                            filterPicker

                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(viewModel.filteredScreenshots) { screenshot in
                                    ScreenshotThumbnailCell(
                                        item: screenshot,
                                        ocrResult: viewModel.ocrResults[screenshot.id],
                                        isExported: viewModel.exportedIDs.contains(screenshot.id),
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
                            .padding(.horizontal, 3)
                        }
                    }
                    .navigationDestination(for: String.self) { screenshotID in
                        ScreenshotDetailView(
                            screenshots: viewModel.filteredScreenshots,
                            currentID: screenshotID,
                            viewModel: viewModel,
                            onDelete: { deletedID in
                                guard let asset = viewModel.screenshots.first(where: { $0.id == deletedID })?.asset else { return }
                                viewModel.removeScreenshotFromUI(deletedID)
                                navigationPath.removeLast()
                                Task {
                                    try? await services.photoLibrary.deleteAssets([asset])
                                }
                            }
                        )
                        .zoomNavigationTransition(id: screenshotID, in: zoomNamespace)
                    }
                    .safeAreaInset(edge: .bottom) {
                        if viewModel.isEditing && !viewModel.selectedItems.isEmpty {
                            batchActionBar
                        }
                    }
                }
            }
            .navigationTitle("截图管理")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.isEditing ? "完成" : "选择") {
                        viewModel.isEditing.toggle()
                        if !viewModel.isEditing { viewModel.deselectAll() }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isEditing {
                        Button(viewModel.selectedItems.count == viewModel.filteredScreenshots.count ? "取消全选" : "全选") {
                            if viewModel.selectedItems.count == viewModel.filteredScreenshots.count {
                                viewModel.deselectAll()
                            } else {
                                viewModel.selectAll()
                            }
                        }
                    } else {
                        if !services.notesExport.notes.isEmpty {
                            Button {
                                showSavedNotes = true
                            } label: {
                                Label("识别记录", systemImage: "doc.text")
                            }
                        }

                        Menu {
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
                        } label: {
                            Label("排序", systemImage: "arrow.up.arrow.down")
                        }

                        if viewModel.exportedCount > 0 {
                            Button("删除已存储(\(viewModel.exportedCount))") {
                                viewModel.showDeleteExportedConfirmation = true
                            }
                            .foregroundStyle(.red)
                        }

                        Button("全部识别") {
                            if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                                Task { await viewModel.analyzeAllScreenshots(services: services) }
                            } else {
                                showPaywall = true
                            }
                        }
                        .disabled(viewModel.isAnalyzing)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = exportToast {
                    Text(toast)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation { exportToast = nil }
                            }
                        }
                }
            }
            .animation(.default, value: exportToast)
            .task { await viewModel.loadScreenshots(services: services) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showSavedNotes) {
                SavedNotesView()
                    .environment(services)
            }
            .confirmationDialog(
                "删除 \(viewModel.exportedCount) 张已存储截图？",
                isPresented: $viewModel.showDeleteExportedConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    viewModel.deleteExported(services: services)
                }
            }
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: viewModel.filterCategory == nil && !viewModel.filterExported) {
                    viewModel.filterCategory = nil
                    viewModel.filterExported = false
                }

                let exportedCount = viewModel.exportedCount
                if exportedCount > 0 {
                    FilterChip(
                        title: "已存储 (\(exportedCount))",
                        isSelected: viewModel.filterExported,
                        color: .green
                    ) {
                        viewModel.filterExported.toggle()
                        if viewModel.filterExported { viewModel.filterCategory = nil }
                    }
                }

                ForEach(ScreenshotCategory.allCases, id: \.self) { category in
                    let count = viewModel.screenshots.filter { item in
                        viewModel.ocrResults[item.id]?.category == category
                    }.count
                    if count > 0 {
                        FilterChip(
                            title: "\(category.localizedName) (\(count))",
                            isSelected: viewModel.filterCategory == category && !viewModel.filterExported,
                            color: category.color
                        ) {
                            viewModel.filterExported = false
                            viewModel.filterCategory = viewModel.filterCategory == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var batchActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("已选 \(viewModel.selectedItems.count) 个")
                    .font(.subheadline)
                Spacer()

                Button("识别并存储") {
                    if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                        Task {
                            let count = await viewModel.analyzeAndExportSelected(services: services)
                            withAnimation { exportToast = "已保存 \(count) 条识别记录" }
                        }
                    } else {
                        showPaywall = true
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isAnalyzing || viewModel.selectedItems.isEmpty)

                Button("删除", role: .destructive) {
                    if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                        viewModel.showDeleteConfirmation = true
                    } else {
                        showPaywall = true
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "确定删除 \(viewModel.selectedItems.count) 张截图？",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                viewModel.deleteSelected(services: services)
            }
        }
    }
}

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

// MARK: - iOS 18+ Zoom 过渡(原相册从缩略图展开到全屏)

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

private struct ScreenshotThumbnailCell: View {
    let item: MediaItem
    let ocrResult: OCRResult?
    let isExported: Bool
    let isEditing: Bool
    let isSelected: Bool
    let services: AppServiceContainer
    let onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 缩略图 — 截图用接近手机屏幕的竖向比例
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

            // 选中蒙层
            if isEditing && isSelected {
                Rectangle().fill(.blue.opacity(0.3))
            }

            // 左上：选中勾
            if isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(6)
            }

            // 右上：已导出标记
            if isExported {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
            }

            // 底部：文件大小 + 分类标签
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Text(item.fileSizeText)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())

                    if let result = ocrResult {
                        Text(result.category.localizedName)
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(result.category.color.opacity(0.8), in: Capsule())
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
