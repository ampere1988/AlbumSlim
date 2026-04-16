import SwiftUI
import Photos

struct ScreenshotDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: MediaItem
    @Binding var ocrResult: OCRResult?
    @Binding var isExported: Bool
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var showDeleteConfirmation = false
    @State private var saveState: SaveState = .idle

    enum SaveState { case idle, saving, saved, failed }

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
                    HStack {
                        Text(result.category.rawValue)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(result.category.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(result.category.color)

                        if isExported {
                            Label("已存储", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                }

                // OCR 文本
                if let result = ocrResult {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("识别文字")
                            .font(.headline)
                        Text(result.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        HStack(spacing: 12) {
                            Button {
                                guard saveState != .saving else { return }
                                saveState = .saving
                                services.notesExport.saveNote(
                                    text: result.text,
                                    category: result.category,
                                    screenshotDate: item.creationDate
                                )
                                isExported = true
                                saveState = .saved
                            } label: {
                                Group {
                                    switch saveState {
                                    case .idle:
                                        Label(isExported ? "重新保存" : "保存笔记", systemImage: "square.and.arrow.down")
                                    case .saving:
                                        Label("保存中...", systemImage: "arrow.down.circle")
                                    case .saved:
                                        Label("已保存", systemImage: "checkmark.circle.fill")
                                    case .failed:
                                        Label("保存失败", systemImage: "xmark.circle")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(saveState == .saved ? .green : saveState == .failed ? .red : .accentColor)
                            .disabled(saveState == .saving)

                            ShareLink(
                                item: services.notesExport.shareText(
                                    for: SavedNote(
                                        id: UUID(),
                                        text: result.text,
                                        category: result.category.rawValue,
                                        screenshotDate: item.creationDate,
                                        savedDate: Date()
                                    )
                                ),
                                subject: Text(result.category.rawValue)
                            ) {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    HStack(spacing: 12) {
                        Button("开始识别") {
                            Task {
                                let size = CGSize(width: 1024, height: 1024)
                                guard let img = await services.photoLibrary.thumbnail(for: item.asset, size: size),
                                      let result = await services.ocrService.recognizeText(from: img) else { return }
                                ocrResult = result
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("直接删除", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
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
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除截图", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("确定删除这张截图？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    onDelete()
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
