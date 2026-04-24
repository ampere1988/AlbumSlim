import Foundation
import Photos

@MainActor @Observable
final class AppServiceContainer {
    let photoLibrary: PhotoLibraryService
    let storageAnalyzer: StorageAnalyzer
    let aiEngine: AIAnalysisEngine
    let videoCompression: VideoCompressionService
    let videoAnalysis: VideoAnalysisService
    let imageSimilarity: ImageSimilarityService
    let ocrService: OCRService
    let cleanupCoordinator: CleanupCoordinator
    let subscription: SubscriptionService
    let analysisCache: AnalysisCacheService
    let achievement: AchievementService
    let notesExport: NotesExportService
    let reminder: ReminderService
    let backgroundTask: BackgroundTaskService
    let trash: TrashService
    let locationName: LocationNameService
    let backdrop: BackdropAdapterService

    private(set) var isReady = false
    private var prepareTask: Task<Void, Never>?

    init() {
        self.photoLibrary = PhotoLibraryService()
        self.storageAnalyzer = StorageAnalyzer()
        self.aiEngine = AIAnalysisEngine()
        self.videoCompression = VideoCompressionService()
        self.videoAnalysis = VideoAnalysisService()
        self.imageSimilarity = ImageSimilarityService()
        self.ocrService = OCRService()
        self.cleanupCoordinator = CleanupCoordinator()
        self.cleanupCoordinator.restoreScannedVersions()
        self.notesExport = NotesExportService()
        self.subscription = SubscriptionService()
        self.analysisCache = AnalysisCacheService()
        self.achievement = AchievementService()
        self.reminder = ReminderService()
        self.backgroundTask = BackgroundTaskService()
        self.trash = TrashService()
        self.locationName = LocationNameService()
        self.backdrop = BackdropAdapterService()
    }

    /// 异步恢复缓存数据，不阻塞主线程。幂等：并发多次调用共享同一次执行
    func prepareAsync() async {
        if isReady { return }
        if let task = prepareTask {
            await task.value
            return
        }
        let task = Task { @MainActor in
            await cleanupCoordinator.restoreGroups(using: photoLibrary)
            isReady = true
        }
        prepareTask = task
        await task.value
    }
}
