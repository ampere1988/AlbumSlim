import Foundation
import BackgroundTasks
import UIKit

@MainActor @Observable
final class BackgroundTaskService {
    static let processingTaskID = "com.hao.doushan.analysis"

    private(set) var lastBackgroundScanAt: Date? = UserDefaults.standard.object(forKey: "lastBackgroundScanAt") as? Date

    private var analyzeTask: Task<Void, Never>?

    /// 当前后台延长任务的标识
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - 注册（必须在 App 启动时、didFinishLaunching 返回前调用）

    func registerBackgroundTasks(services: AppServiceContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskID,
            using: nil
        ) { [weak self] task in
            guard let self, let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await self.handleProcessingTask(task, services: services)
            }
        }
    }

    // MARK: - scenePhase 事件

    func handleEnterBackground(services: AppServiceContainer) {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.analyzeTask?.cancel()
            self?.endBackgroundTask()
        }
        scheduleProcessingTask()
    }

    func handleEnterForeground() {
        analyzeTask?.cancel()
        analyzeTask = nil
        endBackgroundTask()
    }

    // MARK: - BGProcessingTask 执行

    private func handleProcessingTask(_ task: BGProcessingTask, services: AppServiceContainer) async {
        // 安排下一次
        scheduleProcessingTask()

        task.expirationHandler = { [weak self] in
            self?.analyzeTask?.cancel()
        }

        analyzeTask = Task {
            await services.cleanupCoordinator.backgroundAnalyze(services: services)
        }
        await analyzeTask?.value

        lastBackgroundScanAt = .now
        UserDefaults.standard.set(lastBackgroundScanAt, forKey: "lastBackgroundScanAt")

        let cancelled = analyzeTask?.isCancelled ?? false
        analyzeTask = nil
        task.setTaskCompleted(success: !cancelled)
    }

    // MARK: - Private

    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskID)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        // 至少等 15 分钟再调度（避免频繁触发）
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
