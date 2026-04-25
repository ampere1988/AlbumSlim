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

    private var pendingQueue: [(ToastMessage, TimeInterval)] = []
    private var displayTask: Task<Void, Never>?
    private static let maxQueueSize = 3

    func show(icon: String, text: String, tint: Color = .primary, duration: TimeInterval = 1.5) {
        let message = ToastMessage(icon: icon, text: text, tint: tint)

        if current == nil {
            // 没有正在显示的 toast，直接展示
            current = message
            scheduleNext(after: duration)
        } else {
            // 排队，限制队列长度（丢弃最旧的等待项）
            pendingQueue.append((message, duration))
            if pendingQueue.count > Self.maxQueueSize {
                pendingQueue.removeFirst(pendingQueue.count - Self.maxQueueSize)
            }
        }
    }

    private func scheduleNext(after duration: TimeInterval) {
        displayTask?.cancel()
        displayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.advance()
        }
    }

    private func advance() {
        if pendingQueue.isEmpty {
            current = nil
        } else {
            let (next, duration) = pendingQueue.removeFirst()
            current = next
            scheduleNext(after: duration)
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

    func failure(_ text: String) {
        show(icon: "exclamationmark.triangle.fill", text: text, tint: .orange)
    }
}
