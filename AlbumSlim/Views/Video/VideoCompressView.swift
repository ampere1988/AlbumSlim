import SwiftUI
import Photos
import AVKit

struct VideoCompressView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    @State private var selectedQuality: CompressionQuality = .high
    @State private var isCompressing = false
    @State private var compressedURL: URL?
    @State private var compressedSize: Int64?
    @State private var error: String?
    @State private var thumbnail: UIImage?
    @State private var player: AVPlayer?
    @State private var showPaywall = false

    private var isCompleted: Bool { compressedSize != nil }

    var body: some View {
        List {
            // 视频播放预览
            Section {
                Group {
                    if let player {
                        VideoPlayer(player: player)
                            .aspectRatio(item.asset.pixelWidth > 0 ? CGFloat(item.asset.pixelWidth) / CGFloat(item.asset.pixelHeight) : 16/9, contentMode: .fit)
                    } else if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                    } else {
                        ProgressView()
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section("视频信息") {
                LabeledContent("分辨率", value: item.resolution)
                LabeledContent("时长", value: formatDuration(item.duration))
                LabeledContent("原始大小", value: item.fileSizeText)
            }

            if !isCompressing && !isCompleted {
                Section("压缩质量") {
                    Picker("质量", selection: $selectedQuality) {
                        ForEach(CompressionQuality.allCases, id: \.self) { quality in
                            VStack(alignment: .leading) {
                                Text(quality.localizedName)
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

                Section("预估结果") {
                    let estimated = services.videoCompression.estimateCompressedSize(
                        asset: item.asset, quality: selectedQuality
                    )
                    let saved = item.fileSize - estimated
                    let percent = item.fileSize > 0 ? Int(Double(saved) / Double(item.fileSize) * 100) : 0
                    LabeledContent("压缩后大小", value: estimated.formattedFileSize)
                    LabeledContent("预估节省", value: "\(saved.formattedFileSize)（\(percent)%）")
                }

                Section {
                    Button(role: .destructive) {
                        if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                            services.trash.moveToTrash(assets: [item.asset], source: .video, mediaType: .video)
                            Haptics.moveToTrash()
                            services.toast.movedToTrash(1)
                            dismiss()
                        } else {
                            Haptics.proGate()
                            showPaywall = true
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("移到垃圾桶", systemImage: AppIcons.trash)
                            Spacer()
                        }
                    }
                }
            }

            if isCompressing {
                Section {
                    ProgressLoadingState(phase: AppStrings.compressing, progress: services.videoCompression.progress)
                }
            }

            if let compressedSize {
                Section("压缩结果") {
                    let saved = item.fileSize - compressedSize
                    let percent = item.fileSize > 0 ? Int(Double(saved) / Double(item.fileSize) * 100) : 0
                    LabeledContent("原始大小", value: item.fileSizeText)
                    LabeledContent("压缩后", value: compressedSize.formattedFileSize)
                    LabeledContent("实际节省", value: "\(saved.formattedFileSize)（\(percent)%）")
                }

                Section {
                    Button("完成") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .bold()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isCompressing && !isCompleted {
                ActionBar {
                    Button {
                        if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                            Task { await compressAndSaveNew() }
                        } else {
                            Haptics.proGate()
                            showPaywall = true
                        }
                    } label: {
                        Text("压缩保存为新视频")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryActionStyle()

                    Button {
                        if ProFeatureGate.canClean(isPro: services.subscription.isPro) {
                            Task { await compressAndReplace() }
                        } else {
                            Haptics.proGate()
                            showPaywall = true
                        }
                    } label: {
                        Text("压缩并替换原视频")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionStyle()
                }
            }
        }
        .navigationTitle("视频压缩")
        .task {
            thumbnail = await services.photoLibrary.thumbnail(
                for: item.asset, size: CGSize(width: 600, height: 400)
            )
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            let playerItem = await withCheckedContinuation { continuation in
                PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { item, _ in
                    continuation.resume(returning: item)
                }
            }
            if let playerItem {
                player = AVPlayer(playerItem: playerItem)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("压缩失败", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定") {}
        } message: {
            Text(error ?? "")
        }
    }

    private func compressAndReplace() async {
        isCompressing = true
        defer { isCompressing = false }
        do {
            let url = try await services.videoCompression.compressVideo(
                asset: item.asset, quality: selectedQuality
            )
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs?[.size] as? Int64 ?? 0
            try await services.videoCompression.replaceOriginal(asset: item.asset, with: url)
            let savedBytes = item.fileSize - size
            compressedSize = size
            Haptics.operationSuccess()
            services.toast.compressed(max(0, savedBytes))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func compressAndSaveNew() async {
        isCompressing = true
        defer { isCompressing = false }
        do {
            let url = try await services.videoCompression.compressVideo(
                asset: item.asset, quality: selectedQuality
            )
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs?[.size] as? Int64 ?? 0
            try await services.videoCompression.saveCompressedToLibrary(url: url)
            let savedBytes = item.fileSize - size
            compressedSize = size
            Haptics.operationSuccess()
            services.toast.compressed(max(0, savedBytes))
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
