import Foundation
import Photos

struct MediaItem: Identifiable {
    let id: String // PHAsset.localIdentifier
    let asset: PHAsset
    let fileSize: Int64
    let creationDate: Date?

    var mediaType: PHAssetMediaType { asset.mediaType }
    var duration: TimeInterval { asset.duration }
    var pixelWidth: Int { asset.pixelWidth }
    var pixelHeight: Int { asset.pixelHeight }
    var isBurst: Bool { asset.burstIdentifier != nil }
    var isScreenshot: Bool { asset.mediaSubtypes.contains(.photoScreenshot) }
    var isLivePhoto: Bool { asset.mediaSubtypes.contains(.photoLive) }

    var fileSizeText: String { fileSize.formattedFileSize }
    var resolution: String { "\(pixelWidth)×\(pixelHeight)" }
}
