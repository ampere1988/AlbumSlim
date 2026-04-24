import SwiftUI
import Photos

struct MediaGridView: View {
    let items: [MediaItem]
    let bestItemID: String?
    let services: AppServiceContainer
    var isSelectable: Bool = false
    var selection: Binding<Set<String>>?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(items) { item in
                ThumbnailCell(
                    item: item,
                    isBest: item.id == bestItemID,
                    isSelectable: isSelectable,
                    isSelected: selection?.wrappedValue.contains(item.id) ?? false,
                    services: services
                ) {
                    if let selection {
                        if selection.wrappedValue.contains(item.id) {
                            selection.wrappedValue.remove(item.id)
                        } else {
                            selection.wrappedValue.insert(item.id)
                        }
                    }
                }
            }
        }
    }
}

private struct ThumbnailCell: View {
    let item: MediaItem
    let isBest: Bool
    let isSelectable: Bool
    let isSelected: Bool
    let services: AppServiceContainer
    var onTap: () -> Void
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

            // 选中覆盖层
            if isSelectable && isSelected {
                Rectangle()
                    .fill(.blue.opacity(0.3))
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .blue)
                    .padding(6)
            }

            if isBest {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .padding(4)
                    .background(.yellow, in: Circle())
                    .padding(4)
            }

            VStack {
                Spacer()
                Text(item.fileSizeText)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
        .overlay {
            if isBest {
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .stroke(.yellow, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectable { onTap() }
        }
        .task {
            image = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: 200, height: 200)
            )
        }
    }
}
