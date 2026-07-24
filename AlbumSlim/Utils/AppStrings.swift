import Foundation

/// 全局文案常量，统一术语
enum AppStrings {
    // 动作
    static let select = String(localized: "选择")
    static let done = String(localized: "完成")
    static let selectAll = String(localized: "全选")
    static let deselectAll = String(localized: "取消全选")
    static let cancel = String(localized: "取消")
    static let restore = String(localized: "恢复")
    static let moveToTrash = String(localized: "移到垃圾桶")
    static let permanentlyDelete = String(localized: "永久删除")
    static let emptyTrash = String(localized: "全部清空")

    // 加载文案
    static let loading = String(localized: "加载中…")
    static let scanning = String(localized: "扫描中…")
    static let analyzing = String(localized: "分析中…")
    static let compressing = String(localized: "压缩中…")
    static let recognizing = String(localized: "识别中…")

    // 计数 / 数量格式
    static func selected(_ count: Int) -> String { String(localized: "已选 \(count) 项") }
    static func items(_ count: Int) -> String { String(localized: "\(count) 项") }
    static func releasable(_ bytes: Int64) -> String {
        String(localized: "可释放 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
    }

    // Toast 反馈
    static func movedToTrash(_ count: Int, freed: Int64) -> String {
        freed > 0
            ? String(localized: "已移到垃圾桶 \(count) 项 · 可释放 \(freed.formattedFileSize)")
            : String(localized: "已移到垃圾桶 \(count) 项")
    }
    static func restored(_ count: Int) -> String { String(localized: "已恢复 \(count) 项") }
    static func permanentlyDeleted(_ count: Int, freed: Int64) -> String {
        String(localized: "已永久删除 \(count) 项，释放 \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))")
    }
    static func compressed(_ saved: Int64) -> String {
        String(localized: "已压缩，节省 \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file))")
    }
    static let saved = String(localized: "已保存")
    static let copied = String(localized: "已复制到剪贴板")
    static let proRequired = String(localized: "此功能需要 Pro")

    // 空状态前缀
    static func empty(_ object: String) -> String { String(localized: "没有\(object)") }

    // 永久删除确认
    static func confirmPermanentDeleteTitle(_ count: Int) -> String { String(localized: "永久删除 \(count) 项？") }
    static let confirmPermanentDeleteMessage = String(localized: "照片将移入系统相册的「最近删除」，30 天内仍可在系统相册中找回")
    static let confirmEmptyTrashMessage = String(localized: "照片将移入系统相册的「最近删除」，30 天内仍可在系统相册中找回")
}
