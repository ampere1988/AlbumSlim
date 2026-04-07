import SwiftUI

struct ScreenshotListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = ScreenshotViewModel()
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("加载截图...")
                } else if viewModel.screenshots.isEmpty {
                    ContentUnavailableView("没有截图", systemImage: "scissors")
                } else {
                    List {
                        if viewModel.isAnalyzing {
                            ProgressView(value: viewModel.analysisProgress) {
                                Text("OCR 识别中...")
                            }
                        }

                        filterPicker

                        ForEach(viewModel.filteredScreenshots) { screenshot in
                            if viewModel.isEditing {
                                ScreenshotRow(
                                    item: screenshot,
                                    ocrResult: viewModel.ocrResults[screenshot.id],
                                    isSelected: viewModel.selectedItems.contains(screenshot.id)
                                )
                                .onTapGesture { viewModel.toggleSelection(screenshot.id) }
                            } else {
                                NavigationLink(value: screenshot.id) {
                                    ScreenshotRow(
                                        item: screenshot,
                                        ocrResult: viewModel.ocrResults[screenshot.id]
                                    )
                                }
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { screenshotID in
                        if let screenshot = viewModel.screenshots.first(where: { $0.id == screenshotID }) {
                            ScreenshotDetailView(
                                item: screenshot,
                                ocrResult: binding(for: screenshotID),
                                onDelete: {
                                    await viewModel.deleteScreenshot(screenshot, services: services)
                                }
                            )
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
                        if !viewModel.isEditing {
                            viewModel.deselectAll()
                        }
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
            .task { await viewModel.loadScreenshots(services: services) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func binding(for id: String) -> Binding<OCRResult?> {
        Binding(
            get: { viewModel.ocrResults[id] },
            set: { viewModel.ocrResults[id] = $0 }
        )
    }

    private var filterPicker: some View {
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
                            title: "\(category.rawValue) (\(count))",
                            isSelected: viewModel.filterCategory == category,
                            color: category.color
                        ) {
                            viewModel.filterCategory = category
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
                Button("导出") {
                    viewModel.exportSelected(services: services)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedItems.isEmpty)

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
