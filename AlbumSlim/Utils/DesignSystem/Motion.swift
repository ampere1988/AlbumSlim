import SwiftUI

/// 动效刻度 —— 普通状态变化保持短促、稳定，弹性只留给完成反馈。
enum Motion {
    /// 120ms — 按压/松手这种必须"立刻"的反馈
    static let instant = Animation.spring(duration: 0.12, bounce: 0)
    /// 220ms — 默认微交互: 选中、展开、chip 切换
    static let standard = Animation.spring(duration: 0.22, bounce: 0)
    /// 300ms — 卡片入场、面板滑出
    static let emphasized = Animation.spring(duration: 0.28, bounce: 0.04)
    /// 400ms — 仅用于一次性的成果展示(清理完成、成就解锁)
    static let celebratory = Animation.spring(duration: 0.4, bounce: 0.18)

    /// 列表逐项入场的单项延迟
    static let staggerStep: Double = 0.05
    /// 最多错峰到第几项, 再多就同时出现, 否则长列表尾部要等太久
    static let staggerCap = 8

    static func staggerDelay(index: Int) -> Double {
        Double(min(index, staggerCap)) * staggerStep
    }
}
