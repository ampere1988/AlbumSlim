import SwiftUI

/// 清理分类的统一视觉映射 —— 图标、颜色、标题只在这里定义一次，
/// 智能扫描、各清理页、成就页引用同一套，避免"同一类东西换页就换色"。
extension CleanupGroup.GroupType {
    var icon: String {
        switch self {
        case .waste: AppIcons.waste
        case .similar: AppIcons.similar
        case .burst: AppIcons.burst
        case .screenshot: AppIcons.screenshot
        case .largePhoto: AppIcons.largePhoto
        case .largeVideo: AppIcons.video
        }
    }

    var tint: Color {
        switch self {
        case .waste: Theme.danger
        case .similar: Theme.photo
        case .burst: Theme.burst
        case .screenshot: Theme.screenshot
        case .largePhoto: Theme.accentSecondary
        case .largeVideo: Theme.video
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .waste: "废片"
        case .similar: "相似照片"
        case .burst: "连拍多余"
        case .screenshot: "截图"
        case .largePhoto: "超大照片"
        case .largeVideo: "大视频"
        }
    }
}
