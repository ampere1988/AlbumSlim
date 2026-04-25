import SwiftUI

/// 统一空状态：标题"没有 X" + 图标 + 可选 description + 可选 actions
struct EmptyState<Actions: View>: View {
    let object: String           // 比如"视频"，会拼成"没有视频"
    let systemImage: String
    let description: String?
    let actions: () -> Actions

    init(
        _ object: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.object = object
        self.systemImage = systemImage
        self.description = description
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label(AppStrings.empty(object), systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            actions()
        }
    }
}
