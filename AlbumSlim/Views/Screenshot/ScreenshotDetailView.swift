import SwiftUI
import UIKit
import Photos

struct ScreenshotDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: ScreenshotViewModel
    let onTrash: (String) -> Void

    @State private var screenshots: [MediaItem]
    @State private var scrolledID: String?
    @State private var isZoomedIn = false
    @State private var showOCRPanel = false
    @State private var isRecognizing = false
    @State private var recognitionFailed = false
    @State private var savedItemIDs: Set<String> = []
    @State private var recognitionTask: Task<Void, Never>?

    init(screenshots: [MediaItem], currentID: String, viewModel: ScreenshotViewModel, onTrash: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.onTrash = onTrash
        self._screenshots = State(initialValue: screenshots)
        self._scrolledID = State(initialValue: currentID)
    }

    private var currentItem: MediaItem? {
        guard let id = scrolledID else { return screenshots.first }
        return screenshots.first { $0.id == id } ?? screenshots.first
    }

    private var currentIndex: Int {
        guard let id = scrolledID else { return 0 }
        return screenshots.firstIndex { $0.id == id } ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let currentIdx = currentIndex
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, item in
                            ScreenshotDetailPage(
                                item: item,
                                isZoomedIn: $isZoomedIn,
                                isActive: item.id == scrolledID,
                                shouldLoad: abs(index - currentIdx) <= 1
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledID, anchor: .leading)
                .scrollDisabled(isZoomedIn)
            }
            .ignoresSafeArea()

            if showOCRPanel, let item = currentItem {
                VStack(spacing: 0) {
                    Spacer()
                    OCROverlayPanel(
                        item: item,
                        ocrResult: Binding(
                            get: { viewModel.ocrResults[item.id] },
                            set: { viewModel.ocrResults[item.id] = $0 }
                        ),
                        isRecognizing: isRecognizing,
                        recognitionFailed: recognitionFailed,
                        isSaved: savedItemIDs.contains(item.id),
                        onSave: {
                            if let result = viewModel.ocrResults[item.id] {
                                services.notesExport.saveNote(
                                    text: result.text,
                                    category: result.category,
                                    screenshotDate: item.creationDate
                                )
                                savedItemIDs.insert(item.id)
                                services.toast.saved()
                            }
                        },
                        onRetry: {
                            startRecognition(for: item)
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showOCRPanel = false
                            }
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(isZoomedIn ? .hidden : .visible, for: .bottomBar)
        .statusBarHidden(isZoomedIn)
        .persistentSystemOverlays(isZoomedIn ? .hidden : .automatic)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if !showOCRPanel {
                    Button {
                        handleOCRButtonTap()
                    } label: {
                        if isRecognizing {
                            Label("识别中...", systemImage: "arrow.triangle.2.circlepath")
                        } else if currentItem.flatMap({ viewModel.ocrResults[$0.id] }) != nil {
                            Label("查看识别", systemImage: "doc.text.magnifyingglass")
                        } else {
                            Label("识别文字", systemImage: "doc.text.viewfinder")
                        }
                    }
                    .disabled(isRecognizing)

                    Spacer()

                    Button(role: .destructive) {
                        handleTrashCurrent()
                    } label: {
                        Label(AppStrings.moveToTrash, systemImage: AppIcons.trash)
                    }
                    .disabled(isRecognizing)
                }
            }
        }
        .onChange(of: scrolledID) { _, _ in
            recognitionTask?.cancel()
            if isZoomedIn { isZoomedIn = false }
            if showOCRPanel {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showOCRPanel = false }
            }
            isRecognizing = false
            recognitionFailed = false
        }
        .onDisappear {
            recognitionTask?.cancel()
        }
        .animation(.easeInOut(duration: 0.25), value: isZoomedIn)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showOCRPanel)
    }

    private func handleOCRButtonTap() {
        guard let item = currentItem else { return }
        if viewModel.ocrResults[item.id] != nil {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showOCRPanel = true }
        } else {
            startRecognition(for: item)
        }
    }

    private func startRecognition(for item: MediaItem) {
        recognitionTask?.cancel()
        isRecognizing = true
        recognitionFailed = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showOCRPanel = true }
        recognitionTask = Task {
            let size = CGSize(width: 1024, height: 1024)
            guard let img = await services.photoLibrary.thumbnail(for: item.asset, size: size),
                  !Task.isCancelled else {
                if !Task.isCancelled {
                    isRecognizing = false
                    recognitionFailed = true
                    services.toast.failure("识别失败，请重试")
                }
                return
            }
            guard let result = await services.ocrService.recognizeText(from: img),
                  !Task.isCancelled else {
                if !Task.isCancelled {
                    isRecognizing = false
                    recognitionFailed = true
                    services.toast.failure("识别失败，请重试")
                }
                return
            }
            viewModel.ocrResults[item.id] = result
            isRecognizing = false
            recognitionFailed = false
        }
    }

    private func handleTrashCurrent() {
        guard let item = currentItem else { return }
        recognitionTask?.cancel()
        let deletedIndex = currentIndex
        if showOCRPanel {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showOCRPanel = false }
        }
        isRecognizing = false
        recognitionFailed = false
        let assets = services.trash.fetchAssets(for: [item.id])
        services.trash.moveToTrash(assets: assets, source: .screenshot, mediaType: .screenshot)
        Haptics.moveToTrash()
        services.toast.movedToTrash(1)
        onTrash(item.id)
        if screenshots.count <= 1 {
            screenshots.removeAll()
            dismiss()
            return
        }
        let nextIndex = deletedIndex == screenshots.count - 1 ? deletedIndex - 1 : deletedIndex + 1
        scrolledID = screenshots[nextIndex].id
        screenshots.remove(at: deletedIndex)
    }

}


