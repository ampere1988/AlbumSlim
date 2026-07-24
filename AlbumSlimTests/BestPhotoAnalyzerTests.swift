import XCTest
import Photos
import UIKit
@testable import AlbumSlim

final class BestPhotoAnalyzerTests: XCTestCase {

    func testCompositeScoreWeightsSumToOne() {
        // 三项信号全 1 时合成分应为 1（权重和为 1）
        let signals = PhotoSignals(technical: 1.0, face: 1.0, behavior: 1.0)
        XCTAssertEqual(BestPhotoAnalyzer.compositeScore(signals), 1.0, accuracy: 0.001)
    }

    func testCompositeScoreAllZeroIsZero() {
        let signals = PhotoSignals(technical: 0, face: 0, behavior: 0)
        XCTAssertEqual(BestPhotoAnalyzer.compositeScore(signals), 0, accuracy: 0.001)
    }

    func testFaceSignalOutweighsNothingWhenTechnicalTied() {
        // 技术质量相同时，有笑脸睁眼的一张必须胜出
        let smiling = PhotoSignals(technical: 0.5, face: 1.0, behavior: 0.3)
        let neutral = PhotoSignals(technical: 0.5, face: 0.5, behavior: 0.3)
        XCTAssertGreaterThan(
            BestPhotoAnalyzer.compositeScore(smiling),
            BestPhotoAnalyzer.compositeScore(neutral)
        )
    }

    func testFavoriteBehaviorScoreIsMaximum() {
        // 收藏是最强保留信号，必须拿满分
        XCTAssertEqual(BestPhotoAnalyzer.behaviorScoreValue(isFavorite: true, isEdited: false), 1.0, accuracy: 0.001)
        XCTAssertEqual(BestPhotoAnalyzer.behaviorScoreValue(isFavorite: true, isEdited: true), 1.0, accuracy: 0.001)
    }

    func testEditedBeatsUntouched() {
        let edited = BestPhotoAnalyzer.behaviorScoreValue(isFavorite: false, isEdited: true)
        let untouched = BestPhotoAnalyzer.behaviorScoreValue(isFavorite: false, isEdited: false)
        XCTAssertGreaterThan(edited, untouched)
        XCTAssertLessThan(edited, 1.0)
    }

    func testNoFaceReturnsNeutralScore() {
        // 纯色图无人脸，应返回中性 0.5 而不是 0——否则风景照会被系统性判劣
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let analyzer = BestPhotoAnalyzer()
        let score = analyzer.faceScore(for: image.cgImage!)
        XCTAssertEqual(score, 0.5, accuracy: 0.001)
    }
}
