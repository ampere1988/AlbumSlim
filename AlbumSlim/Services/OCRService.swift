import Foundation
import Vision
import UIKit

enum ScreenshotCategory: String, CaseIterable {
    case verificationCode = "验证码"
    case address          = "地址"
    case chatRecord       = "聊天记录"
    case article          = "文章"
    case receipt          = "账单/收据"
    case other            = "其他"
}

struct OCRResult {
    let text: String
    let category: ScreenshotCategory
    let confidence: Float
}

@MainActor
final class OCRService {

    func recognizeText(from image: UIImage) async -> OCRResult? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                let category = self.categorize(text)
                let avgConfidence = observations.isEmpty ? 0 :
                    observations.reduce(Float(0)) { $0 + ($1.topCandidates(1).first?.confidence ?? 0) }
                    / Float(observations.count)

                continuation.resume(returning: OCRResult(
                    text: text,
                    category: category,
                    confidence: avgConfidence
                ))
            }

            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }

    private func categorize(_ text: String) -> ScreenshotCategory {
        let lower = text.lowercased()
        if lower.contains("验证码") || lower.range(of: #"\d{4,6}"#, options: .regularExpression) != nil {
            return .verificationCode
        }
        if lower.contains("省") || lower.contains("市") || lower.contains("区") || lower.contains("路") {
            return .address
        }
        if lower.contains("¥") || lower.contains("订单") || lower.contains("支付") {
            return .receipt
        }
        if text.count > 200 {
            return .article
        }
        return .other
    }
}
