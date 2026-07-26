import SwiftUI

/// 层级刻度。
///
/// 深色模式下阴影几乎不可见, 层次要靠表面亮度和描边表达; 浅色模式下反过来
/// 靠阴影表达。所以 elevation 不是单一的"阴影强度", 而是两套映射。
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
        case .card: 12
        case .floating: 24
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .flat: 0
        case .card: 4
        case .floating: 10
        }
    }

    /// 浅色模式下的阴影不透明度
    var lightOpacity: Double {
        switch self {
        case .flat: 0
        case .card: 0.06
        case .floating: 0.12
        }
    }

    /// 深色模式下阴影仅用于把浮层从背景里"抠"出来, 因此更浓但更集中
    var darkOpacity: Double {
        switch self {
        case .flat: 0
        case .card: 0.24
        case .floating: 0.44
        }
    }
}
