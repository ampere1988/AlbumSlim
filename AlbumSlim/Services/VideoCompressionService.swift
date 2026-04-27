import Foundation
import AVFoundation
import Photos
import UserNotifications

enum CompressionQuality: String, CaseIterable {
    case high   = "高质量"
    case medium = "中质量"
    case low    = "省空间"

    var exportPreset: String {
        switch self {
        case .high:   return AVAssetExportPresetHEVC1920x1080
        case .medium: return AVAssetExportPresetMediumQuality
        case .low:    return AVAssetExportPresetLowQuality
        }
    }

    var estimatedSavingsPercent: String {
        switch self {
        case .high:   return "40-60%"
        case .medium: return "60-80%"
        case .low:    return "80-90%"
        }
    }

    var localizedName: String {
        switch self {
        case .high:   return String(localized: "高质量")
        case .medium: return String(localized: "中质量")
        case .low:    return String(localized: "省空间")
        }
    }
}

struct CompressionTask: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let quality: CompressionQuality
    var status: CompressionTaskStatus = .pending

    enum CompressionTaskStatus {
        case pending, compressing, completed, failed(Error)
    }
}

@MainActor @Observable
final class VideoCompressionService {
    private(set) var progress: Double = 0
    private(set) var isCompressing = false
    private(set) var queue: [CompressionTask] = []
    private(set) var isProcessingQueue = false

    func enqueueCompression(asset: PHAsset, quality: CompressionQuality) {
        queue.append(CompressionTask(asset: asset, quality: quality))
    }

    func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        defer { isProcessingQueue = false }

        while let index = queue.firstIndex(where: {
            if case .pending = $0.status { return true }
            return false
        }) {
            queue[index].status = .compressing
            do {
                let url = try await compressVideo(asset: queue[index].asset, quality: queue[index].quality)
                try await replaceOriginal(asset: queue[index].asset, with: url)
                queue[index].status = .completed
            } catch {
                queue[index].status = .failed(error)
            }
        }

        await sendCompletionNotification()
    }

    func compressVideo(asset: PHAsset, quality: CompressionQuality) async throws -> URL {
        isCompressing = true
        defer { isCompressing = false; progress = 0 }

        let inputURL = try await exportOriginalVideo(asset: asset)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let avAsset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: avAsset, presetName: quality.exportPreset) else {
            throw CompressionError.exportSessionFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled {
                progress = Double(session.progress)
                try await Task.sleep(for: .milliseconds(200))
            }
        }

        await session.export()
        progressTask.cancel()

        // 清理临时输入文件（如果是我们拷贝出来的）
        if inputURL.path.contains(NSTemporaryDirectory()) {
            try? FileManager.default.removeItem(at: inputURL)
        }

        if session.status == .completed {
            progress = 1.0
            return outputURL
        } else {
            // 清理失败的输出文件
            try? FileManager.default.removeItem(at: outputURL)
            throw session.error ?? CompressionError.unknown
        }
    }

    func estimateCompressedSize(asset: PHAsset, quality: CompressionQuality) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first,
              let originalSize = resource.value(forKey: "fileSize") as? Int64 else { return 0 }

        let ratio: Double = switch quality {
        case .high:   0.5
        case .medium: 0.3
        case .low:    0.15
        }
        return Int64(Double(originalSize) * ratio)
    }

    func saveCompressedToLibrary(url: URL) async throws {
        try await Self.performSave(videoFileURL: url)
        cleanupTempFile(url)
    }

    func replaceOriginal(asset: PHAsset, with url: URL) async throws {
        try await Self.performReplace(asset: asset, videoFileURL: url)
        cleanupTempFile(url)
    }

    /// nonisolated 入口：避免 @MainActor 类闭包被隐式隔离到主线程，
    /// 与 Photos changes queue 冲突触发 _dispatch_assert_queue_fail
    private nonisolated static func performSave(videoFileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoFileURL)
        }
    }

    private nonisolated static func performReplace(asset: PHAsset, videoFileURL: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoFileURL)
            PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
        }
    }

    func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func sendCompletionNotification() async {
        let completed = queue.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
        let failed = queue.filter {
            if case .failed = $0.status { return true }
            return false
        }.count

        let content = UNMutableNotificationContent()
        content.title = String(localized: "视频压缩完成")
        content.body = failed > 0
            ? String(localized: "成功压缩 \(completed) 个视频，\(failed) 个失败")
            : String(localized: "成功压缩 \(completed) 个视频")
        content.sound = .default

        let request = UNNotificationRequest(identifier: "compression-done", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func exportOriginalVideo(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else if let composition = avAsset as? AVComposition {
                    // 慢动作视频等返回 AVComposition，需要导出为临时文件
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mov")
                    guard let exportSession = AVAssetExportSession(
                        asset: composition,
                        presetName: AVAssetExportPresetPassthrough
                    ) else {
                        continuation.resume(throwing: CompressionError.exportSessionFailed)
                        return
                    }
                    exportSession.outputURL = tempURL
                    exportSession.outputFileType = .mov
                    exportSession.exportAsynchronously {
                        if exportSession.status == .completed {
                            continuation.resume(returning: tempURL)
                        } else {
                            continuation.resume(throwing: exportSession.error ?? CompressionError.assetNotAvailable)
                        }
                    }
                } else {
                    continuation.resume(throwing: CompressionError.assetNotAvailable)
                }
            }
        }
    }
}

enum CompressionError: LocalizedError {
    case exportSessionFailed
    case assetNotAvailable
    case saveFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .exportSessionFailed: return String(localized: "无法创建压缩会话")
        case .assetNotAvailable:   return String(localized: "视频不可用（可能在 iCloud 中）")
        case .saveFailed:          return String(localized: "保存失败")
        case .unknown:             return String(localized: "压缩失败")
        }
    }
}
