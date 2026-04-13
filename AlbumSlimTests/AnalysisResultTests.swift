import Foundation
import Testing
@testable import AlbumSlim

@Suite("AnalysisResult 模型测试")
struct AnalysisResultTests {

    @Test("WasteReason 原始值")
    func wasteReasonRawValues() {
        #expect(WasteReason.pureBlack.rawValue == "pureBlack")
        #expect(WasteReason.pureWhite.rawValue == "pureWhite")
        #expect(WasteReason.blurry.rawValue == "blurry")
        #expect(WasteReason.fingerBlock.rawValue == "fingerBlock")
        #expect(WasteReason.accidental.rawValue == "accidental")
    }

    @Test("WasteReason Codable 编解码")
    func wasteReasonCodable() throws {
        let reasons: [WasteReason] = [.pureBlack, .pureWhite, .blurry, .fingerBlock, .accidental]
        let data = try JSONEncoder().encode(reasons)
        let decoded = try JSONDecoder().decode([WasteReason].self, from: data)
        #expect(decoded == reasons)
    }

    @Test("PhotoQuality 排序")
    func photoQualityOrdering() {
        #expect(PhotoQuality.low < PhotoQuality.medium)
        #expect(PhotoQuality.medium < PhotoQuality.high)
        #expect(!(PhotoQuality.high < PhotoQuality.low))
    }

    @Test("PhotoQuality Codable 编解码")
    func photoQualityCodable() throws {
        let qualities: [PhotoQuality] = [.low, .medium, .high]
        let data = try JSONEncoder().encode(qualities)
        let decoded = try JSONDecoder().decode([PhotoQuality].self, from: data)
        #expect(decoded == qualities)
    }
}
