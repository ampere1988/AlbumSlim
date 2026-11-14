import SwiftUI

/// 顶层 ZStack 中插入：
/// ```
/// ZStack(alignment: .bottom) {
///     content
///     AppToast(toastCenter: services.toast)
/// }
/// ```
struct AppToast: View {
    let toastCenter: ToastCenter

    var body: some View {
        Group {
            if let toast = toastCenter.current {
                HStack(spacing: Spacing.s) {
                    Image(systemName: toast.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(toast.tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(toast.tint.opacity(0.18)))
                    Text(toast.text)
                        .font(AppFont.meta.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if let actionLabel = toast.actionLabel, let action = toast.action {
                        Button {
                            action()
                            toastCenter.dismissCurrent()
                        } label: {
                            Text(actionLabel)
                                .font(AppFont.meta.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.leading, Spacing.xs)
                    }
                }
                .padding(.leading, Spacing.s)
                .padding(.trailing, Spacing.l)
                .padding(.vertical, Spacing.s)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
                .elevation(.floating)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
                // 带操作按钮的 toast 需要可点击；纯提示型 toast 保持不拦截触摸
                .allowsHitTesting(toast.action != nil)
            }
        }
        .motion(Motion.emphasized, value: toastCenter.current)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
