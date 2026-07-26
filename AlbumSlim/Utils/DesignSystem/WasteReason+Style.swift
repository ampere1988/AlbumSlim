import SwiftUI

/// 废片原因的统一视觉映射。
///
/// 颜色按"这张照片有多没救"排序：纯黑/纯白是确定无用的中性灰，
/// 模糊是可惜但可能想留的琥珀色，遮挡/误拍是几乎必删的红与紫。
extension WasteReason {
    var label: LocalizedStringKey {
        switch self {
        case .pureBlack: "纯黑"
        case .pureWhite: "纯白"
        case .blurry: "模糊"
        case .fingerBlock: "遮挡"
        case .accidental: "误拍"
        }
    }

    var icon: String {
        switch self {
        case .pureBlack: "moon.fill"
        case .pureWhite: "sun.max.fill"
        case .blurry: "camera.filters"
        case .fingerBlock: "hand.raised.fill"
        case .accidental: "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pureBlack, .pureWhite: Theme.textSecondary
        case .blurry: Theme.warning
        case .fingerBlock: Theme.danger
        case .accidental: Theme.burst
        }
    }
}
