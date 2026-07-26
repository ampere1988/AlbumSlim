import SwiftUI

/// 底部 action bar 容器：safeAreaInset 用。
///
/// 从贴边的整条 material 改成浮起的胶囊面板 —— 内容能从下方"穿过去"，
/// 深色下的层次也更清楚。左右留白由容器自己负责，调用方直接塞按钮即可。
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Spacing.m) {
            content()
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Radius.sheet)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sheet)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: Radius.sheet))
        .elevation(.floating)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
    }
}

#Preview {
    Color.clear
        .safeAreaInset(edge: .bottom) {
            ActionBar {
                Button("取消") {}.secondaryActionStyle()
                Button("删除 12 项") {}.primaryActionStyle(destructive: true)
            }
        }
        .background(Theme.background)
}
