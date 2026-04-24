import SwiftUI
import UIKit
import Photos
import PhotosUI

// MARK: - 可缩放容器（UIImageView / PHLivePhotoView 共用）

final class ZoomableScrollView: UIScrollView {
    enum InitialMode {
        /// 图片完整显示（可能留黑边）。minimumZoomScale = fitScale
        case fit
        /// 沉浸式铺满屏幕（可能裁剪）。minimumZoomScale = fillScale
        case fill
    }

    var contentView: UIView?
    /// 内容视图的"自然"尺寸（UIImage.size 或 PHLivePhoto.size），用于计算缩放基准。
    var naturalContentSize: CGSize = .zero
    var needsInitialZoom = true
    var fullscreenTriggerScale: CGFloat = 0
    var initialMode: InitialMode = .fit
    /// 当前模式下的"基准"缩放：fit 模式 = fitScale，fill 模式 = fillScale。
    /// 初始态与双击切换都围绕这个值，而非 minimumZoomScale —— 保留 pinch 继续缩小到 fit 看全貌的能力。
    private(set) var baseScale: CGFloat = 0
    private var lastBaseScale: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard
            naturalContentSize.width > 0, naturalContentSize.height > 0,
            bounds.width > 0, bounds.height > 0
        else { return }

        let widthScale = bounds.width / naturalContentSize.width
        let heightScale = bounds.height / naturalContentSize.height
        let fitScale = min(widthScale, heightScale)
        let fillScale = max(widthScale, heightScale)
        let base = initialMode == .fill ? fillScale : fitScale
        let previousBase = lastBaseScale
        lastBaseScale = base
        baseScale = base
        let previousZoom = zoomScale

        // fit 始终是最小值，这样竖屏 fill 模式也能 pinch 缩回"全貌"。
        minimumZoomScale = fitScale
        maximumZoomScale = fitScale * 8
        fullscreenTriggerScale = max(base * 1.15, fillScale)

        if needsInitialZoom {
            zoomScale = base
            needsInitialZoom = false
            centerContent()
        } else if previousBase > 0.0001, abs(base - previousBase) > 0.0001 {
            let wasBase = abs(previousZoom - previousBase) < previousBase * 0.01
            if wasBase {
                zoomScale = base
                centerContent()
            } else {
                let ratio = previousZoom / previousBase
                zoomScale = min(maximumZoomScale, max(minimumZoomScale, base * ratio))
            }
        } else if zoomScale < minimumZoomScale {
            zoomScale = minimumZoomScale
        }

        updateContentInset()
        syncPanState()
    }

    /// 主动重置 zoomScale 后把内容居中。
    /// 正 offset：contentSize > bounds，滚动到中心。
    /// 负 offset：contentSize < bounds，利用 contentInset 的空间让图居中（inset 已在 updateContentInset 设置好）。
    private func centerContent() {
        updateContentInset()
        contentOffset = CGPoint(
            x: (contentSize.width - bounds.width) / 2,
            y: (contentSize.height - bounds.height) / 2
        )
    }

    func updateContentInset() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func syncPanState() {
        // 放大（> base）时才允许内层 pan 平移查看细节；base 及以下由外层 paging 接管。
        let zoomed = zoomScale > baseScale + 0.001
        if panGestureRecognizer.isEnabled != zoomed {
            panGestureRecognizer.isEnabled = zoomed
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // 只在第一次上 window 且 layout 还没算出 baseScale 时 reset，
        // 避免 page view 复用时吞掉用户的缩放态
        guard window != nil,
              contentView != nil,
              naturalContentSize.width > 0,
              baseScale == 0 else { return }
        needsInitialZoom = true
        lastBaseScale = 0
        contentOffset = .zero
        setNeedsLayout()
    }
}

// MARK: - 共享 Coordinator（双击、缩放回调）

class ZoomableCoordinator: NSObject, UIScrollViewDelegate {
    weak var scrollView: ZoomableScrollView?
    var onZoomStateChanged: ((Bool) -> Void)?
    private var lastReportedZoomed = false

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        (scrollView as? ZoomableScrollView)?.contentView
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
        onZoomStateChanged?(zoomed)
    }

    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scroll = scrollView, let target = scroll.contentView else { return }
        let base = scroll.baseScale
        // 非 base 态（放大或缩小）先回 base 并居中；已在 base 则放大到 base*2.5
        if abs(scroll.zoomScale - base) > 0.001 {
            let w = scroll.bounds.width / base
            let h = scroll.bounds.height / base
            let size = target.bounds.size
            let centerRect = CGRect(
                x: (size.width - w) / 2,
                y: (size.height - h) / 2,
                width: w, height: h
            )
            scroll.zoom(to: centerRect, animated: true)
        } else {
            let targetScale = min(scroll.maximumZoomScale, base * 2.5)
            let point = gesture.location(in: target)
            let width = scroll.bounds.width / targetScale
            let height = scroll.bounds.height / targetScale
            let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            scroll.zoom(to: rect, animated: true)
        }
    }
}

