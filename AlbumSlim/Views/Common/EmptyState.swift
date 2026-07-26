import SwiftUI

/// 统一空状态：光晕图标 + 标题"没有 X" + 可选 description + 可选 actions
///
/// 外壳仍是 `ContentUnavailableView`，保留系统的无障碍语义与尺寸适配，
/// 只把默认那个灰扑扑的 SF Symbol 换成品牌光晕图标。
struct EmptyState<Actions: View>: View {
    let object: String           // 比如"视频"，会拼成"没有视频"
    let systemImage: String
    let description: String?
    let tint: Color
    let actions: () -> Actions

    init(
        _ object: String,
        systemImage: String,
        description: String? = nil,
        tint: Color = Theme.accent,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.object = object
        self.systemImage = systemImage
        self.description = description
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: Spacing.l) {
                GlowIcon(systemImage: systemImage, tint: tint, size: 76)
                Text(AppStrings.empty(object))
                    .font(AppFont.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
            }
        } description: {
            if let description {
                Text(description)
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
            }
        } actions: {
            actions()
        }
    }
}

#Preview {
    EmptyState("视频", systemImage: "video.fill", description: "相册里还没有视频") {
        Button("重新扫描") {}
            .secondaryActionStyle()
            .frame(maxWidth: 220)
    }
    .background(Theme.background)
}
