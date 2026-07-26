import SwiftUI

/// 全 App 统一的卡片容器: 表面色 + 发丝描边 + 层级阴影。
///
/// 深色下靠"比背景亮一档的表面 + 亮描边"分层, 浅色下靠阴影分层,
/// 两者的切换由 `elevation(_:)` 内部处理, 调用方无需关心。
struct GlassCard<Content: View>: View {
    var radius: CGFloat = Radius.card
    var elevation: Elevation = .card
    var padding: CGFloat = Spacing.l
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: radius, elevation: elevation)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("已释放空间").font(AppFont.sectionTitle)
                Text("2.4 GB").font(AppFont.display)
            }
        }
        .padding(Spacing.l)
    }
}
