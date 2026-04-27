import Foundation
import UIKit

/// 采样当前浏览媒体的平均亮度，让浮动 Glass 按钮的 colorScheme 自适应。
/// 浅色背景 → light（.primary=黑）；深色背景 → dark（.primary=白）。
@MainActor
@Observable
final class BackdropAdapterService {
    /// true 表示 backdrop 偏暗，图标应使用白色；false 表示偏亮，图标应使用黑色
    private(set) var isDark: Bool = false

    /// 异步采样 UIImage 平均亮度并更新状态
    func sample(image: UIImage?) async {
        guard let image else {
            if isDark { isDark = false }
            return
        }
        let brightness = await Task.detached(priority: .utility) {
            Self.averageBrightness(of: image)
        }.value
        let dark = brightness < 0.5
        if dark != isDark { isDark = dark }
    }

    /// 切到非浏览 Tab 时重置（其他 Tab 都是系统 Form 背景）
    func reset() {
        if isDark { isDark = false }
    }

    /// 缩放到 10x10 采样 grid 计算平均灰度亮度
    /// 使用 UIGraphicsImageRenderer（iOS 10+，线程安全）替代旧的
    /// UIGraphicsBeginImageContextWithOptions（在后台线程使用会偶发崩溃）
    nonisolated static func averageBrightness(of image: UIImage) -> CGFloat {
        let size = CGSize(width: 10, height: 10)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let cgImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage

        guard let cg = cgImage,
              let provider = cg.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.5
        }

        let bytesPerPixel = cg.bitsPerPixel / 8
        let bytesPerRow = cg.bytesPerRow
        let alphaInfo = cg.alphaInfo

        var sum: Double = 0
        let pixelCount = 10 * 10

        for y in 0..<10 {
            for x in 0..<10 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let c0 = Double(bytes[offset]) / 255.0
                let c1 = Double(bytes[offset + 1]) / 255.0
                let c2 = Double(bytes[offset + 2]) / 255.0
                // CGImage 通道顺序由 alphaInfo 决定：BGRA premultipliedFirst (常见于 iOS) 时
                // bytes[0]=B, [1]=G, [2]=R；RGBA 类则是 R/G/B。
                // 对 0.5 二值化阈值精度影响极小，但仍按通道顺序使用 Rec.709 系数
                if alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst {
                    // BGRA: c0=B, c1=G, c2=R
                    sum += 0.0722 * c0 + 0.7152 * c1 + 0.2126 * c2
                } else {
                    // RGBA: c0=R, c1=G, c2=B
                    sum += 0.2126 * c0 + 0.7152 * c1 + 0.0722 * c2
                }
            }
        }
        return CGFloat(sum / Double(pixelCount))
    }
}
