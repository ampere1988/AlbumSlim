import Foundation
import UIKit

enum AppConstants {
    static let appName = String(localized: "闪图")

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
        static var presets: [(name: String, width: Int, height: Int)] {
            [
                (String(localized: "高质量"), 1920, 1080),
                (String(localized: "中质量"), 1280, 720),
                (String(localized: "省空间"), 640, 480),
            ]
        }
    }

    enum Shuffle {
        /// 高清图目标像素尺寸（屏幕 points × scale）
        @MainActor static var fullImageTargetSize: CGSize {
            let scale = UIScreen.main.scale
            let bounds = UIScreen.main.bounds.size
            return CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
        /// 预加载/占位用的 thumbnail 尺寸（本地缓存易命中、内存占用小）
        static let thumbnailSize = CGSize(width: 1200, height: 1200)
        /// 预加载窗口：前 1 + 后 2
        static let prefetchOffsets: [Int] = [-1, 1, 2]
        /// thumbnail LRU cache 容量（窗口 3 + 缓冲）
        static let thumbnailCacheCapacity = 12
        /// 全图 UIImage 内存缓存容量（当前 + 下一张 + 回滑上一张）
        static let fullImageCacheCapacity = 3
        /// 分享导出图的尺寸
        static let shareImageSize = CGSize(width: 1600, height: 1600)
    }
}
