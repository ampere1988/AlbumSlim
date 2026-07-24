import SwiftUI

@MainActor
struct ShareCardGenerator {
    static func generateShareImage(freedSpace: Int64, totalFreed: Int64, cleanupCount: Int, isCumulative: Bool = false) -> UIImage? {
        let view = ShareCardContent(
            freedSpace: freedSpace,
            totalFreed: totalFreed,
            cleanupCount: cleanupCount,
            isCumulative: isCumulative
        )
        let renderer = ImageRenderer(content: view.frame(width: 375, height: 500))
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
