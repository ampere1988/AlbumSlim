import SwiftUI

/// 动效刻度 —— 微交互统一落在 150–300ms, 超过 500ms 的动画一律不做
///
/// 曲线取 Expo.out 手感(起步快、尾部长收), 用 SwiftUI 原生 spring 的
/// `bounce` 近似, 避免自定义 timing curve 在不同 iOS 版本上表现漂移。
enum Motion {
    /// 120ms — 按压/松手这种必须"立刻"的反馈
    static let instant = Animation.spring(duration: 0.12, bounce: 0)
    /// 220ms — 默认微交互: 选中、展开、chip 切换
    static let standard = Animation.spring(duration: 0.22, bounce: 0.1)
    /// 300ms — 卡片入场、面板滑出
    static let emphasized = Animation.spring(duration: 0.3, bounce: 0.18)
    /// 400ms — 仅用于一次性的成果展示(清理完成、成就解锁)
    static let celebratory = Animation.spring(duration: 0.4, bounce: 0.32)

    /// 列表逐项入场的单项延迟
    static let staggerStep: Double = 0.05
    /// 最多错峰到第几项, 再多就同时出现, 否则长列表尾部要等太久
    static let staggerCap = 8

    static func staggerDelay(index: Int) -> Double {
        Double(min(index, staggerCap)) * staggerStep
    }
}
