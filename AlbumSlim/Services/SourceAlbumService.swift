import Foundation
import Photos

/// 会在系统相册里创建自有相册的第三方 App。
/// 匹配用全等（trim + 小写），不用 contains——"微信读书" 不应被算作 "微信"。
struct SourceApp: Identifiable, Sendable {
    let id: String
    let displayName: String
    let iconName: String
    let aliases: [String]

    static let known: [SourceApp] = [
        SourceApp(id: "wechat", displayName: String(localized: "微信"),
                  iconName: "message.fill", aliases: ["微信", "wechat"]),
        SourceApp(id: "qq", displayName: "QQ",
                  iconName: "bubble.left.fill", aliases: ["qq", "qq空间", "qzone"]),
        SourceApp(id: "weibo", displayName: String(localized: "微博"),
                  iconName: "at", aliases: ["微博", "weibo", "sina weibo"]),
        SourceApp(id: "xiaohongshu", displayName: String(localized: "小红书"),
                  iconName: "book.fill", aliases: ["小红书", "xiaohongshu", "red"]),
        SourceApp(id: "douyin", displayName: String(localized: "抖音"),
                  iconName: "music.note", aliases: ["抖音", "douyin"]),
        SourceApp(id: "whatsapp", displayName: "WhatsApp",
                  iconName: "phone.fill", aliases: ["whatsapp", "whatsapp images", "whatsapp video"]),
        SourceApp(id: "telegram", displayName: "Telegram",
                  iconName: "paperplane.fill", aliases: ["telegram"]),
        SourceApp(id: "instagram", displayName: "Instagram",
                  iconName: "camera.fill", aliases: ["instagram"]),
        SourceApp(id: "snapchat", displayName: "Snapchat",
                  iconName: "bolt.fill", aliases: ["snapchat"]),
        SourceApp(id: "messenger", displayName: "Messenger",
                  iconName: "bubble.left.and.bubble.right.fill", aliases: ["messenger", "facebook messenger"]),
        SourceApp(id: "facebook", displayName: "Facebook",
                  iconName: "person.2.fill", aliases: ["facebook"]),
        SourceApp(id: "line", displayName: "LINE",
                  iconName: "bubble.right.fill", aliases: ["line"]),
        SourceApp(id: "twitter", displayName: "X",
                  iconName: "xmark", aliases: ["twitter", "x"]),
    ]

    static func match(albumTitle: String) -> SourceApp? {
        let normalized = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return known.first { $0.aliases.contains(normalized) }
    }
}

struct SourceAlbum: Identifiable, Sendable {
    let id: String
    let app: SourceApp
    let title: String
    let assetIDs: [String]
    let totalSize: Int64

    var count: Int { assetIDs.count }
    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

@MainActor @Observable
final class SourceAlbumService {
    private(set) var albums: [SourceAlbum] = []
    private(set) var isLoading = false

    /// 扫描系统里的用户相册，挑出由已知第三方 App 创建的那些。
    /// 第三方 App 通过 `PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:)`
    /// 建的相册都是 `.albumRegular`。
    func loadAlbums(photoLibrary: PhotoLibraryService) async {
        isLoading = true
        defer { isLoading = false }

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )

        var found: [SourceAlbum] = []
        collections.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle,
                  let app = SourceApp.match(albumTitle: title) else { return }

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assetsResult = PHAsset.fetchAssets(in: collection, options: options)
            guard assetsResult.count > 0 else { return }

            var ids: [String] = []
            var size: Int64 = 0
            ids.reserveCapacity(assetsResult.count)
            assetsResult.enumerateObjects { asset, _, _ in
                ids.append(asset.localIdentifier)
                size += photoLibrary.fileSize(for: asset)
            }

            found.append(SourceAlbum(
                id: collection.localIdentifier,
                app: app,
                title: title,
                assetIDs: ids,
                totalSize: size
            ))
        }

        // 占空间大的排前面
        albums = found.sorted { $0.totalSize > $1.totalSize }
    }
}
