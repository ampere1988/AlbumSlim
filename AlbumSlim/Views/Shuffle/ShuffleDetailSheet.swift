import SwiftUI
import Photos
import CoreLocation

/// 查看详情 sheet：分辨率、拍摄日期、文件大小、位置等元信息
struct ShuffleDetailSheet: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    let item: ShuffleItem

    @State private var fileSize: Int64 = 0
    @State private var placeName: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    row("类型", kindLabel)
                    row("分辨率", "\(item.asset.pixelWidth) × \(item.asset.pixelHeight)")
                    row("文件大小", fileSize > 0 ? fileSize.formattedFileSize : "—")
                    if item.kind == .video {
                        row("时长", formatDuration(item.asset.duration))
                    }
                }

                Section("时间") {
                    if let creation = item.asset.creationDate {
                        row("拍摄时间", creation.formatted(date: .long, time: .shortened))
                    }
                    if let modification = item.asset.modificationDate {
                        row("修改时间", modification.formatted(date: .long, time: .shortened))
                    }
                }

                if let location = item.asset.location {
                    Section("位置") {
                        if let placeName {
                            row("地点", placeName)
                        }
                        row("坐标", String(format: "%.5f, %.5f",
                                          location.coordinate.latitude,
                                          location.coordinate.longitude))
                        if location.altitude != 0 {
                            row("海拔", String(format: "%.0f m", location.altitude))
                        }
                    }
                }

                Section("标识") {
                    row("identifier", item.asset.localIdentifier)
                }
            }
            .navigationTitle("详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            placeName = await services.locationName.placeName(for: item.asset.location)
            fileSize = services.photoLibrary.fileSize(for: item.asset)
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .photo: return "照片"
        case .livePhoto: return "Live Photo"
        case .video: return "视频"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
