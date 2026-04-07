import SwiftUI
import Photos

struct ScreenshotDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: MediaItem
    @Binding var ocrResult: OCRResult?
    let onDelete: () async -> Void

    @State private var image: UIImage?
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 大图预览
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView()
                            .frame(height: 300)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // 分类标签
                if let result = ocrResult {
                    Text(result.category.rawValue)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(result.category.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(result.category.color)
                }

                // OCR 文本
                if let result = ocrResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("识别文字")
                            .font(.headline)
                        Text(result.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    Button("开始识别") {
                        Task {
                            let size = CGSize(width: 1024, height: 1024)
                            guard let img = await services.photoLibrary.thumbnail(for: item.asset, size: size),
                                  let result = await services.ocrService.recognizeText(from: img) else { return }
                            ocrResult = result
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "截图详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if ocrResult != nil {
                    Button {
                        if let text = ocrResult?.text {
                            UIPasteboard.general.string = text
                        }
                    } label: {
                        Label("复制文字", systemImage: "doc.on.doc")
                    }

                    Spacer()

                    Button {
                        guard let result = ocrResult else { return }
                        let notesService = NotesExportService()
                        let (title, content) = notesService.formatScreenshotNote(
                            ocrResult: result, date: item.creationDate
                        )
                        notesService.exportToNotes(title: title, content: content)
                    } label: {
                        Label("导出备忘录", systemImage: "square.and.arrow.up")
                    }

                    Spacer()
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("确定删除这张截图？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    dismiss()
                    try? await Task.sleep(for: .milliseconds(300))
                    await onDelete()
                }
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: CGFloat(item.pixelWidth), height: CGFloat(item.pixelHeight))
            )
        }
    }
}
