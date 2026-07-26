import SwiftUI

extension View {
    /// 主要操作按钮：底部 action bar 中的主按钮
    /// - destructive: true 时使用红色实心，否则用品牌渐变
    func primaryActionStyle(destructive: Bool = false) -> some View {
        buttonStyle(AccentButtonStyle(destructive: destructive))
    }

    /// 次要操作按钮：底部 action bar 中的次按钮
    func secondaryActionStyle() -> some View {
        buttonStyle(GhostButtonStyle())
    }

    /// 整卡可点：只加按压反馈，不改卡片自身视觉
    func pressableCardStyle() -> some View {
        buttonStyle(PressableCardStyle())
    }
}
