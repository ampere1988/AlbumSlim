import SwiftUI

struct VideoCompressView: View {
    @Environment(AppServiceContainer.self) private var services
    let item: MediaItem
    @State private var selectedQuality: CompressionQuality = .high
    @State private var isCompressing = false
    @State private var showResult = false
    @State private var error: String?

    var body: some View {
        List {
            Section("视频信息") {
                LabeledContent("分辨率", value: item.resolution)
                LabeledContent("时长", value: formatDuration(item.duration))
                LabeledContent("原始大小", value: item.fileSizeText)
            }

            Section("压缩质量") {
                Picker("质量", selection: $selectedQuality) {
                    ForEach(CompressionQuality.allCases, id: \.self) { quality in
                        VStack(alignment: .leading) {
                            Text(quality.rawValue)
                            Text("预估节省 \(quality.estimatedSavingsPercent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(quality)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                let estimated = services.videoCompression.estimateCompressedSize(
                    asset: item.asset, quality: selectedQuality
                )
                LabeledContent("预估压缩后", value: estimated.formattedFileSize)
                LabeledContent("预估节省", value: (item.fileSize - estimated).formattedFileSize)
            }

            Section {
                if isCompressing {
                    ProgressView(value: services.videoCompression.progress) {
                        Text("压缩中...")
                    }
                } else {
                    Button("开始压缩") {
                        Task { await compress() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("视频压缩")
        .alert("压缩失败", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定") {}
        } message: {
            Text(error ?? "")
        }
        .alert("压缩完成", isPresented: $showResult) {
            Button("好的") {}
        }
    }

    private func compress() async {
        isCompressing = true
        defer { isCompressing = false }
        do {
            _ = try await services.videoCompression.compressVideo(
                asset: item.asset, quality: selectedQuality
            )
            showResult = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
