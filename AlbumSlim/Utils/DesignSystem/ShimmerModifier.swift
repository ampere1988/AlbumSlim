import SwiftUI

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    func body(content: Content) -> some View {
        content.overlay {
            if reduceMotion {
                // 关闭动态效果时保留一层静态高光, 骨架屏仍然读得出"正在加载"
                Color.white.opacity(0.06)
            } else {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.18), .clear],
                    startPoint: sweep ? .init(x: 1, y: 0) : .init(x: -0.6, y: 0),
                    endPoint: sweep ? .init(x: 1.6, y: 1) : .init(x: 0, y: 1)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        sweep = true
                    }
                }
            }
        }
    }
}

extension View {
    /// 骨架屏高光扫过效果。
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
