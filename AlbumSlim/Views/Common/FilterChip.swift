import SwiftUI

/// 横向过滤条里的分类胶囊。
///
/// 胶囊本身 34pt 高以保持条带紧凑，但外层撑到 44pt 满足触控下限 ——
/// 视觉密度和可点性两头都不让步。
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.label.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? color : Theme.textSecondary)
                .padding(.horizontal, Spacing.m)
                .frame(height: 34)
                .background {
                    Capsule().fill(isSelected ? color.opacity(0.16) : Theme.surfaceSunken)
                }
                .overlay {
                    Capsule().strokeBorder(isSelected ? color.opacity(0.5) : .clear, lineWidth: 1)
                }
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    HStack(spacing: Spacing.s) {
        FilterChip(title: "全部", isSelected: true) {}
        FilterChip(title: "聊天 24", isSelected: false, color: Theme.screenshot) {}
        FilterChip(title: "购物 8", isSelected: false, color: Theme.photo) {}
    }
    .padding()
    .background(Theme.background)
}
