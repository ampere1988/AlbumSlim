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
                HStack(spacing: 8) {
                    Image(systemName: toast.icon)
                        .foregroundStyle(toast.tint)
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let actionLabel = toast.actionLabel, let action = toast.action {
                        Button {
                            action()
                            toastCenter.dismissCurrent()
                        } label: {
                            Text(actionLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
                // 带操作按钮的 toast 需要可点击；纯提示型 toast 保持不拦截触摸
                .allowsHitTesting(toast.action != nil)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastCenter.current)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
