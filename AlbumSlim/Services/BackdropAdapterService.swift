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
    nonisolated static func averageBrightness(of image: UIImage) -> CGFloat {
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        guard let ctx = UIGraphicsGetCurrentContext(),
              let data = ctx.data else { return 0.5 }

        let bytes = data.bindMemory(to: UInt8.self, capacity: 10 * 10 * 4)
        var sum: Double = 0
        let pixelCount = 10 * 10
        for i in 0..<pixelCount {
            let r = Double(bytes[i * 4]) / 255.0
            let g = Double(bytes[i * 4 + 1]) / 255.0
            let b = Double(bytes[i * 4 + 2]) / 255.0
            // Rec. 709 luminance
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return CGFloat(sum / Double(pixelCount))
    }
}
