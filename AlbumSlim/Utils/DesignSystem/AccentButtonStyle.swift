import SwiftUI

/// 主操作按钮: 系统强调色实心(或危险操作的系统红)。
///
/// 按压反馈只改缩放和亮度, 不改布局尺寸 —— 避免相邻内容抖动。
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.rowTitle.bold())
            .foregroundStyle(Theme.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: Radius.row)
                    .fill(destructive ? Theme.danger : Theme.accent)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .motion(Motion.instant, value: configuration.isPressed)
    }
}
