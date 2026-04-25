import SwiftUI

extension View {
    /// 主要操作按钮：底部 action bar 中的主按钮
    /// - destructive: true 时使用红色
    func primaryActionStyle(destructive: Bool = false) -> some View {
        self
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(destructive ? .red : .blue)
    }

    /// 次要操作按钮：底部 action bar 中的次按钮
    func secondaryActionStyle() -> some View {
        self
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}
