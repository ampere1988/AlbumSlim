import SwiftUI
import CoreLocation

/// 左下角元信息 overlay：位置（城市名）+ 日期 · 文件大小
struct ShuffleMetaOverlay: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem

    @State private var placeName: String?
    @State private var fileSize: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let placeName, !placeName.isEmpty {
                Text(placeName)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            }
            HStack(spacing: 8) {
                if let date = item.asset.creationDate {
                    Text(date, format: .dateTime.year().month().day())
                }
                if fileSize > 0 {
                    Text("·")
                    Text(fileSize.formattedFileSize)
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: item.id) {
            placeName = await services.locationName.placeName(for: item.asset.location)
            fileSize = services.photoLibrary.fileSize(for: item.asset)
        }
    }
}
