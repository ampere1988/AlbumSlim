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

    init() {
        self.photoLibrary = PhotoLibraryService()
        self.storageAnalyzer = StorageAnalyzer()
        self.aiEngine = AIAnalysisEngine()
        self.videoCompression = VideoCompressionService()
        self.videoAnalysis = VideoAnalysisService()
        self.imageSimilarity = ImageSimilarityService()
        self.ocrService = OCRService()
        self.cleanupCoordinator = CleanupCoordinator()
        self.subscription = SubscriptionService()
    }
}
