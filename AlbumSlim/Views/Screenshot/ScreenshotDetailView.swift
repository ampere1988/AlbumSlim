import SwiftUI
import Photos

struct ScreenshotDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    let screenshots: [MediaItem]
    @Bindable var viewModel: ScreenshotViewModel
    let onDelete: (String) -> Void

    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false

    init(screenshots: [MediaItem], currentID: String, viewModel: ScreenshotViewModel, onDelete: @escaping (String) -> Void) {
        self.screenshots = screenshots
        self.viewModel = viewModel
        self.onDelete = onDelete
        self._currentIndex = State(initialValue: screenshots.firstIndex(where: { $0.id == currentID }) ?? 0)
    }

    private var currentItem: MediaItem? {
        screenshots.indices.contains(currentIndex) ? screenshots[currentIndex] : nil
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, item in
                ScreenshotDetailPage(
                    item: item,
                    ocrResult: Binding(
                        get: { viewModel.ocrResults[item.id] },
                        set: { viewModel.ocrResults[item.id] = $0 }
                    ),
                    isExported: Binding(
                        get: { viewModel.exportedIDs.contains(item.id) },
                        set: { if $0 { viewModel.markExported(item.id) } else { viewModel.unmarkExported(item.id) } }
                    )
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentItem?.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "截图详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if let id = currentItem?.id, let text = viewModel.ocrResults[id]?.text {
                    Button {
                        UIPasteboard.general.string = text
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
                guard let id = currentItem?.id else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    onDelete(id)
                }
            }
        }
    }
}

private struct ScreenshotDetailPage: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let item: MediaItem
    @Binding var ocrResult: OCRResult?
    @Binding var isExported: Bool

    @State private var image: UIImage?
    @State private var saveState: SaveState = .idle

    enum SaveState { case idle, saving, saved, failed }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Group {
                    if let image {
                        let isCompact = horizontalSizeClass == .compact
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                maxWidth: isCompact ? .infinity : 400,
                                maxHeight: UIScreen.main.bounds.height * (isCompact ? 0.55 : 0.5)
                            )
                    } else {
                        ProgressView()
                            .frame(height: 300)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if let result = ocrResult {
                    HStack {
                        Text(result.category.localizedName)
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
                                subject: Text(result.category.localizedName)
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
            .iPadContentMaxWidth()
        }
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: CGFloat(item.pixelWidth), height: CGFloat(item.pixelHeight))
            )
        }
    }
}
