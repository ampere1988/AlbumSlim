import Foundation
import Vision
import UIKit
import CoreImage

@MainActor
final class AIAnalysisEngine {

    // MARK: - 废片检测

    func detectWaste(image: UIImage) -> (isWaste: Bool, reason: WasteReason?) {
        guard let cgImage = image.cgImage else { return (false, nil) }

        // 检测纯黑/纯白
        if let reason = checkPureColor(cgImage) {
            return (true, reason)
        }

        // 检测模糊
        if isBlurry(cgImage) {
            return (true, .blurry)
        }

        return (false, nil)
    }

    // MARK: - 图像质量评分

    func qualityScore(for cgImage: CGImage) -> Float {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNClassifyImageRequest()
        try? handler.perform([request])
        // 基于分辨率和清晰度的简单评分
        let sharpness = laplacianVariance(cgImage)
        return min(Float(sharpness) / 500.0, 1.0)
    }

    // MARK: - 特征提取 (用于相似度比较)

    func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNGenerateImageFeaturePrintRequest()
        try? handler.perform([request])
        return request.results?.first
    }

    // MARK: - Private

    private func checkPureColor(_ cgImage: CGImage) -> WasteReason? {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        // 采样中心区域计算平均亮度和标准差
        let context = CIContext()
        guard let data = context.createCGImage(ciImage, from: extent) else { return nil }

        let width = data.width
        let height = data.height
        guard let pixelData = data.dataProvider?.data,
              let ptr = CFDataGetBytePtr(pixelData) else { return nil }

        let sampleStep = max(1, (width * height) / 1000) // 采样约1000个像素
        var brightnessValues: [Float] = []

        for i in stride(from: 0, to: width * height, by: sampleStep) {
            let offset = i * 4 // RGBA
            let r = Float(ptr[offset])
            let g = Float(ptr[offset + 1])
            let b = Float(ptr[offset + 2])
            let brightness = (r + g + b) / 3.0
            brightnessValues.append(brightness)
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
        let variance = laplacianVariance(cgImage)
        return variance < 50.0
    }

    private func laplacianVariance(_ cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIConvolution3X3") else { return 999 }
        // 拉普拉斯核
        let kernel: [CGFloat] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(values: kernel, count: 9), forKey: "inputWeights")
        filter.setValue(0, forKey: "inputBias")

        guard let output = filter.outputImage else { return 999 }
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        // 计算平均绝对值作为清晰度指标
        context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: extent, format: .RGBA8, colorSpace: nil)
        return Double(bitmap[0])
    }
}
