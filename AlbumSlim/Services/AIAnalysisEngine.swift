import Foundation
import Vision
import UIKit
import CoreImage

final class AIAnalysisEngine: @unchecked Sendable {

    // MARK: - 废片检测

    func detectWaste(image: UIImage) -> (isWaste: Bool, reason: WasteReason?) {
        guard let cgImage = image.cgImage else { return (false, nil) }

        if let reason = checkPureColor(cgImage) {
            return (true, reason)
        }

        if isBlurry(cgImage) {
            return (true, .blurry)
        }

        if isFingerBlocked(cgImage) {
            return (true, .fingerBlock)
        }

        return (false, nil)
    }

    // MARK: - 图像质量评分

    func qualityScore(for cgImage: CGImage) -> Float {
        let sharpness = laplacianVariance(cgImage)
        let sharpnessScore = min(Float(sharpness) / 500.0, 1.0)

        // 亮度均值评分 — 太暗或太亮扣分
        let brightness = averageBrightness(cgImage)
        let exposureScore: Float = {
            if brightness < 30 { return brightness / 30.0 }
            if brightness > 225 { return (255.0 - brightness) / 30.0 }
            return 1.0
        }()

        // 分辨率评分
        let pixels = Float(cgImage.width * cgImage.height)
        let resolutionScore = min(pixels / (3000.0 * 4000.0), 1.0)

        return sharpnessScore * 0.5 + exposureScore * 0.3 + resolutionScore * 0.2
    }

    // MARK: - 特征提取 (用于相似度比较)

    func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNGenerateImageFeaturePrintRequest()
        try? handler.perform([request])
        return request.results?.first
    }

    // MARK: - 手指遮挡检测

    func isFingerBlocked(_ cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        guard let pixelData = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return false }
        let bytesPerRow = cgImage.bytesPerRow
        let bpp = cgImage.bitsPerPixel / 8

        // 检测四个角落区域（各取 1/6 宽高的矩形）
        let cornerW = width / 6
        let cornerH = height / 6
        let corners: [(xStart: Int, yStart: Int)] = [
            (0, 0),
            (width - cornerW, 0),
            (0, height - cornerH),
            (width - cornerW, height - cornerH),
        ]

        var blockedCorners = 0
        for corner in corners {
            var warmPixels = 0
            var totalPixels = 0
            for y in stride(from: corner.yStart, to: corner.yStart + cornerH, by: max(1, cornerH / 14)) {
                for x in stride(from: corner.xStart, to: corner.xStart + cornerW, by: max(1, cornerW / 14)) {
                    let offset = y * bytesPerRow + x * bpp
                    let r = Float(ptr[offset])
                    let g = Float(ptr[offset + 1])
                    let b = Float(ptr[offset + 2])
                    totalPixels += 1
                    // 暖色：红色通道高，蓝色低，亮度适中（类似肤色）
                    if r > 120 && r > b + 30 && g > 60 && b < 160 {
                        warmPixels += 1
                    }
                }
            }
            if totalPixels > 0 && Float(warmPixels) / Float(totalPixels) > 0.7 {
                blockedCorners += 1
            }
        }
        return blockedCorners >= 2
    }

    // MARK: - Private

    private func checkPureColor(_ cgImage: CGImage) -> WasteReason? {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let context = CIContext()
        guard let data = context.createCGImage(ciImage, from: extent) else { return nil }

        let width = data.width
        let height = data.height
        guard let pixelData = data.dataProvider?.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return nil }

        let sampleStep = max(1, (width * height) / 1000)
        var brightnessValues: [Float] = []

        for i in stride(from: 0, to: width * height, by: sampleStep) {
            let offset = i * 4
            let r = Float(ptr[offset])
            let g = Float(ptr[offset + 1])
            let b = Float(ptr[offset + 2])
            brightnessValues.append((r + g + b) / 3.0)
        }

        let mean = brightnessValues.reduce(0, +) / Float(brightnessValues.count)
        let variance = brightnessValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(brightnessValues.count)
        let stdDev = sqrt(variance)

        if stdDev < AppConstants.Analysis.brightnessStdDevThreshold {
            return mean < 30 ? .pureBlack : (mean > 225 ? .pureWhite : nil)
        }
        return nil
    }

    private func isBlurry(_ cgImage: CGImage) -> Bool {
        laplacianVariance(cgImage) < 50.0
    }

    private func averageBrightness(_ cgImage: CGImage) -> Float {
        guard let pixelData = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return 128 }
        let total = cgImage.width * cgImage.height
        let step = max(1, total / 500)
        let bpp = cgImage.bitsPerPixel / 8
        var sum: Float = 0
        var count: Float = 0
        for i in stride(from: 0, to: total, by: step) {
            let offset = i * bpp
            sum += (Float(ptr[offset]) + Float(ptr[offset + 1]) + Float(ptr[offset + 2])) / 3.0
            count += 1
        }
        return count > 0 ? sum / count : 128
    }

    /// 缩小图像到固定尺寸后采样多点计算拉普拉斯方差
    private func laplacianVariance(_ cgImage: CGImage) -> Double {
        let targetSize = 256
        let ciImage = CIImage(cgImage: cgImage)
        let scale = Double(targetSize) / max(Double(cgImage.width), Double(cgImage.height))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let filter = CIFilter(name: "CIConvolution3X3") else { return 999 }
        let kernel: [CGFloat] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        filter.setValue(scaled, forKey: kCIInputImageKey)
        filter.setValue(CIVector(values: kernel, count: 9), forKey: "inputWeights")
        filter.setValue(0, forKey: "inputBias")

        guard let output = filter.outputImage else { return 999 }
        let context = CIContext()
        let extent = output.extent
        let w = Int(extent.width)
        let h = Int(extent.height)
        guard w > 0, h > 0 else { return 999 }

        guard let rendered = context.createCGImage(output, from: extent),
              let data = rendered.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 999 }

        let bpp = rendered.bitsPerPixel / 8
        let bytesPerRow = rendered.bytesPerRow
        // 采样多个点计算方差
        let sampleCount = min(500, w * h)
        let step = max(1, (w * h) / sampleCount)
        var values: [Double] = []
        for i in stride(from: 0, to: w * h, by: step) {
            let y = i / w
            let x = i % w
            let offset = y * bytesPerRow + x * bpp
            values.append(Double(ptr[offset]))
        }
        guard !values.isEmpty else { return 999 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance
    }
}
