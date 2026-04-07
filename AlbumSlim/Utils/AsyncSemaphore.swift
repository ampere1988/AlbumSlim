import Foundation

/// 简单的异步信号量，用于限制并发任务数量
final class AsyncSemaphore: @unchecked Sendable {
    private let semaphore: DispatchSemaphore
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
        self.semaphore = DispatchSemaphore(value: limit)
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
    }

    func signal() {
        semaphore.signal()
    }
}
