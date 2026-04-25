import SwiftUI
import Photos

struct WastePhotosView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = PhotoCleanerViewModel()
    @State private var isEditing = false
    @State private var showPaywall = false
    @State private var showTrash = false

    var body: some View {
        Group {
            if viewModel.isScanning {
                ProgressLoadingState(phase: AppStrings.scanning, progress: viewModel.scanProgress)
            } else if viewModel.wasteItems.isEmpty {
                EmptyState("废片", systemImage: AppIcons.waste) {
                    Button("开始扫描") {
                        Task { await viewModel.scanWastePhotos(services: services) }
                    }
                    .primaryActionStyle()
                }
            } else {
                List {
                    SpaceSavedBanner(
                        count: viewModel.wasteItems.count,
                        size: viewModel.wasteItems.reduce(Int64(0)) { $0 + $1.fileSize }
                    )
                    .listRowInsets(EdgeInsets())

                    ForEach(viewModel.wasteItems) { item in
                        HStack(spacing: 12) {
                            if isEditing {
                                Image(systemName: viewModel.selectedForDeletion.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedForDeletion.contains(item.id) ? .blue : .secondary)
                                    .onTapGesture { viewModel.toggleSelection(item.id) }
                            }

                            AsyncThumbnail(asset: item.asset, services: services)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))

                            VStack(alignment: .leading, spacing: 4) {
                                if let reason = viewModel.wasteReasons[item.id] {
                                    reasonTag(reason)
                                }
                                Text(item.fileSizeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !isEditing {
                                Button("保留") {
                                    viewModel.keepItem(item.id)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if isEditing && !viewModel.selectedForDeletion.isEmpty {
                        ActionBar {
                            Button(role: .destructive) {
                                guard services.subscription.isPro else {
                                    Haptics.proGate()
                                    services.toast.proRequired()
                                    showPaywall = true
                                    return
                                }
                                let count = viewModel.selectedForDeletion.count
                                Task {
                                    await viewModel.deleteSelected(services: services, source: .waste)
                                    Haptics.moveToTrash()
                                    services.toast.movedToTrash(count)
                                    isEditing = false
                                }
                            } label: {
                                Text("\(AppStrings.moveToTrash) \(AppStrings.items(viewModel.selectedForDeletion.count))")
                                    .frame(maxWidth: .infinity)
                            }
                            .primaryActionStyle(destructive: true)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TrashToolbarButton(count: services.trash.trashedItems.count) {
                    showTrash = true
                }
            }
        }
        .selectionToolbar(
            isEditing: $isEditing,
            selectedCount: viewModel.selectedForDeletion.count,
            totalCount: viewModel.wasteItems.count,
            onSelectAll: { viewModel.selectedForDeletion = Set(viewModel.wasteItems.map(\.id)) },
            onDeselectAll: { viewModel.selectedForDeletion.removeAll() }
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showTrash) { GlobalTrashView() }
        .task {
            if viewModel.wasteItems.isEmpty && !viewModel.isScanning {
                await viewModel.scanWastePhotos(services: services)
            }
        }
        .onChange(of: services.trash.trashedItems.count) { _, _ in
            if services.trash.lastChangeKind == .permanentDelete { return }
            Task { await viewModel.reloadWaste(services: services) }
        }
    }

    @ViewBuilder
    private func reasonTag(_ reason: WasteReason) -> some View {
        let (text, color): (String, Color) = switch reason {
        case .pureBlack: ("纯黑", .gray)
        case .pureWhite: ("纯白", .gray)
        case .blurry: ("模糊", .orange)
        case .fingerBlock: ("遮挡", .red)
        case .accidental: ("误拍", .purple)
        }
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct AsyncThumbnail: View {
    let asset: PHAsset
    let services: AppServiceContainer
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { ProgressView() }
            }
        }
        .task {
            image = await services.photoLibrary.thumbnail(for: asset, size: CGSize(width: 120, height: 120))
        }
    }
}
