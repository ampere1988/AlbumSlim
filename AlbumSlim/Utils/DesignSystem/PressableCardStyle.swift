import SwiftUI

/// 整卡可点时用的按钮样式: 不画任何背景, 只提供统一的按压反馈,
/// 让卡片自己的视觉保持原样。
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .motion(Motion.instant, value: configuration.isPressed)
    }
}
