import SwiftUI
import UIKit
import Photos

struct ScreenshotDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    let screenshots: [MediaItem]
    @Bindable var viewModel: ScreenshotViewModel
    let onDelete: (String) -> Void

    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false
    @State private var isZoomedIn = false
    @State private var dragOffset: CGSize = .zero

    init(screenshots: [MediaItem], currentID: String, viewModel: ScreenshotViewModel, onDelete: @escaping (String) -> Void) {
        self.screenshots = screenshots
        self.viewModel = viewModel
        self.onDelete = onDelete
        self._currentIndex = State(initialValue: screenshots.firstIndex(where: { $0.id == currentID }) ?? 0)
    }

    private var currentItem: MediaItem? {
        screenshots.indices.contains(currentIndex) ? screenshots[currentIndex] : nil
    }

    /// 下拉进度 0 ~ 1(仅基于向下拖动距离)
    private var dismissProgress: CGFloat {
        min(max(dragOffset.height, 0) / 500, 1)
    }

    /// 随下拉缩小的比例,拖到底最小 0.5(对齐原相册"照片逐渐变小往回缩"的观感)
    private var dismissScale: CGFloat {
        1 - dismissProgress * 0.5
    }

    var body: some View {
        ZStack {
            // 全屏模式下直接黑底,非全屏时随下拉逐渐暗化
            Color.black
                .opacity(isZoomedIn ? 1 : dismissProgress * 0.85)
                .ignoresSafeArea()

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
                        isZoomedIn: $isZoomedIn,
                        isActive: index == currentIndex
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 放大/全屏模式下忽略 safe area,让图片延伸到屏幕边缘(含 Dynamic Island 和 Home indicator 区域)
            .ignoresSafeArea(.container, edges: isZoomedIn ? .all : [])
            // 下拉时给图片加圆角,强化"卡片被抓起来"的手感
            .clipShape(RoundedRectangle(cornerRadius: dismissProgress * 24, style: .continuous))
            .scaleEffect(dismissScale, anchor: .center)
            .offset(dragOffset)
            .opacity(1 - dismissProgress * 0.15)
        }
        .background {
            if isZoomedIn {
                Color.black.ignoresSafeArea()
            }
        }
        .navigationTitle(currentItem?.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "截图详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isZoomedIn ? .hidden : .visible, for: .navigationBar)
        .toolbar(isZoomedIn ? .hidden : .visible, for: .bottomBar)
        .statusBarHidden(isZoomedIn)
        .persistentSystemOverlays(isZoomedIn ? .hidden : .automatic)
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
        .onChange(of: currentIndex) { _, _ in
            if isZoomedIn { isZoomedIn = false }
        }
        .animation(.easeInOut(duration: 0.25), value: isZoomedIn)
        .simultaneousGesture(dragToDismissGesture)
    }

    /// 下拉退出手势:仅在非缩放状态下响应,垂直占主导且向下
    private var dragToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isZoomedIn else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                // 向上拖或横向占优——不处理(横向留给 TabView 翻页)
                guard dy > 0, abs(dy) > abs(dx) * 1.2 else {
                    if dragOffset != .zero {
                        dragOffset = .zero
                    }
                    return
                }
                // 横向 30% 阻尼,垂直全程跟手
                dragOffset = CGSize(width: dx * 0.3, height: dy)
            }
            .onEnded { value in
                guard !isZoomedIn else {
                    if dragOffset != .zero {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = .zero
                        }
                    }
                    return
                }
                let triggered = value.translation.height > 120 ||
                    value.predictedEndTranslation.height > 260
                if triggered, abs(value.translation.height) > abs(value.translation.width) {
                    dismiss()
                } else {
                    // 松手回弹:interactive spring 保持手指抛物线的惯性,观感更自然
                    withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.25)) {
                        dragOffset = .zero
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
    @Binding var isZoomedIn: Bool
    let isActive: Bool

    @State private var image: UIImage?
    @State private var loadProgress: Double = 0
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
                iPadLayout(geometry: geometry, isLandscape: true)
            case .iPadPortrait:
                iPadLayout(geometry: geometry, isLandscape: false)
            case .iPhoneLandscape:
                iPhoneLandscapeLayout(geometry: geometry)
            case .iPhonePortrait:
                iPhonePortraitLayout(geometry: geometry)
            }
        }
        .task {
            image = await services.photoLibrary.loadFullImage(
                for: item.asset,
                size: CGSize(width: CGFloat(item.pixelWidth), height: CGFloat(item.pixelHeight)),
                onProgress: { loadProgress = $0 }
            )
        }
    }

    // MARK: - iPad 统一布局

    private func iPadLayout(geometry: GeometryProxy, isLandscape: Bool) -> some View {
        let contentMaxWidth: CGFloat = isLandscape ? 820 : 900

        return VStack(spacing: 16) {
            imageSection(maxHeight: .infinity)
                .frame(maxHeight: .infinity)

            if !isZoomedIn {
                ocrSection(horizontalPadding: 32, textMaxHeight: 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, isZoomedIn ? 0 : 8)
        .frame(maxWidth: isZoomedIn ? .infinity : contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - iPhone 横屏

    private func iPhoneLandscapeLayout(geometry: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            imageSection(maxHeight: .infinity)
                .frame(width: isZoomedIn ? geometry.size.width : geometry.size.width * 0.42)
                .frame(maxHeight: .infinity)

            if !isZoomedIn {
                ScrollView {
                    ocrSection(horizontalPadding: 12)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: - iPhone 竖屏

    private func iPhonePortraitLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            imageSection(maxHeight: .infinity)
                .frame(maxHeight: .infinity)

            if !isZoomedIn {
                ocrSection(horizontalPadding: 16, textMaxHeight: 140)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, isZoomedIn ? 0 : 8)
    }

    // MARK: - 共享组件

    /// 图片加载占位:iCloud 下载时显示线性进度 + 百分比,本地瞬时加载显示系统转圈
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

    private func imageSection(maxHeight: CGFloat) -> some View {
        // 非激活页面用普通 Image,激活页面才挂载 ZoomableImageView。
        // 切走时 ZoomableImageView 会被销毁,切回时重新创建 —— 彻底避免 UIScrollView 状态在页面间残留
        Group {
            if let image {
                if isActive {
                    ZoomableImageView(
                        image: image,
                        onZoomStateChanged: { zoomed in
                            if isZoomedIn != zoomed {
                                isZoomedIn = zoomed
                            }
                        }
                    )
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxHeight: maxHeight)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: maxHeight)
                }
            } else {
                loadingPlaceholder
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: isZoomedIn ? 0 : 12))
        .padding(.horizontal, isZoomedIn ? 0 : 16)
    }

    private func ocrSection(horizontalPadding: CGFloat, textMaxHeight: CGFloat? = nil) -> some View {
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

                    if let textMaxHeight {
                        ScrollView {
                            Text(result.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: textMaxHeight)
                    } else {
                        Text(result.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

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
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
}

// MARK: - 可缩放图片容器(对齐原相册:双指捏合 + 双击缩放 + 拖动平移 + 让位 TabView 翻页 + 全屏切换回调)

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
        // 初始在 fit 缩放,不应拦截横向 pan,让 TabView 可以翻到上/下一张
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
            // 进入:达到 fullscreenTriggerScale(iPad 需要放大到 fillScale 才真正全屏);
            // 退出:滞回 15%,避免临界抖动
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
                // 原相册双击:放大到 fit * 2.5
                let targetScale = min(scroll.maximumZoomScale, scroll.minimumZoomScale * 2.5)
                let point = gesture.location(in: imageView)
                let width = scroll.bounds.width / targetScale
                let height = scroll.bounds.height / targetScale
                let rect = CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                )
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

private final class ZoomableScrollView: UIScrollView {
    var imageView: UIImageView?
    var needsInitialZoom = true
    /// 进入"全屏模式"需要达到的 zoom 级别。iPhone 基本 = fit*1.15;iPad 竖屏看 iPhone 截图时 = fillScale(约 1.85*fit),保证触发时图片真的铺满屏幕边
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
        // 对齐原相册:允许放大到 fit 的 16 倍(看清像素级细节),minimum 由 bouncesZoom 处理回弹
        maximumZoomScale = fitScale * 16
        // 全屏触发阈值:至少 1.15*fit 避免贴近 fit 抖动;宽高比差异大的场景(iPad)要到 fillScale 才算真正铺满
        fullscreenTriggerScale = max(fitScale * 1.15, fillScale)

        if needsInitialZoom {
            zoomScale = fitScale
            needsInitialZoom = false
        } else if previousFit > 0.0001, abs(fitScale - previousFit) > 0.0001 {
            // bounds 变化(如全屏切换、旋转)时,若切换前处于 fit 则保持 fit,否则按原缩放比例等比缩放
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

    /// fit 缩放时禁用 pan,让父级 TabView 接管横向翻页;放大后恢复内部拖动
    func syncPanState() {
        let zoomed = zoomScale > minimumZoomScale + 0.001
        if panGestureRecognizer.isEnabled != zoomed {
            panGestureRecognizer.isEnabled = zoomed
        }
    }

    /// 切 Tab、NavigationStack pop 等场景下 scrollView 会被从 window 移除再添加回来,
    /// 这些场景的 layoutSubviews 时序不可控 —— 重新加入 window 时主动走 fit 初始化分支,
    /// 保证每次重新显示都从全貌开始
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, imageView?.image != nil else { return }
        needsInitialZoom = true
        lastFitScale = 0
        contentOffset = .zero
        setNeedsLayout()
    }
}
