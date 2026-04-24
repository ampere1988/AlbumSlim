import SwiftUI

/// 统一的浮动主导航栏：默认显示当前 Tab 的图标作为主按钮，
/// 点击后向左横向展开其他 Tab 入口。iOS 26+ 使用原生 Liquid Glass morph。
struct ShuffleNavMenu: View {
    @Environment(AppServiceContainer.self) private var services
    @Binding var selectedTab: Int
    @State private var isExpanded = false
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    @Namespace private var glassNamespace

    struct Entry: Identifiable, Equatable {
        let id: Int
        let icon: String
    }

    static let entries: [Entry] = [
        Entry(id: 0, icon: "shuffle"),
        Entry(id: 1, icon: "video.fill"),
        Entry(id: 2, icon: "photo.on.rectangle.angled"),
        Entry(id: 3, icon: "scissors"),
        Entry(id: 4, icon: "gearshape.fill")
    ]

    private var currentEntry: Entry {
        Self.entries.first(where: { $0.id == selectedTab }) ?? Self.entries[0]
    }

    private var otherEntries: [Entry] {
        Self.entries.filter { $0.id != selectedTab }
    }

    // 灵敏的弹簧动画：response 短 + damping 高，快速到位不拖沓
    private var snappy: Animation { .spring(response: 0.28, dampingFraction: 0.82) }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassMenu
            } else {
                fallbackMenu
            }
        }
        .tint(.primary)  // 覆盖项目 AccentColor（绿色）
        .environment(\.colorScheme, services.backdrop.isDark ? .dark : .light)
        .animation(.smooth(duration: 0.25), value: services.backdrop.isDark)
        .onAppear { hapticGenerator.prepare() }
    }

    // MARK: - iOS 26 Liquid Glass

    @available(iOS 26.0, *)
    private var liquidGlassMenu: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if isExpanded {
                    ForEach(otherEntries) { entry in
                        glassEntryButton(entry)
                    }
                }
                glassMainButton
            }
        }
    }

    @available(iOS 26.0, *)
    private func glassEntryButton(_ entry: Entry) -> some View {
        Button { select(entry) } label: {
            Image(systemName: entry.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("entry-\(entry.id)", in: glassNamespace)
    }

    @available(iOS 26.0, *)
    private var glassMainButton: some View {
        Button(action: toggle) {
            Image(systemName: isExpanded ? "xmark" : currentEntry.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("main", in: glassNamespace)
    }

    // MARK: - Fallback (pre-iOS 26)

    private var fallbackMenu: some View {
        HStack(spacing: 6) {
            if isExpanded {
                ForEach(otherEntries) { entry in
                    fallbackEntryButton(entry)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            fallbackMainButton
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        )
    }

    private var fallbackMainButton: some View {
        Button(action: toggle) {
            Image(systemName: isExpanded ? "xmark" : currentEntry.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
    }

    private func fallbackEntryButton(_ entry: Entry) -> some View {
        Button { select(entry) } label: {
            Image(systemName: entry.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
    }

    // MARK: - Actions

    private func toggle() {
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
        withAnimation(snappy) { isExpanded.toggle() }
    }

    private func select(_ entry: Entry) {
        // 立即更新 tab,不等展开动画完成,避免 Tab 切换延迟感
        selectedTab = entry.id
        withAnimation(snappy) { isExpanded = false }
    }
}
