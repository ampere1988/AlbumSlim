import SwiftUI

private struct ElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let elevation: Elevation

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(colorScheme == .dark ? elevation.darkOpacity : elevation.lightOpacity),
            radius: elevation.shadowRadius,
            y: elevation.shadowY
        )
    }
}

extension View {
    /// 按层级刻度施加阴影, 深浅色各用一套参数。
    func elevation(_ elevation: Elevation) -> some View {
        modifier(ElevationModifier(elevation: elevation))
    }
}
