import Foundation
import Photos

enum TrashSource: String, Codable, CaseIterable {
    case similar
    case waste
    case burst
    case largePhoto
    case video
    case screenshot
    case shuffle
    case other

    var label: String {
        switch self {
        case .similar:    return "相似照片"
        case .waste:      return "废片"
        case .burst:      return "连拍"
        case .largePhoto: return "超大照片"
        case .video:      return "视频"
        case .screenshot: return "截图"
        case .shuffle:    return "浏览"
        case .other:      return "其他"
        }
    }
}

enum TrashedMediaType: String, Codable {
    case photo
    case video
    case livePhoto
    case screenshot
}

enum TrashChangeKind {
    case none
    case insert
    case restore
    case permanentDelete
}

struct TrashedItem: Codable, Identifiable {
    let id: String
    let fileSize: Int64
    let creationDate: Date?
    let trashedDate: Date
    let sourceModule: TrashSource
    let mediaType: TrashedMediaType

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

@MainActor @Observable
final class TrashService {
    private(set) var trashedItems: [TrashedItem] = []
    private(set) var lastChangeKind: TrashChangeKind = .none

    var totalSize: Int64 {
        trashedItems.reduce(0) { $0 + $1.fileSize }
    }

    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// 当前所有被软删除的 asset localIdentifier 集合，供各模块过滤使用
    var trashedAssetIDs: Set<String> {
        Set(trashedItems.map(\.id))
    }

    private static let storageKeyV2 = "trashedItems_v2"
    private static let legacyKey = "trashedScreenshotItems"
    private static let migrationFlag = "trashItemsMigrated_v2"

    init() {
        migrateLegacyIfNeeded()
        load()
    }

    // MARK: - 软删除

    /// 通用入口：传入 PHAsset 列表 + 来源模块 + 媒体类型
    func moveToTrash(assets: [PHAsset], source: TrashSource, mediaType: TrashedMediaType) {
        let now = Date()
        let existingIDs = trashedAssetIDs
        let newItems: [TrashedItem] = assets.compactMap { asset in
            guard !existingIDs.contains(asset.localIdentifier) else { return nil }
            let bytes = asset.estimatedByteSize
            return TrashedItem(
                id: asset.localIdentifier,
                fileSize: bytes,
                creationDate: asset.creationDate,
                trashedDate: now,
                sourceModule: source,
                mediaType: mediaType
            )
        }
        guard !newItems.isEmpty else { return }
        trashedItems.insert(contentsOf: newItems, at: 0)
        lastChangeKind = .insert
        persist()
    }

    // MARK: - 恢复 / 永久删除

    func restore(_ ids: Set<String>) {
        trashedItems.removeAll { ids.contains($0.id) }
        lastChangeKind = .restore
        persist()
    }

    func permanentlyDelete(_ ids: Set<String>, photoLibrary: PhotoLibraryService) async throws {
        let assets = fetchAssets(for: ids)
        if !assets.isEmpty {
            try await photoLibrary.deleteAssets(assets)
        }
        trashedItems.removeAll { ids.contains($0.id) }
        lastChangeKind = .permanentDelete
        persist()
    }

    func permanentlyDeleteAll(photoLibrary: PhotoLibraryService) async throws {
        try await permanentlyDelete(trashedAssetIDs, photoLibrary: photoLibrary)
    }

    // MARK: - 查询

    func contains(_ assetID: String) -> Bool {
        trashedItems.contains { $0.id == assetID }
    }

    func fetchAssets(for ids: Set<String>) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // MARK: - 同步

    /// 剔除系统相册中已不存在的条目
    func reconcileWithLibrary() {
        guard !trashedItems.isEmpty else { return }
        let ids = trashedAssetIDs
        let validIDs = Set(fetchAssets(for: ids).map(\.localIdentifier))
        let removed = ids.subtracting(validIDs)
        guard !removed.isEmpty else { return }
        trashedItems.removeAll { removed.contains($0.id) }
        persist()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKeyV2),
              let items = try? JSONDecoder().decode([TrashedItem].self, from: data) else { return }
        trashedItems = items
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(trashedItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKeyV2)
    }

    // MARK: - 旧数据迁移

    private func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationFlag) else { return }

        let markMigrated = {
            defaults.set(true, forKey: Self.migrationFlag)
            defaults.removeObject(forKey: Self.legacyKey)
        }

        guard let data = defaults.data(forKey: Self.legacyKey) else {
            markMigrated()
            return
        }

        struct LegacyItem: Codable {
            let id: String
            let fileSize: Int64
            let creationDate: Date?
            let trashedDate: Date
        }
        guard let legacy = try? JSONDecoder().decode([LegacyItem].self, from: data) else {
            // 损坏数据无法恢复，标记完成不再重试
            markMigrated()
            return
        }

        if legacy.isEmpty {
            markMigrated()
            return
        }

        let migrated = legacy.map { item in
            TrashedItem(
                id: item.id,
                fileSize: item.fileSize,
                creationDate: item.creationDate,
                trashedDate: item.trashedDate,
                sourceModule: .screenshot,
                mediaType: .screenshot
            )
        }

        guard let encoded = try? JSONEncoder().encode(migrated) else {
            // encode 失败：不清理 legacy key、不设 flag，下次启动重试
            return
        }
        defaults.set(encoded, forKey: Self.storageKeyV2)
        markMigrated()
    }
}

// MARK: - PHAsset 估算字节数

private extension PHAsset {
    var estimatedByteSize: Int64 {
        let resources = PHAssetResource.assetResources(for: self)
        for r in resources {
            if let n = r.value(forKey: "fileSize") as? NSNumber {
                return n.int64Value
            }
        }
        return 0
    }
}
