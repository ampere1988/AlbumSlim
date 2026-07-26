import SwiftUI

/// 骨架屏占位块 —— 加载时先撑出真实内容的尺寸, 避免内容到位时布局跳动。
///
/// 默认占满可用宽度; 需要模拟长短不一的文字行时, 调用方直接给 `.frame(width:)`。
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var radius: CGFloat = Radius.chip

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Theme.surfaceSunken)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(.rect(cornerRadius: radius))
            .shimmer()
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.m) {
        SkeletonBlock(height: 120, radius: Radius.card)
        SkeletonBlock()
        SkeletonBlock(height: 12).frame(width: 140)
    }
    .padding()
    .background(Theme.background)
}
