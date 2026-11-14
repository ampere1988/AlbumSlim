import SwiftUI

private struct GlassSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let elevation: Elevation

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.hairline.opacity(0.45), lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: radius))
            .elevation(elevation)
    }
}

extension View {
    /// 把任意视图变成一张卡片表面(不加内边距, 需要内边距时用 `GlassCard`)。
    func glassSurface(radius: CGFloat = Radius.card, elevation: Elevation = .flat) -> some View {
        modifier(GlassSurfaceModifier(radius: radius, elevation: elevation))
    }
}
