import SwiftUI
import UIKit
import Photos

struct ScreenshotDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: ScreenshotViewModel
    let onTrash: (String) -> Void

    @State private var screenshots: [MediaItem]
    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false
    @State private var isZoomedIn = false
    @State private var dragOffset: CGSize = .zero
    @State private var showOCRPanel = false
    @State private var isRecognizing = false
    @State private var recognitionFailed = false
    @State private var savedItemIDs: Set<String> = []
    @State private var showSaveFlyIn = false
    @State private var recognitionTask: Task<Void, Never>?

    init(screenshots: [MediaItem], currentID: String, viewModel: ScreenshotViewModel, onTrash: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.onTrash = onTrash
        self._screenshots = State(initialValue: screenshots)
        self._currentIndex = State(initialValue: screenshots.firstIndex(where: { $0.id == currentID }) ?? 0)
    }

    private var currentItem: MediaItem? {
        screenshots.indices.contains(currentIndex) ? screenshots[currentIndex] : nil
    }

    private var dismissProgress: CGFloat {
        min(max(dragOffset.height, 0) / 500, 1)
    }

    private var dismissScale: CGFloat {
        1 - dismissProgress * 0.5
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isZoomedIn ? 1 : dismissProgress * 0.85)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, item in
                    ScreenshotDetailPage(
                        item: item,
                        isZoomedIn: $isZoomedIn,
                        isActive: index == currentIndex
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: isZoomedIn ? .all : [])
            .clipShape(RoundedRectangle(cornerRadius: dismissProgress * 24, style: .continuous))
            .scaleEffect(dismissScale, anchor: .center)
            .offset(dragOffset)
            .opacity(1 - dismissProgress * 0.15)

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
                                triggerSaveFlyIn()
                            }
                        },
                        onRetry: {
                            startRecognition(for: item)
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showSaveFlyIn {
                VStack {
                    HStack {
                        Spacer()
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.green, in: Capsule())
                            .padding(.top, 60)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .ignoresSafeArea()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(currentItem?.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "截图详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isZoomedIn ? .hidden : .visible, for: .navigationBar)
        .toolbar(isZoomedIn ? .hidden : .visible, for: .bottomBar)
        .statusBarHidden(isZoomedIn)
        .persistentSystemOverlays(isZoomedIn ? .hidden : .automatic)
        .toolbar {
            if showOCRPanel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("返回查看") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showOCRPanel = false
                        }
                    }
                }
            }

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
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(isRecognizing)
                }
            }
        }
        .confirmationDialog("移入垃圾桶？此截图将保留在相册，可从垃圾桶恢复。", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("移入垃圾桶", role: .destructive) {
                handleTrashCurrent()
            }
        }
        .onChange(of: currentIndex) { _, _ in
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
        .simultaneousGesture(dragToDismissGesture)
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
                }
                return
            }
            guard let result = await services.ocrService.recognizeText(from: img),
                  !Task.isCancelled else {
                if !Task.isCancelled {
                    isRecognizing = false
                    recognitionFailed = true
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
        viewModel.trashScreenshot(item, services: services)
        let deletedIndex = currentIndex
        screenshots.remove(at: deletedIndex)
        if showOCRPanel {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showOCRPanel = false }
        }
        isRecognizing = false
        recognitionFailed = false
        if screenshots.isEmpty {
            dismiss()
        } else {
            currentIndex = min(deletedIndex, screenshots.count - 1)
        }
    }

    private func triggerSaveFlyIn() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showSaveFlyIn = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { showSaveFlyIn = false }
        }
    }

    private var dragToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isZoomedIn, !showOCRPanel else {
                    if dragOffset != .zero { dragOffset = .zero }
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                guard dy > 0, abs(dy) > abs(dx) * 1.2 else {
                    if dragOffset != .zero { dragOffset = .zero }
                    return
                }
                dragOffset = CGSize(width: dx * 0.3, height: dy)
            }
            .onEnded { value in
                guard !isZoomedIn, !showOCRPanel else {
                    if dragOffset != .zero {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = .zero }
                    }
                    return
                }
                let triggered = value.translation.height > 120 || value.predictedEndTranslation.height > 260
                if triggered, abs(value.translation.height) > abs(value.translation.width) {
                    dismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.25)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

private struct ScreenshotDetailPage: View {
    @Environment(AppServiceContainer.self) private var services
    let item: MediaItem
    @Binding var isZoomedIn: Bool
    let isActive: Bool

    @State private var image: UIImage?
    @State private var loadProgress: Double = 0

