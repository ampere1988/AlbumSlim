import Foundation
import Vision
import UIKit
import SwiftUI

enum ScreenshotCategory: String, CaseIterable {
    case verificationCode = "验证码"
    case address          = "地址"
    case chatRecord       = "聊天记录"
    case article          = "文章"
    case receipt          = "账单/收据"
    case delivery         = "快递"
    case meeting          = "会议"
    case code             = "代码"
    case socialMedia      = "社交媒体"
    case other            = "其他"

    var color: Color {
        switch self {
        case .verificationCode: .red
        case .address: .orange
        case .chatRecord: .green
        case .article: .blue
        case .receipt: .purple
        case .delivery: .brown
        case .meeting: .cyan
        case .code: .indigo
        case .socialMedia: .pink
        case .other: .gray
        }
    }

    var localizedName: String {
        switch self {
        case .verificationCode: return String(localized: "验证码")
        case .address:          return String(localized: "地址")
        case .chatRecord:       return String(localized: "聊天记录")
        case .article:          return String(localized: "文章")
        case .receipt:          return String(localized: "账单/收据")
        case .delivery:         return String(localized: "快递")
        case .meeting:          return String(localized: "会议")
        case .code:             return String(localized: "代码")
        case .socialMedia:      return String(localized: "社交媒体")
        case .other:            return String(localized: "其他")
        }
    }
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

        if lower.contains("验证码") || lower.range(of: #"\b\d{4,6}\b"#, options: .regularExpression) != nil {
            return .verificationCode
        }

        let deliveryKeywords = ["顺丰", "圆通", "中通", "韵达", "申通", "极兔", "京东快递", "邮政", "运单号", "快递单号", "物流"]
        if deliveryKeywords.contains(where: { lower.contains($0) })
            || lower.range(of: #"[A-Z]{2}\d{9,13}"#, options: .regularExpression) != nil
            || lower.range(of: #"\d{12,15}"#, options: .regularExpression) != nil {
            return .delivery
        }

        if lower.contains("¥") || lower.contains("订单") || lower.contains("支付") || lower.contains("收据") || lower.contains("发票") {
            return .receipt
        }

        let meetingKeywords = ["腾讯会议", "飞书", "钉钉", "zoom", "会议号", "入会", "teams", "webex", "会议室"]
        if meetingKeywords.contains(where: { lower.contains($0) }) {
            return .meeting
        }

        let codeKeywords = ["func ", "class ", "import ", "def ", "const ", "var ", "let ", "return ", "struct ", "enum ",
                            "if (", "for (", "while ", "switch ", "print(", "console.log", "public ", "private ", "->"]
        if codeKeywords.filter({ lower.contains($0) }).count >= 2 {
            return .code
        }

        let socialKeywords = ["微博", "朋友圈", "抖音", "小红书", "微信", "qq空间", "快手", "b站", "bilibili", "知乎",
                              "转发", "点赞", "评论", "关注"]
        if socialKeywords.filter({ lower.contains($0) }).count >= 2 {
            return .socialMedia
        }

        if lower.contains("省") || lower.contains("市") || lower.contains("区") || lower.contains("路") {
            return .address
        }

        if text.count > 200 {
            return .article
        }

        return .other
    }
}
