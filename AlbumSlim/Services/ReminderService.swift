import Foundation
import UserNotifications

@MainActor @Observable
final class ReminderService {
    var isReminderEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "reminderEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "reminderEnabled")
            if newValue { scheduleReminder() } else { cancelReminder() }
        }
    }

    var reminderInterval: ReminderInterval {
        get {
            let raw = UserDefaults.standard.string(forKey: "reminderInterval") ?? ReminderInterval.weekly.rawValue
            return ReminderInterval(rawValue: raw) ?? .weekly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "reminderInterval")
            if isReminderEnabled { scheduleReminder() }
        }
    }

    enum ReminderInterval: String, CaseIterable {
        case weekly = "每周"
        case biweekly = "每两周"
        case monthly = "每月"

        var calendarComponent: Calendar.Component {
            switch self {
            case .weekly: .weekOfYear
            case .biweekly: .weekOfYear
            case .monthly: .month
            }
        }

        var value: Int {
            switch self {
            case .weekly: 1
            case .biweekly: 2
            case .monthly: 1
            }
        }

        var localizedName: String {
            switch self {
            case .weekly:    return String(localized: "每周")
            case .biweekly:  return String(localized: "每两周")
            case .monthly:   return String(localized: "每月")
            }
        }
    }

    func requestNotificationPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func scheduleReminder() {
        cancelReminder()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "该清理相册了")
        content.body = String(localized: "您的相册可能积累了不少新照片，来看看有哪些可以清理吧")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 1
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger: UNNotificationTrigger
        switch reminderInterval {
        case .weekly:
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        case .biweekly:
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 14 * 24 * 3600, repeats: true)
        case .monthly:
            dateComponents.weekday = nil
            dateComponents.day = 1
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        }

        let request = UNNotificationRequest(identifier: "cleanup-reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["cleanup-reminder"])
    }
}
