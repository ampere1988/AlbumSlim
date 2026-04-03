import StoreKit
import UIKit

@MainActor
enum ReviewPromptManager {
    private static let cleanupCountKey = "reviewPrompt_cleanupCount"
    private static let lastPromptDateKey = "reviewPrompt_lastDate"
    private static let hasRatedKey = "reviewPrompt_hasRated"

    static func requestReviewIfAppropriate() {
        guard !UserDefaults.standard.bool(forKey: hasRatedKey) else { return }

        let count = UserDefaults.standard.integer(forKey: cleanupCountKey) + 1
        UserDefaults.standard.set(count, forKey: cleanupCountKey)

        guard count >= 3 else { return }

        if let lastPrompt = UserDefaults.standard.object(forKey: lastPromptDateKey) as? Date {
            guard Date().timeIntervalSince(lastPrompt) > 90 * 24 * 3600 else { return }
        }

        UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)

        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
