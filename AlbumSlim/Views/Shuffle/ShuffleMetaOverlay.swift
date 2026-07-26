import SwiftUI
import CoreLocation

/// 左下角元信息 overlay：位置（城市名）+ 日期 · 文件大小
///
/// 日期和体积改用玻璃胶囊承载：纯白字加投影在浅色照片上仍然会糊，
/// 胶囊底能保证任何画面下都读得清，同时不遮挡照片主体。
struct ShuffleMetaOverlay: View {
    @Environment(AppServiceContainer.self) private var services
    let item: ShuffleItem

    @State private var placeName: String?
    @State private var fileSize: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let placeName, !placeName.isEmpty {
                Label(placeName, systemImage: "mappin.and.ellipse")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
            }

            HStack(spacing: Spacing.s) {
                if let date = item.asset.creationDate {
                    glassPill {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                if fileSize > 0 {
                    glassPill {
                        Text(fileSize.formattedFileSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: item.id) {
            placeName = await services.locationName.placeName(for: item.asset.location)
            fileSize = services.photoLibrary.fileSize(for: item.asset)
        }
    }

    private func glassPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(AppFont.label)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(.black.opacity(0.35)))
            .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
    }
}
