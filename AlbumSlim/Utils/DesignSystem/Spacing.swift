import Foundation

/// 4/8 节奏的间距刻度 —— 所有 padding / spacing 只能取这些值
enum Spacing {
    /// 4 — 图标与文字的贴合
    static let xs: CGFloat = 4
    /// 8 — 同组元素之间
    static let s: CGFloat = 8
    /// 12 — 卡片内部行距
    static let m: CGFloat = 12
    /// 16 — 卡片内边距 / 页面水平边距
    static let l: CGFloat = 16
    /// 24 — 区块之间
    static let xl: CGFloat = 24
    /// 32 — 大区块之间
    static let xxl: CGFloat = 32
    /// 48 — 页面级留白 / 空状态上下
    static let xxxl: CGFloat = 48
}
