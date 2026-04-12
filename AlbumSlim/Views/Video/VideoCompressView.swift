import SwiftUI
import Photos

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
    @State private var showPaywall = false
    @State private var showDeleteConfirm = false

    private var isCompleted: Bool { compressedSize != nil }

    var body: some View {
        List {
            // 视频缩略图预览
            Section {
                HStack {
                    Spacer()
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "video.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .listRowBackground(Color.clear)
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
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("删除视频", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }

            if isCompressing {
                Section {
                    VStack(spacing: 8) {
                        ProgressView(value: services.videoCompression.progress) {
                            Text("压缩中...")
                        }
                        Text("\(Int(services.videoCompression.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        Button {
                            if ProFeatureGate.canCompress(isPro: services.subscription.isPro) {
                                Task { await compressAndReplace() }
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            Text("压缩并替换原视频")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)

                        Button {
                            if ProFeatureGate.canCompress(isPro: services.subscription.isPro) {
                                Task { await compressAndSaveNew() }
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            Text("压缩保存为新视频")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog("确认删除", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除视频", role: .destructive) {
                Task {
                    try? await services.photoLibrary.deleteAssets([item.asset])
                    dismiss()
                }
            }
        } message: {
            Text("删除后视频将移至「最近删除」相簿")
        }
        .navigationTitle("视频压缩")
        .task {
            thumbnail = await services.photoLibrary.thumbnail(
                for: item.asset, size: CGSize(width: 600, height: 400)
            )
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
            compressedSize = size
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
            compressedSize = size
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
