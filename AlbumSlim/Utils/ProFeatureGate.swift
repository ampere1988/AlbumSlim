import Foundation

enum ProFeatureGate {
    static func canCleanWaste(currentCount: Int, isPro: Bool) -> Bool {
        isPro || currentCount < 20
    }

    static func canViewSimilarGroup(groupIndex: Int, isPro: Bool) -> Bool {
        true // TODO: 恢复 Pro 限制: isPro || groupIndex < 3
    }

    static func canCompress(isPro: Bool) -> Bool { isPro }

    static func canOCR(isPro: Bool) -> Bool { isPro }

    static func canQuickClean(isPro: Bool) -> Bool { isPro }
}
