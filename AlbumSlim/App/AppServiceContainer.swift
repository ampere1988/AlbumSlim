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

    private(set) var isReady = false

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
    }

    /// 异步恢复缓存数据，不阻塞主线程
    func prepareAsync() async {
        await cleanupCoordinator.restoreGroups(using: photoLibrary)
        isReady = true
    }
}
