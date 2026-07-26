import Foundation

/// 圆角刻度 —— 越大的面积用越大的圆角, 保持视觉张力一致
enum Radius {
    /// 6 — chip / 小徽标
    static let chip: CGFloat = 6
    /// 10 — 网格缩略图
    static let thumb: CGFloat = 10
    /// 14 — 列表行内的小卡
    static let row: CGFloat = 14
    /// 18 — 主卡片
    static let card: CGFloat = 18
    /// 24 — 全宽大卡 / sheet
    static let sheet: CGFloat = 24
    /// 28 — 满屏媒体卡(滑卡)
    static let hero: CGFloat = 28
}
