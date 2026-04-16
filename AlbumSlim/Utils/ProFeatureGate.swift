import Foundation

enum ProFeatureGate {
    /// 所有清理/删除/压缩操作统一检查
    static func canClean(isPro: Bool) -> Bool { isPro }
}