    var body: some View {
        Group {
            if let image {
                if isActive {
                    ZoomableImageView(
                        image: image,
                        onZoomStateChanged: { zoomed in
                            if isZoomedIn != zoomed { isZoomedIn = zoomed }
                        }
                    )
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                loadingPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: isActive) {
            if isActive {
                image = await services.photoLibrary.loadFullImage(
                    for: item.asset,
                    size: CGSize(width: CGFloat(item.pixelWidth), height: CGFloat(item.pixelHeight)),
                    onProgress: { loadProgress = $0 }
                )
            } else {
                image = nil
                loadProgress = 0
            }
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

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onZoomStateChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomableScrollView {
        let scroll = ZoomableScrollView()
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true
        scroll.bounces = true
        scroll.decelerationRate = .fast
        scroll.clipsToBounds = true
        scroll.panGestureRecognizer.isEnabled = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scroll.addSubview(imageView)
        scroll.imageView = imageView
        scroll.contentSize = image.size

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scroll
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        return scroll
    }

    func updateUIView(_ scroll: ZoomableScrollView, context: Context) {
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        guard scroll.imageView?.image !== image else { return }
        scroll.imageView?.image = image
        scroll.imageView?.frame = CGRect(origin: .zero, size: image.size)
        scroll.contentSize = image.size
        scroll.needsInitialZoom = true
        scroll.panGestureRecognizer.isEnabled = false
        scroll.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: ZoomableScrollView?
        var onZoomStateChanged: ((Bool) -> Void)?
        private var lastReportedZoomed = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomableScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let zoom = scrollView as? ZoomableScrollView else { return }
            zoom.updateContentInset()
            zoom.syncPanState()
            reportIfChanged(zoom: zoom)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            guard let zoom = scrollView as? ZoomableScrollView else { return }
            zoom.syncPanState()
            reportIfChanged(zoom: zoom)
        }

        private func reportIfChanged(zoom: ZoomableScrollView) {
            let enter = zoom.fullscreenTriggerScale
            let exit = max(enter * 0.85, zoom.minimumZoomScale * 1.05)
            let zoomed: Bool
            if lastReportedZoomed {
                zoomed = zoom.zoomScale > exit
            } else {
                zoomed = zoom.zoomScale >= enter
            }
            guard zoomed != lastReportedZoomed else { return }
            lastReportedZoomed = zoomed
            DispatchQueue.main.async { [weak self] in
                self?.onZoomStateChanged?(zoomed)
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = scrollView, let imageView = scroll.imageView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale + 0.001 {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let targetScale = min(scroll.maximumZoomScale, scroll.minimumZoomScale * 2.5)
                let point = gesture.location(in: imageView)
                let width = scroll.bounds.width / targetScale
                let height = scroll.bounds.height / targetScale
                let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

private final class ZoomableScrollView: UIScrollView {
    var imageView: UIImageView?
    var needsInitialZoom = true
    var fullscreenTriggerScale: CGFloat = 0
    private var lastFitScale: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard
            let imageSize = imageView?.image?.size,
            imageSize.width > 0, imageSize.height > 0,
            bounds.width > 0, bounds.height > 0
        else { return }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        let fillScale = max(widthScale, heightScale)
        let previousFit = lastFitScale
        lastFitScale = fitScale
        let previousZoom = zoomScale

        minimumZoomScale = fitScale
        maximumZoomScale = fitScale * 16
        fullscreenTriggerScale = max(fitScale * 1.15, fillScale)

        if needsInitialZoom {
            zoomScale = fitScale
            needsInitialZoom = false
        } else if previousFit > 0.0001, abs(fitScale - previousFit) > 0.0001 {
            let wasFit = abs(previousZoom - previousFit) < previousFit * 0.01
            if wasFit {
                zoomScale = fitScale
            } else {
                let ratio = previousZoom / previousFit
                zoomScale = min(maximumZoomScale, max(minimumZoomScale, fitScale * ratio))
            }
        } else if zoomScale < minimumZoomScale {
            zoomScale = minimumZoomScale
        }

        updateContentInset()
        syncPanState()
    }

    func updateContentInset() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func syncPanState() {
        let zoomed = zoomScale > minimumZoomScale + 0.001
        if panGestureRecognizer.isEnabled != zoomed {
            panGestureRecognizer.isEnabled = zoomed
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, imageView?.image != nil else { return }
        needsInitialZoom = true
        lastFitScale = 0
        contentOffset = .zero
        setNeedsLayout()
    }
}
