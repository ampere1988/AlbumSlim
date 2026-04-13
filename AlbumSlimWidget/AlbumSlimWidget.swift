import WidgetKit
import SwiftUI

struct StorageEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStorageStats?
}

struct StorageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry {
        StorageEntry(date: .now, stats: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        let stats = WidgetStorageStats.loadFromAppGroup()
        completion(StorageEntry(date: .now, stats: stats))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let stats = WidgetStorageStats.loadFromAppGroup()
        let entry = StorageEntry(date: .now, stats: stats)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 4, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Ring Chart

struct RingChartView: View {
    let segments: [(color: Color, fraction: Double)]
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - lineWidth / 2
            var startAngle = Angle.degrees(-90)

            for segment in segments {
                guard segment.fraction > 0 else { continue }
                let endAngle = startAngle + Angle.degrees(360 * segment.fraction)
                let path = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: startAngle, endAngle: endAngle, clockwise: false)
                }
                context.stroke(path, with: .color(segment.color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                startAngle = endAngle
            }
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let stats: WidgetStorageStats?

    var body: some View {
        if let stats, !stats.isEmpty {
            VStack(spacing: 6) {
                ZStack {
                    RingChartView(segments: ringSegments(stats), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    VStack(spacing: 0) {
                        Text(stats.totalSize.formattedFileSize)
                            .font(.system(size: 11, weight: .bold))
                            .minimumScaleFactor(0.6)
                    }
                }
                if stats.estimatedSavable > 0 {
                    Text("可释放 \(stats.estimatedSavable.formattedFileSize)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("打开 App 扫描")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let stats: WidgetStorageStats?

    var body: some View {
        if let stats, !stats.isEmpty {
            HStack(spacing: 16) {
                ZStack {
                    RingChartView(segments: ringSegments(stats), lineWidth: 10)
                        .frame(width: 80, height: 80)
                    VStack(spacing: 0) {
                        Text(stats.totalSize.formattedFileSize)
                            .font(.system(size: 13, weight: .bold))
                            .minimumScaleFactor(0.6)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    CategoryRow(color: .blue, name: "视频", size: stats.videoSize, count: stats.totalVideoCount)
                    CategoryRow(color: .green, name: "照片", size: stats.photoSize, count: stats.totalPhotoCount)
                    CategoryRow(color: .orange, name: "截图", size: stats.screenshotSize, count: stats.totalScreenshotCount)

                    if stats.estimatedSavable > 0 {
                        Divider()
                        Text("可释放 \(stats.estimatedSavable.formattedFileSize)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("打开闪图扫描后\n即可在此查看统计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct CategoryRow: View {
    let color: Color
    let name: String
    let size: Int64
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)个")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(size.formattedFileSize)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

// MARK: - Helpers

private func ringSegments(_ stats: WidgetStorageStats) -> [(color: Color, fraction: Double)] {
    let total = Double(stats.totalSize)
    guard total > 0 else { return [] }
    return [
        (.blue, Double(stats.videoSize) / total),
        (.green, Double(stats.photoSize) / total),
        (.orange, Double(stats.screenshotSize) / total),
    ]
}

// MARK: - Widget Definition

struct AlbumSlimWidget: Widget {
    let kind = "AlbumSlimWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StorageTimelineProvider()) { entry in
            AlbumSlimWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("闪图")
        .description("查看相册存储空间使用情况")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AlbumSlimWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StorageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(stats: entry.stats)
        case .systemMedium:
            MediumWidgetView(stats: entry.stats)
        default:
            SmallWidgetView(stats: entry.stats)
        }
    }
}
