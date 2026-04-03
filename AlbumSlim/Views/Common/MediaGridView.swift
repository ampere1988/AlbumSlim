import SwiftUI
import Photos

struct MediaGridView: View {
    let items: [MediaItem]
    let bestItemID: String?
    let services: AppServiceContainer

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(items) { item in
                ThumbnailCell(
                    item: item,
                    isBest: item.id == bestItemID,
                    services: services
                )
            }
        }
    }
}

private struct ThumbnailCell: View {
    let item: MediaItem
    let isBest: Bool
    let services: AppServiceContainer
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fill)
                    .overlay { ProgressView() }
            }

            if isBest {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .padding(4)
                    .background(.yellow, in: Circle())
                    .padding(4)
            }

            // 文件大小标签
            VStack {
                Spacer()
                Text(item.fileSizeText)
                    .font(.system(size: 10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isBest {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.yellow, lineWidth: 2)
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: 200, height: 200)
            )
        }
    }
}
