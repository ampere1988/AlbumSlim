import SwiftUI

/// 视频列表行：缩略图带时长角标，体积作为右侧主指标。
struct VideoRow: View {
    let item: MediaItem
    let services: AppServiceContainer
    var isSelected: Bool = false

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: Spacing.m) {
            thumbnailView

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(item.creationDate?.formatted(date: .abbreviated, time: .shortened)
                     ?? String(localized: "未知日期"))
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                MetaChip(text: item.resolution, systemImage: "aspectratio")
            }

            Spacer(minLength: 0)

            Text(item.fileSizeText)
                .font(AppFont.metricSmall)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, Spacing.xs)
        .task {
            thumbnail = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: 240, height: 160)
            )
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.surfaceSunken)
                    .overlay {
                        Image(systemName: "video.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.video)
                    }
            }
        }
        .frame(width: 86, height: 58)
        .clipShape(.rect(cornerRadius: Radius.thumb))
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.thumb)
                .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                              lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textOnAccent)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.accent))
                    .padding(Spacing.xs)
            }
        }
        .motion(Motion.standard, value: isSelected)
    }

    private var durationBadge: some View {
        Text(durationText)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(Spacing.xs)
    }

    private var durationText: String {
        let total = Int(item.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
