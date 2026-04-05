import Foundation
import BackgroundTasks
import UIKit

@MainActor @Observable
final class BackgroundTaskService {
    static let processingTaskID = "com.hao.doushan.analysis"

    private(set) var lastBackgroundScanAt: Date? = UserDefaults.standard.object(forKey: "lastBackgroundScanAt") as? Date

    /// 后台任务被要求停止时设为 true
    private var shouldCancel = false

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
        // 1. beginBackgroundTask 保护当前扫描
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        // 2. 安排 BGProcessingTask
        scheduleProcessingTask()
    }

    func handleEnterForeground() {
        endBackgroundTask()
        shouldCancel = false
    }

    // MARK: - BGProcessingTask 执行

    private func handleProcessingTask(_ task: BGProcessingTask, services: AppServiceContainer) async {
        // 安排下一次
        scheduleProcessingTask()

        shouldCancel = false
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.shouldCancel = true
            }
        }

        let cancelPtr: UnsafeMutablePointer<Bool> = withUnsafeMutablePointer(to: &shouldCancel) { $0 }
        await services.cleanupCoordinator.backgroundAnalyze(
            services: services,
            cancelFlag: cancelPtr
        )

        lastBackgroundScanAt = .now
        UserDefaults.standard.set(lastBackgroundScanAt, forKey: "lastBackgroundScanAt")

        task.setTaskCompleted(success: !shouldCancel)
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
