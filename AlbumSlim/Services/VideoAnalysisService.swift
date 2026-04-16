import Foundation

@MainActor @Observable
final class VideoAnalysisService {

    struct VideoSuggestion: Identifiable {
        let id: String
        let item: MediaItem
        let type: SuggestionType
        let reason: String
        let estimatedSaving: Int64

        enum SuggestionType: String, CaseIterable {
            case tooLong = "超长视频"
            case lowQuality = "低质量"
            case largeFile = "大文件"
            case possibleDuplicate = "疑似重复"

            var icon: String {
                switch self {
                case .tooLong: "clock.arrow.circlepath"
                case .lowQuality: "exclamationmark.triangle"
                case .largeFile: "externaldrive.fill"
                case .possibleDuplicate: "doc.on.doc"
                }
            }

            var color: String {
                switch self {
                case .tooLong: "orange"
                case .lowQuality: "red"
                case .largeFile: "purple"
                case .possibleDuplicate: "blue"
                }
            }

            var localizedName: String {
                switch self {
                case .tooLong:           return String(localized: "超长视频")
                case .lowQuality:        return String(localized: "低质量")
                case .largeFile:         return String(localized: "大文件")
                case .possibleDuplicate: return String(localized: "疑似重复")
                }
            }
        }
    }

    private(set) var isAnalyzing = false

    func analyzeVideos(_ videos: [MediaItem]) async -> [VideoSuggestion] {
        isAnalyzing = true
        defer { isAnalyzing = false }

        var suggestions: [VideoSuggestion] = []
        var usedIDs: Set<String> = []

        for video in videos {
            if video.duration > 300 {
                suggestions.append(VideoSuggestion(
                    id: "\(video.id)_tooLong",
                    item: video,
                    type: .tooLong,
                    reason: "时长超过5分钟，建议压缩或裁剪",
                    estimatedSaving: Int64(Double(video.fileSize) * 0.5)
                ))
                usedIDs.insert(video.id)
            }

            if video.pixelWidth < 1280 || (video.duration < 3 && video.fileSize < 1_000_000) {
                suggestions.append(VideoSuggestion(
                    id: "\(video.id)_lowQuality",
                    item: video,
                    type: .lowQuality,
                    reason: video.pixelWidth < 1280 ? "分辨率低于720p" : "极短且体积小",
                    estimatedSaving: video.fileSize
                ))
                usedIDs.insert(video.id)
            }

            if video.fileSize > 100_000_000 {
                suggestions.append(VideoSuggestion(
                    id: "\(video.id)_largeFile",
                    item: video,
                    type: .largeFile,
                    reason: "文件超过100MB，建议压缩",
                    estimatedSaving: Int64(Double(video.fileSize) * 0.5)
                ))
                usedIDs.insert(video.id)
            }
        }

        // 疑似重复：creationDate 差 < 60s 且 duration 差 < 5s
        let sorted = videos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        for i in 0..<sorted.count {
            guard i + 1 < sorted.count else { break }
            let a = sorted[i]
            let b = sorted[i + 1]
            guard let dateA = a.creationDate, let dateB = b.creationDate else { continue }
            if abs(dateA.timeIntervalSince(dateB)) < 60 && abs(a.duration - b.duration) < 5 {
                let smaller = a.fileSize <= b.fileSize ? a : b
                suggestions.append(VideoSuggestion(
                    id: "\(a.id)_\(b.id)_dup",
                    item: smaller,
                    type: .possibleDuplicate,
                    reason: "与相邻视频时间和时长相近",
                    estimatedSaving: smaller.fileSize
                ))
            }
        }

        return suggestions
    }
}
