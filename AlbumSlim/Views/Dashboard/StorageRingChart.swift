import SwiftUI
import Charts

struct StorageRingChart: View {
    let stats: StorageStats

    var body: some View {
        VStack(spacing: 12) {
            Chart(stats.categories, id: \.name) { category in
                SectorMark(
                    angle: .value("大小", category.size),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("类型", category.name))
                .cornerRadius(4)
            }
            .chartLegend(position: .bottom)
            .overlay {
                VStack(spacing: 4) {
                    Text("总占用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stats.totalSize.formattedFileSize)
                        .font(.title2.bold())
                }
            }
        }
    }
}
