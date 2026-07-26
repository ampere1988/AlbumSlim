import SwiftUI

extension View {
    /// 卡片式列表容器：去掉系统分组底色，交给页面自己的 `Theme.background`。
    func cardListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    /// 卡片式列表行：每行是一张独立卡片，而不是被分隔线切开的条目。
    func cardListRow() -> some View {
        listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.l,
                                 bottom: Spacing.xs, trailing: Spacing.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