private struct ScreenshotDetailPage: View {
    @Environment(AppServiceContainer.self) private var services
    let item: MediaItem
    @Binding var isZoomedIn: Bool
    let isActive: Bool
    let shouldLoad: Bool

    @State private var image: UIImage?
    @State private var loadProgress: Double = 0

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(
                    image: image,
                    onZoomStateChanged: { zoomed in
                        guard isActive else { return }
                        if isZoomedIn != zoomed { isZoomedIn = zoomed }
                    }
                )
            } else {
                loadingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: shouldLoad) {
            guard shouldLoad, image == nil else { return }
            image = await services.photoLibrary.loadFullImage(
                for: item.asset,
                size: CGSize(width: CGFloat(item.pixelWidth), height: CGFloat(item.pixelHeight)),
                onProgress: { loadProgress = $0 }
            )
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        if loadProgress > 0, loadProgress < 1 {
            VStack(spacing: 10) {
                ProgressView(value: loadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
                Text("正在从 iCloud 下载 \(Int(loadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            ProgressView()
        }
    }
}

private struct OCROverlayPanel: View {
    let item: MediaItem
    @Binding var ocrResult: OCRResult?
    let isRecognizing: Bool
    let recognitionFailed: Bool
    let isSaved: Bool
    let onSave: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .padding(.trailing, 14)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 14)

            if isRecognizing && ocrResult == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在识别文字...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
                .padding(.bottom, 16)
            } else if let result = ocrResult {
                resultContent(result: result)
            } else if recognitionFailed {
                VStack(spacing: 12) {
                    Text("识别失败，请重试")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(action: onRetry) {
                        Label("重新识别", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 20)
                .padding(.bottom, 20)
            } else {
                Text("暂无识别结果")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: -4)
    }

    private func resultContent(result: OCRResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.category.localizedName)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(result.category.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(result.category.color)
                Spacer()
                Button {
                    UIPasteboard.general.string = result.text
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)

            ScrollView {
                Text(result.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: 180)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.thumb))
            .padding(.horizontal, 12)

            Button(action: onSave) {
                Label(
                    isSaved ? "已保存到识别记录" : "保存到识别记录",
                    systemImage: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSaved ? .green : .blue)
            .disabled(isSaved)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}
