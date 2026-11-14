import SwiftUI

/// 字体层级 —— 全部基于系统 text style, 因此天然跟随 Dynamic Type 缩放
///
/// 数字类一律 `.rounded` + `monospacedDigit`: 存储容量、剩余张数在刷新时不会左右跳动。
enum AppFont {
    /// 首屏英雄数字, 例如"12.4 GB"
    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// 卡片里的指标数字
    static let metric = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
    /// 小号指标数字(chip 内)
    static let metricSmall = Font.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()

    /// 页面主标题
    static let screenTitle = Font.title2.weight(.bold)
    /// 区块标题
    static let sectionTitle = Font.headline
    /// 卡片标题 / 列表行主文案
    static let rowTitle = Font.body.weight(.medium)
    /// 正文
    static let body = Font.body
    /// 次要说明
    static let meta = Font.subheadline
    /// 标签 / 徽标文字。比 .caption2 大一档, 后者在小机型上几乎不可读
    static let label = Font.caption.weight(.medium)
}
