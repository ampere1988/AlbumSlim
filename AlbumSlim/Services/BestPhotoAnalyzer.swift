import Foundation
import CoreImage
import Photos
import UIKit

/// 单张照片的三维打分信号，各项均归一化到 0...1
struct PhotoSignals: Sendable {
    /// 技术质量：锐度/曝光/分辨率，来自 AIAnalysisEngine.qualityScore
    var technical: Float
    /// 人脸质量：微笑 + 睁眼；无人脸时为中性 0.5
    var face: Float
    /// 用户行为信号：收藏 / 编辑过
    var behavior: Float
}

/// 在技术质量之上叠加人脸与用户行为信号，选出一组照片里最该保留的那张。
///
/// 权重设计说明：
/// - technical 0.45 —— 糊片再有笑脸也不该留
/// - face 0.25 —— 人像场景的决定性差异；风景照走中性值不产生偏置
/// - behavior 0.30 —— 用户自己收藏/修过的照片是最可信的保留意图
final class BestPhotoAnalyzer: @unchecked Sendable {

    private static let technicalWeight: Float = 0.45
    private static let faceWeight: Float = 0.25
    private static let behaviorWeight: Float = 0.30

    /// CIDetector 创建开销大，复用同一实例
    private let detector: CIDetector?

    init() {
        let context = CIContext(options: nil)
        detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: context,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }

    // MARK: - 合成

    static func compositeScore(_ signals: PhotoSignals) -> Float {
        signals.technical * technicalWeight
            + signals.face * faceWeight
            + signals.behavior * behaviorWeight
    }

    func signals(for cgImage: CGImage, asset: PHAsset, engine: AIAnalysisEngine) -> PhotoSignals {
        PhotoSignals(
            technical: engine.qualityScore(for: cgImage),
            face: faceScore(for: cgImage),
            behavior: Self.behaviorScore(for: asset)
        )
    }

    // MARK: - 人脸信号

    /// 返回 0...1。无人脸返回中性 0.5，避免风景照被系统性判劣。
    /// 多张人脸时取各脸得分的均值——合照里大家都在笑才算好照片。
    func faceScore(for cgImage: CGImage) -> Float {
        guard let detector else { return 0.5 }
        let ciImage = CIImage(cgImage: cgImage)
        let features = detector.features(in: ciImage, options: [
            CIDetectorSmile: true,
            CIDetectorEyeBlink: true,
        ])
        let faces = features.compactMap { $0 as? CIFaceFeature }
        guard !faces.isEmpty else { return 0.5 }

        var total: Float = 0
        for face in faces {
            // 睁眼 0.6 权重（闭眼是硬伤），微笑 0.4 权重
            let bothEyesOpen = !face.leftEyeClosed && !face.rightEyeClosed
            let eyeScore: Float = bothEyesOpen ? 1.0 : (face.leftEyeClosed && face.rightEyeClosed ? 0.0 : 0.4)
            let smileScore: Float = face.hasSmile ? 1.0 : 0.5
            total += eyeScore * 0.6 + smileScore * 0.4
        }
        return total / Float(faces.count)
    }

    // MARK: - 择优

    /// 从候选中选出最佳。同分时取文件更大者（保留旧行为作为 tiebreaker）。
    static func pickBest(from candidates: [(id: String, score: Float, fileSize: Int64)]) -> String? {
        candidates.max { lhs, rhs in
            if abs(lhs.score - rhs.score) < 0.0001 {
                return lhs.fileSize < rhs.fileSize
            }
            return lhs.score < rhs.score
        }?.id
    }

    // MARK: - 行为信号

    static func behaviorScore(for asset: PHAsset) -> Float {
        behaviorScoreValue(isFavorite: asset.isFavorite, isEdited: isEdited(asset))
    }

    /// 纯值函数，便于单测（不依赖 PHAsset 构造）
    static func behaviorScoreValue(isFavorite: Bool, isEdited: Bool) -> Float {
        if isFavorite { return 1.0 }
        return isEdited ? 0.7 : 0.3
    }

    /// 通过 PHAssetResource 是否含 adjustmentData 判断照片被编辑过
    static func isEdited(_ asset: PHAsset) -> Bool {
        PHAssetResource.assetResources(for: asset).contains { $0.type == .adjustmentData }
    }
}
