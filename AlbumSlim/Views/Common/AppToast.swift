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
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastCenter.current)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}
