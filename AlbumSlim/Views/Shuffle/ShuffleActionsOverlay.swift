import SwiftUI
import Photos

/// 右下角操作 overlay：收藏 / 删除 / 更多（竖向展开 info/share）。
/// iOS 26+ 用 Liquid Glass，低版本回退到 ultraThinMaterial，样式由 ShuffleCircleButton 统一。
struct ShuffleActionsOverlay: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let onDelete: () -> Void
    let onShare: () -> Void
    let onShowDetail: () -> Void

    @State private var isFavorite: Bool = false
    @State private var isExpanded: Bool = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)
    @Namespace private var glassNs

    private var snappy: Animation { .spring(response: 0.28, dampingFraction: 0.82) }

    var body: some View {
        VStack(spacing: 14) {
            button(system: isFavorite ? "star.fill" : "star",
                   tint: isFavorite ? .yellow : nil,
                   glassID: "fav") {
                Task { await toggleFavorite() }
            }

            button(system: "trash", glassID: "trash") { onDelete() }

            moreStack
        }
        .tint(.primary)  // 覆盖项目 AccentColor（绿色），保持黑白灰
        .environment(\.colorScheme, services.backdrop.isDark ? .dark : .light)
        .animation(.smooth(duration: 0.25), value: services.backdrop.isDark)
        .onAppear {
            isFavorite = item.asset.isFavorite
            haptic.prepare()
        }
        .onChange(of: item.id) { _, _ in
            isFavorite = item.asset.isFavorite
            isExpanded = false
        }
    }

    @ViewBuilder
    private var moreStack: some View {
        let stack = VStack(spacing: 10) {
            if isExpanded {
                button(system: "info.circle", glassID: "info") {
                    close(); onShowDetail()
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                button(system: "square.and.arrow.up", glassID: "share") {
                    close(); onShare()
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            button(system: isExpanded ? "xmark" : "ellipsis", glassID: "more") {
                toggleExpand()
            }
        }

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { stack }
        } else {
            stack
        }
    }

    private func button(system: String,
                        tint: Color? = nil,
                        glassID: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .modifier(ShuffleCircleButtonStyle(glassID: glassID, glassNs: glassNs))
    }

    private func toggleExpand() {
        haptic.impactOccurred()
        haptic.prepare()
        withAnimation(snappy) { isExpanded.toggle() }
    }

    private func close() {
        withAnimation(snappy) { isExpanded = false }
    }

    private func toggleFavorite() async {
        isFavorite.toggle()
        haptic.impactOccurred()
        haptic.prepare()
        do {
            try await services.photoLibrary.toggleFavorite(item.asset)
        } catch {
            isFavorite.toggle()
        }
    }
}

/// 圆形按钮背景：iOS 26+ 用 Liquid Glass；低版本用 ultraThinMaterial。
private struct ShuffleCircleButtonStyle: ViewModifier {
    let glassID: String
    let glassNs: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID(glassID, in: glassNs)
        } else {
            content.background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            )
        }
    }
}
