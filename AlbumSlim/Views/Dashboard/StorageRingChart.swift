import SwiftUI
import Charts

struct StorageRingChart: View {
    let stats: StorageStats

    private var hasData: Bool {
        stats.totalSize > 0
    }

    private var colorMap: [String: Color] {
        ["视频": .blue, "照片": .green, "截图": .orange]
    }

    var body: some View {
        VStack(spacing: 12) {
            if hasData {
                Chart(stats.categories, id: \.name) { category in
                    SectorMark(
                        angle: .value("大小", category.size),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(colorMap[category.name] ?? .gray)
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale([
                    "视频": Color.blue,
                    "照片": Color.green,
                    "截图": Color.orange,
                ])
                .chartLegend(position: .bottom)
            } else {
                Chart {
                    SectorMark(
                        angle: .value("占位", 1),
                        innerRadius: .ratio(0.6)
                    )
                    .foregroundStyle(.quaternary)
                }
                .chartLegend(.hidden)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("暂无数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
