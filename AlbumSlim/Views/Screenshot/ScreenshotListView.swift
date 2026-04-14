import SwiftUI

struct ScreenshotListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = ScreenshotViewModel()
    @State private var showPaywall = false
    @State private var exportToast: String?
    @State private var navigationPath = NavigationPath()

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
                                }
                            }
                            .padding(.horizontal, 3)
                        }
                    }
                    .navigationDestination(for: String.self) { screenshotID in
                        if let screenshot = viewModel.screenshots.first(where: { $0.id == screenshotID }) {
                            ScreenshotDetailView(
                                item: screenshot,
                                ocrResult: ocrBinding(for: screenshotID),
                                isExported: exportedBinding(for: screenshotID),
                                onDelete: {
                                    let asset = screenshot.asset
                                    viewModel.removeScreenshotFromUI(screenshotID)
                                    navigationPath.removeLast()
                                    Task {
                                        try? await services.photoLibrary.deleteAssets([asset])
                                    }
                                }
                            )
                        } else {
                            Color.clear
                        }
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
                        Menu {
                            ForEach(ScreenshotSortOrder.allCases, id: \.self) { order in
                                Button {
                                    viewModel.sortOrder = order
                                } label: {
                                    if viewModel.sortOrder == order {
                                        Label(order.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(order.rawValue)
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
                            if ProFeatureGate.canOCR(isPro: services.subscription.isPro) {
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

    private func ocrBinding(for id: String) -> Binding<OCRResult?> {
        Binding(
            get: { viewModel.ocrResults[id] },
            set: { viewModel.ocrResults[id] = $0 }
        )
    }

    private func exportedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.exportedIDs.contains(id) },
            set: { if $0 { viewModel.markExported(id) } else { viewModel.unmarkExported(id) } }
        )
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
                            title: "\(category.rawValue) (\(count))",
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
                    if ProFeatureGate.canOCR(isPro: services.subscription.isPro) {
                        Task {
                            let count = await viewModel.analyzeAndExportSelected(services: services)
                            withAnimation { exportToast = "已存储 \(count) 条文字到文件" }
                        }
                    } else {
                        showPaywall = true
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isAnalyzing || viewModel.selectedItems.isEmpty)

                Button("删除", role: .destructive) {
                    viewModel.showDeleteConfirmation = true
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
                        Text(result.category.rawValue)
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
