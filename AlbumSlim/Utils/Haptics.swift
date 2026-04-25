import UIKit

/// 全局触觉反馈封装。所有关键交互必须走这里。
@MainActor
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // 高层语义封装
    static func tap()              { light() }
    static func toggleSelect()     { selection() }
    static func moveToTrash()      { medium() }
    static func permanentDelete()  { heavy(); warning() }
    static func operationSuccess() { success() }
    static func proGate()          { warning() }
}
