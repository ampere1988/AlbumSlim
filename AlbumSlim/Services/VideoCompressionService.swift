import Foundation
import AVFoundation
import Photos

enum CompressionQuality: String, CaseIterable {
    case high   = "高质量"   // 1920x1080
    case medium = "中质量"   // 1280x720
    case low    = "省空间"   // 640x480

    var exportPreset: String {
        switch self {
        case .high:   return AVAssetExportPresetHEVC1920x1080
        case .medium: return AVAssetExportPresetHEVC1920x1080 // 降级处理
        case .low:    return AVAssetExportPresetHEVCHighestQuality
        }
    }

    var estimatedSavingsPercent: String {
        switch self {
        case .high:   return "40-60%"
        case .medium: return "60-80%"
        case .low:    return "80-90%"
        }
    }
}

@MainActor @Observable
final class VideoCompressionService {
    private(set) var progress: Double = 0
    private(set) var isCompressing = false

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

        // 监控进度
        let progressTask = Task {
            while !Task.isCancelled {
                progress = Double(session.progress)
                try await Task.sleep(for: .milliseconds(200))
            }
        }

        await session.export()
        progressTask.cancel()

        if session.status == .completed {
            progress = 1.0
            return outputURL
        } else {
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

    // MARK: - Private

    private func exportOriginalVideo(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
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
    case unknown

    var errorDescription: String? {
        switch self {
        case .exportSessionFailed: return "无法创建压缩会话"
        case .assetNotAvailable:   return "视频不可用"
        case .unknown:             return "压缩失败"
        }
    }
}
