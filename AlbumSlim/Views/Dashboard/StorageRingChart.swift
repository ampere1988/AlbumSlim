import SwiftUI
import Charts

/// 存储占用环形图：中心放总容量大字，图例换成彩色胶囊。
///
/// 系统默认图例是一排小色块 + 灰字，信息密度低又抢不到注意力；
/// 这里把"分类 + 体积"合进一个胶囊，一眼能读完。
struct StorageRingChart: View {
    let stats: StorageStats

    private var hasData: Bool { stats.totalSize > 0 }

    private var colorMap: [String: Color] {
        [
            String(localized: "视频"): Theme.video,
            String(localized: "照片"): Theme.photo,
            String(localized: "截图"): Theme.screenshot,
        ]
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            if hasData {
                ring
                legend
            } else {
                placeholder
            }
        }
    }

    private var ring: some View {
        Chart(stats.categories, id: \.name) { category in
            SectorMark(
                angle: .value("大小", category.size),
                innerRadius: .ratio(0.74),
                angularInset: 2
            )
            .foregroundStyle(colorMap[category.name] ?? Theme.textTertiary)
            .cornerRadius(6)
        }
        .chartLegend(.hidden)
        .overlay { centerLabel }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("相册总占用")
        .accessibilityValue(stats.totalSize.formattedFileSize)
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(stats.totalSize.formattedFileSize)
                .font(AppFont.metric)
                .foregroundStyle(Theme.textPrimary)
            Text("总占用")
                .font(AppFont.label)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var legend: some View {
        HStack(spacing: Spacing.s) {
            ForEach(stats.categories, id: \.name) { category in
                MetaChip(
                    text: "\(category.name) \(category.size.formattedFileSize)",
                    tint: colorMap[category.name] ?? Theme.textTertiary
                )
            }
        }
    }

    private var placeholder: some View {
        Chart {
            SectorMark(angle: .value("占位", 1), innerRadius: .ratio(0.74))
                .foregroundStyle(Theme.surfaceSunken)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: Spacing.s) {
                Image(systemName: "photo.badge.plus")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
                Text("暂无数据")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
