import SwiftUI

/// 视频列表行：缩略图带时长角标，体积作为右侧主指标。
struct VideoRow: View {
    let item: MediaItem
    let services: AppServiceContainer
    var isEditing: Bool = false
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
                Text(item.fileSizeText)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textPrimary)
                Text(item.resolution)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s)
        .task {
            thumbnail = await services.photoLibrary.thumbnail(
                for: item.asset,
                size: CGSize(width: 360, height: 240)
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
        .frame(width: 132, height: 88)
        .clipShape(.rect(cornerRadius: Radius.thumb))
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.thumb)
                .strokeBorder(isSelected ? Theme.accent : Theme.hairline,
                              lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .topLeading) {
            if isEditing {
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isSelected ? Theme.accent : .black.opacity(0.38)))
                    .overlay {
                        if !isSelected {
                            Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)
                        }
                    }
                    .padding(Spacing.xs)
            }
        }
        .motion(Motion.standard, value: isSelected)
    }

    private var durationBadge: some View {
        Text(durationText)
            .font(AppFont.label.monospacedDigit())
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
