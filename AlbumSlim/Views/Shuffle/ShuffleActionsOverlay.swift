import SwiftUI
import Photos

/// 右下角操作 overlay：收藏 / 删除 / 更多（横向展开 分享/系统相册/详情）
/// 按钮统一使用 iOS 26 Liquid Glass；低版本回退到 ultraThinMaterial + shadow
struct ShuffleActionsOverlay: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem
    let onDelete: () -> Void
    let onShare: () -> Void
    let onOpenInPhotos: () -> Void
    let onShowDetail: () -> Void

    @State private var isFavorite: Bool = false
    @State private var isExpanded: Bool = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .light)
    @Namespace private var glassNs

    private var snappy: Animation { .spring(response: 0.28, dampingFraction: 0.82) }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassStack
            } else {
                fallbackStack
            }
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

    // MARK: - iOS 26 Liquid Glass

    @available(iOS 26.0, *)
    private var liquidGlassStack: some View {
        VStack(spacing: 14) {
            glassButton(system: isFavorite ? "star.fill" : "star",
                        tint: isFavorite ? .yellow : nil,
                        glassID: "fav") {
                Task { await toggleFavorite() }
            }

            glassButton(system: "trash", glassID: "trash") { onDelete() }

            moreButton
        }
    }

    @available(iOS 26.0, *)
    private var moreButton: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if isExpanded {
                    glassButton(system: "square.and.arrow.up", glassID: "share") {
                        close(); onShare()
                    }
                    glassButton(system: "photo.on.rectangle", glassID: "photos") {
                        close(); onOpenInPhotos()
                    }
                    glassButton(system: "info.circle", glassID: "info") {
                        close(); onShowDetail()
                    }
                }
                glassButton(system: isExpanded ? "xmark" : "ellipsis",
                            glassID: "more") {
                    toggleExpand()
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func glassButton(system: String,
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
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(glassID, in: glassNs)
    }

    // MARK: - Fallback

    private var fallbackStack: some View {
        VStack(spacing: 14) {
            fallbackButton(system: isFavorite ? "star.fill" : "star",
                           tint: isFavorite ? .yellow : nil) {
                Task { await toggleFavorite() }
            }
            fallbackButton(system: "trash") { onDelete() }

            HStack(spacing: 10) {
                if isExpanded {
                    fallbackButton(system: "square.and.arrow.up") {
                        close(); onShare()
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    fallbackButton(system: "photo.on.rectangle") {
                        close(); onOpenInPhotos()
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    fallbackButton(system: "info.circle") {
                        close(); onShowDetail()
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                fallbackButton(system: isExpanded ? "xmark" : "ellipsis") {
                    toggleExpand()
                }
            }
        }
    }

    private func fallbackButton(system: String,
                                tint: Color? = nil,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                )
                .contentShape(Circle())
        }
    }

    // MARK: - Actions

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
