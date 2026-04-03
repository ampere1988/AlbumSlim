import SwiftUI

struct ScreenshotListView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = ScreenshotViewModel()

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

                        ForEach(viewModel.screenshots) { screenshot in
                            ScreenshotRow(
                                item: screenshot,
                                ocrResult: viewModel.ocrResults[screenshot.id]
                            ) {
                                viewModel.exportToNotes(screenshot, services: services)
                            }
                        }
                    }
                }
            }
            .navigationTitle("截图管理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部识别") {
                        Task { await viewModel.analyzeAllScreenshots(services: services) }
                    }
                    .disabled(viewModel.isAnalyzing)
                }
            }
            .onAppear { viewModel.loadScreenshots(services: services) }
        }
    }
}

private struct ScreenshotRow: View {
    let item: MediaItem
    let ocrResult: OCRResult?
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                        .font(.subheadline)
                    Text(item.fileSizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let result = ocrResult {
                    Text(result.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1), in: Capsule())
                }
            }

            if let result = ocrResult {
                Text(result.text.prefix(100) + (result.text.count > 100 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Button("导出到备忘录", action: onExport)
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
    }
}
