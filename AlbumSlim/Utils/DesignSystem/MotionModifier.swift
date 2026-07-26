import SwiftUI

/// 尊重"减弱动态效果"辅助功能开关的动画修饰符。
///
/// 直接用 `.animation(_:value:)` 无法感知 `accessibilityReduceMotion`,
/// 因此全项目的显式动画都走这里。
private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` 的替代品, 开启减弱动态效果时自动降级为无动画。
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}
