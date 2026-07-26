import SwiftUI

/// 次操作按钮: 描边 + 半透明填充, 视觉重量明确低于 `AccentButtonStyle`,
/// 但仍保持 50pt 高度以满足触控下限。
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.rowTitle)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: Radius.row)
                    .fill(Theme.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.row)
                            .strokeBorder(configuration.isPressed ? Theme.hairlineStrong : Theme.hairline)
                    }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .motion(Motion.instant, value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                pressed ? .impact(weight: .light) : nil
            }
    }
}
