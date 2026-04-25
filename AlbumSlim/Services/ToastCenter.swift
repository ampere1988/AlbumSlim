import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
    let tint: Color
}

@MainActor @Observable
final class ToastCenter {
    private(set) var current: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    func show(icon: String, text: String, tint: Color = .primary, duration: TimeInterval = 1.5) {
        dismissTask?.cancel()
        current = ToastMessage(icon: icon, text: text, tint: tint)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    // 高层语义封装
    func movedToTrash(_ count: Int) {
        show(icon: AppIcons.trash, text: AppStrings.movedToTrash(count))
    }

    func restored(_ count: Int) {
        show(icon: AppIcons.restore, text: AppStrings.restored(count), tint: .blue)
    }

    func permanentlyDeleted(_ count: Int, freed: Int64) {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.permanentlyDeleted(count, freed: freed), tint: .green)
    }

    func compressed(_ saved: Int64) {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.compressed(saved), tint: .green)
    }

    func saved() {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.saved, tint: .green)
    }

    func copied() {
        show(icon: AppIcons.checkmarkCircleFill, text: AppStrings.copied, tint: .green)
    }

    func proRequired() {
        show(icon: AppIcons.proCrown, text: AppStrings.proRequired, tint: .orange)
    }
}
