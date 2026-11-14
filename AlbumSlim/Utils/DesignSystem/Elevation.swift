import SwiftUI

/// 层级刻度。
///
/// 原生分组界面主要靠系统表面色分层，阴影仅留给真正悬浮的操作面板。
enum Elevation {
    /// 与背景同层, 只靠描边区分
    case flat
    /// 常规卡片
    case card
    /// 浮在内容之上(底部操作栏、弹出面板)
    case floating

    var shadowRadius: CGFloat {
        switch self {
        case .flat: 0
        case .card: 0
        case .floating: 12
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .flat: 0
        case .card: 0
        case .floating: 5
        }
    }

    /// 浅色模式下的阴影不透明度
    var lightOpacity: Double {
        switch self {
        case .flat: 0
        case .card: 0
        case .floating: 0.10
        }
    }

    /// 深色模式下阴影仅用于把浮层从背景里"抠"出来, 因此更浓但更集中
    var darkOpacity: Double {
        switch self {
        case .flat: 0
        case .card: 0
        case .floating: 0.28
        }
    }
}
