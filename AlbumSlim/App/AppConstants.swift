import Foundation

enum AppConstants {
    static let appName = "相册瘦身"

    enum Similarity {
        static let highThreshold: Float = 0.85
        static let suspectThreshold: Float = 0.70
        static let timeWindowSeconds: TimeInterval = 300 // 5分钟
    }

    enum Analysis {
        static let batchSize = 100
        static let maxConcurrency = 4
        static let brightnessStdDevThreshold: Float = 5.0
    }

    enum Compression {
        static let presets: [(name: String, width: Int, height: Int)] = [
            ("高质量", 1920, 1080),
            ("中质量", 1280, 720),
            ("省空间", 640, 480),
        ]
    }
}
