import Foundation
import Photos

struct TrashedItem: Codable, Identifiable {
    let id: String
    let fileSize: Int64
    let creationDate: Date?
    let trashedDate: Date

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

@MainActor @Observable
final class TrashService {
    private(set) var trashedItems: [TrashedItem] = []

    var totalSize: Int64 {
        trashedItems.reduce(0) { $0 + $1.fileSize }
    }

    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private static let storageKey = "trashedScreenshotItems"

    init() {
        load()
    }

    func trash(_ items: [MediaItem]) {
        let now = Date()
        let existingIDs = Set(trashedItems.map(\.id))
        let newItems = items.compactMap { item -> TrashedItem? in
            guard !existingIDs.contains(item.id) else { return nil }
            return TrashedItem(
                id: item.id,
                fileSize: item.fileSize,
                creationDate: item.creationDate,
                trashedDate: now
            )
        }
        trashedItems.insert(contentsOf: newItems, at: 0)
        persist()
    }

    func restore(_ ids: Set<String>) {
        trashedItems.removeAll { ids.contains($0.id) }
        persist()
    }

    func permanentlyDelete(_ ids: Set<String>, photoLibrary: PhotoLibraryService) async {
        let assets = fetchAssets(for: ids)
        if !assets.isEmpty {
            try? await photoLibrary.deleteAssets(assets)
        }
        trashedItems.removeAll { ids.contains($0.id) }
        persist()
    }

    func permanentlyDeleteAll(photoLibrary: PhotoLibraryService) async {
        let ids = Set(trashedItems.map(\.id))
        await permanentlyDelete(ids, photoLibrary: photoLibrary)
    }

    func fetchAssets(for ids: Set<String>) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// 剔除系统相册中已不存在的条目（用户可能在 Photos.app 里直接永久删除）
    func reconcileWithLibrary() {
        guard !trashedItems.isEmpty else { return }
        let ids = Set(trashedItems.map(\.id))
        let validIDs = Set(fetchAssets(for: ids).map(\.localIdentifier))
        let removed = ids.subtracting(validIDs)
        guard !removed.isEmpty else { return }
        trashedItems.removeAll { removed.contains($0.id) }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let items = try? JSONDecoder().decode([TrashedItem].self, from: data) else { return }
        trashedItems = items
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(trashedItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
