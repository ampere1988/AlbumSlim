import UserNotifications
import Foundation

/// 处理用户点击本地通知的路由。目前仅处理清理提醒通知("cleanup-reminder")的深链跳转。
///
/// 冷启动场景下，本 delegate 的回调会先于 SwiftUI 视图完成 `.onReceive` 订阅执行，
/// 直接 `post` 的通知会丢失。因此这里同时写入 UserDefaults 标记，MainTabView 在
/// `.task` 里检查并消费该标记，保证冷启动和热启动都能可靠打开 QuickClean。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static let shared = NotificationDelegate()

    static let pendingOpenQuickCleanKey = "pendingOpenQuickClean"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.notification.request.identifier == "cleanup-reminder" {
            UserDefaults.standard.set(true, forKey: Self.pendingOpenQuickCleanKey)
            await MainActor.run {
                NotificationCenter.default.post(name: .openQuickClean, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let openQuickClean = Notification.Name("openQuickClean")
}