// MARK: - 公共 scrollView 构造

@MainActor
private func makeZoomScrollView() -> ZoomableScrollView {
    let scroll = ZoomableScrollView()
    scroll.showsHorizontalScrollIndicator = false
    scroll.showsVerticalScrollIndicator = false
    scroll.backgroundColor = .clear
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.bouncesZoom = true
    scroll.bounces = true
    scroll.decelerationRate = .fast
    scroll.clipsToBounds = true
    scroll.panGestureRecognizer.isEnabled = false
    // 提前设置非零 zoom range，保证 layoutSubviews 执行前捏合手势就能激活
    scroll.minimumZoomScale = 0.01
    scroll.maximumZoomScale = 10.0
    return scroll
}

// MARK: - ZoomableImageView（静态图）

/// 支持双指缩放、双击切换、fit/fill 自适应的图片展示组件。
/// 缩放状态变化时通过 onZoomStateChanged 回调给上层用于禁用外层滚动等。
struct ZoomableImageView: UIViewRepresentable {
    typealias InitialMode = ZoomableScrollView.InitialMode

    let image: UIImage
    var initialMode: InitialMode = .fit
    let onZoomStateChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomableScrollView {
        let scroll = makeZoomScrollView()
        scroll.initialMode = initialMode
        scroll.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scroll.addSubview(imageView)
        scroll.contentView = imageView
        scroll.naturalContentSize = image.size
        scroll.contentSize = image.size

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ZoomableCoordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scroll
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        return scroll
    }

    func updateUIView(_ scroll: ZoomableScrollView, context: Context) {
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        scroll.initialMode = initialMode
        let current = scroll.contentView as? UIImageView
        guard current?.image !== image else { return }
        let isFirstImage = current?.image == nil
        current?.image = image
        current?.frame = CGRect(origin: .zero, size: image.size)
        scroll.naturalContentSize = image.size
        scroll.contentSize = image.size
        if isFirstImage {
            scroll.needsInitialZoom = true
            scroll.panGestureRecognizer.isEnabled = false
        }
        scroll.setNeedsLayout()
    }

    func makeCoordinator() -> ZoomableCoordinator { ZoomableCoordinator() }
}

// MARK: - ZoomableLivePhotoView（Live Photo）

/// 支持双指缩放的 Live Photo 展示组件。
/// - 双击切换缩放；playTrigger 递增触发一次完整播放；长按触发外部自定义（如重播）。
/// - 播放结束回调给上层以记录状态。
struct ZoomableLivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playTrigger: Int
    let onPlaybackEnded: () -> Void
    let onLongPress: () -> Void
    let onZoomStateChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomableScrollView {
        let scroll = makeZoomScrollView()
        scroll.initialMode = .fit
        scroll.delegate = context.coordinator

        let lpView = PHLivePhotoView()
        lpView.contentMode = .scaleToFill
        lpView.livePhoto = livePhoto
        lpView.isMuted = false
        lpView.delegate = context.coordinator
        lpView.isUserInteractionEnabled = true
        lpView.frame = CGRect(origin: .zero, size: livePhoto.size)
        scroll.addSubview(lpView)
        scroll.contentView = lpView
        scroll.naturalContentSize = livePhoto.size
        scroll.contentSize = livePhoto.size

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ZoomableCoordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(LivePhotoCoordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        scroll.addGestureRecognizer(longPress)

        context.coordinator.scrollView = scroll
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.onLongPress = onLongPress
        return scroll
    }

    func updateUIView(_ scroll: ZoomableScrollView, context: Context) {
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.onLongPress = onLongPress

        guard let lpView = scroll.contentView as? PHLivePhotoView else { return }
        if lpView.livePhoto !== livePhoto {
            lpView.livePhoto = livePhoto
            lpView.frame = CGRect(origin: .zero, size: livePhoto.size)
            scroll.naturalContentSize = livePhoto.size
            scroll.contentSize = livePhoto.size
            scroll.needsInitialZoom = true
            scroll.panGestureRecognizer.isEnabled = false
            context.coordinator.lastTrigger = 0
            scroll.setNeedsLayout()
        }

        if playTrigger == 0 {
            lpView.stopPlayback()
            context.coordinator.lastTrigger = 0
        } else if playTrigger != context.coordinator.lastTrigger {
            context.coordinator.lastTrigger = playTrigger
            lpView.stopPlayback()
            lpView.startPlayback(with: .full)
        }
    }

    func makeCoordinator() -> LivePhotoCoordinator { LivePhotoCoordinator() }

    final class LivePhotoCoordinator: ZoomableCoordinator, PHLivePhotoViewDelegate {
        var onPlaybackEnded: (() -> Void)?
        var onLongPress: (() -> Void)?
        var lastTrigger: Int = 0

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onLongPress?()
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView,
                           didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            onPlaybackEnded?()
        }
    }
}
