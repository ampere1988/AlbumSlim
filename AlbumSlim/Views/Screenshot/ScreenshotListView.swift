import SwiftUI

struct ScreenshotListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = ScreenshotViewModel()
    @State private var showPaywall = false
    @State private var exportToast: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载截图...")
                } else if viewModel.screenshots.isEmpty {
                    ContentUnavailableView("没有截图", systemImage: "scissors")
                } else {
                    List {
                        if viewModel.isAnalyzing {
                            ProgressView(value: viewModel.analysisProgress) {
                                Text("处理中...")
                            }
                        }

                        filterPicker

                        ForEach(viewModel.filteredScreenshots) { screenshot in
                            if viewModel.isEditing {
                                ScreenshotRow(
                                    item: screenshot,
                                    ocrResult: viewModel.ocrResults[screenshot.id],
                                    isExported: viewModel.exportedIDs.contains(screenshot.id),
                                    isSelected: viewModel.selectedItems.contains(screenshot.id)
                                )
                                .onTapGesture { viewModel.toggleSelection(screenshot.id) }
                            } else {
                                NavigationLink(value: screenshot.id) {
                                    ScreenshotRow(
                                        item: screenshot,
                                        ocrResult: viewModel.ocrResults[screenshot.id],
                                        isExported: viewModel.exportedIDs.contains(screenshot.id)
                                    )
                                }
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { screenshotID in
                        if let screenshot = viewModel.screenshots.first(where: { $0.id == screenshotID }) {
                            ScreenshotDetailView(
                                item: screenshot,
                                ocrResult: ocrBinding(for: screenshotID),
                                isExported: exportedBinding(for: screenshotID),
                                onDelete: {
                                    // 1. 捕获 asset 引用
                                    let asset = screenshot.asset
                                    // 2. 先从 UI 数据源移除
                                    viewModel.removeScreenshotFromUI(screenshotID)
                                    // 3. pop 导航
                                    navigationPath.removeLast()
                                    // 4. 后台删除 PHAsset
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
                    Task { await viewModel.deleteExported(services: services) }
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
            .padding(.horizontal, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private var batchActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("已选 \(viewModel.selectedItems.count) 个")
                    .font(.subheadline)
                Spacer()

                // 识别并存储：先 OCR 未识别的，再全部存为文件
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
                Task { await viewModel.deleteSelected(services: services) }
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

private struct ScreenshotRow: View {
    let item: MediaItem
    let ocrResult: OCRResult?
    var isExported: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                        .font(.subheadline)
                    Spacer()
                    if isExported {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    if let result = ocrResult {
                        Text(result.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(result.category.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(result.category.color)
                    }
                }

                Text(item.fileSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let result = ocrResult {
                    Text(result.text.prefix(80) + (result.text.count > 80 ? "..." : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
