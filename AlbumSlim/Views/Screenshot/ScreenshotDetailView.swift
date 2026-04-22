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
                    ),
                    onDelete: { showDeleteConfirmation = true }
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let item: MediaItem
    @Binding var ocrResult: OCRResult?
    @Binding var isExported: Bool
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var isRecognizing = false
    @State private var saveState: SaveState = .idle

    enum SaveState { case idle, saving, saved, failed }

    private enum LayoutMode {
        case iPhonePortrait
        case iPhoneLandscape
        case iPadPortrait
        case iPadLandscape
    }

    private func layoutMode(for size: CGSize) -> LayoutMode {
        let isPad = horizontalSizeClass == .regular && verticalSizeClass == .regular
        let isLandscape = size.width > size.height
        if isPad {
            return isLandscape ? .iPadLandscape : .iPadPortrait
        } else {
            return isLandscape ? .iPhoneLandscape : .iPhonePortrait
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let mode = layoutMode(for: geometry.size)
            switch mode {
            case .iPadLandscape:
                iPadLandscapeLayout(geometry: geometry)
            case .iPadPortrait:
                iPadPortraitLayout(geometry: geometry)
            case .iPhoneLandscape:
                iPhoneLandscapeLayout(geometry: geometry)
            case .iPhonePortrait:
                iPhonePortraitLayout(geometry: geometry)
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: CGFloat(item.pixelWidth), height: CGFloat(item.pixelHeight))
            )
        }
    }

    // MARK: - iPad 横屏：左右分栏

    private func iPadLandscapeLayout(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            imageSection(maxHeight: geometry.size.height * 0.88)
                .frame(width: geometry.size.width * 0.48)
                .padding(.top, 8)

            Divider()

            ScrollView {
                ocrSection(horizontalPadding: 20)
                    .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - iPad 竖屏：纵向大图

    private func iPadPortraitLayout(geometry: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                imageSection(maxHeight: geometry.size.height * 0.6)

                ocrSection(horizontalPadding: 40)
            }
            .padding(.vertical)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - iPhone 横屏：紧凑左右布局

    private func iPhoneLandscapeLayout(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            imageSection(maxHeight: geometry.size.height * 0.92)
                .frame(width: geometry.size.width * 0.42)

            ScrollView {
                ocrSection(horizontalPadding: 12)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - iPhone 竖屏：标准纵向

    private func iPhonePortraitLayout(geometry: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                imageSection(maxHeight: geometry.size.height * 0.55)

                ocrSection(horizontalPadding: 16)
            }
            .padding(.vertical)
        }
    }

    // MARK: - 共享组件

    private func imageSection(maxHeight: CGFloat) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight)
            } else {
                ProgressView()
                    .frame(height: 300)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func ocrSection(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 16) {
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
                .padding(.horizontal, horizontalPadding)
            } else {
                HStack(spacing: 12) {
                    Button {
                        guard !isRecognizing else { return }
                        isRecognizing = true
                        Task {
                            let size = CGSize(width: 1024, height: 1024)
                            if let img = await services.photoLibrary.thumbnail(for: item.asset, size: size),
                               let result = await services.ocrService.recognizeText(from: img) {
                                ocrResult = result
                            }
                            isRecognizing = false
                        }
                    } label: {
                        Label(isRecognizing ? "识别中..." : "开始识别", systemImage: isRecognizing ? "arrow.triangle.2.circlepath" : "doc.text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecognizing)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除截图", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
}
