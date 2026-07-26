import SwiftUI

struct QuickCleanView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var viewModel = QuickCleanViewModel()

    var body: some View {
        Group {
            if viewModel.isScanning {
                scanningView
            } else if viewModel.wasCancelled && viewModel.cleanupGroups.isEmpty {
                pausedStateView
            } else if viewModel.cleanupGroups.isEmpty {
                EmptyState("可清理项", systemImage: "sparkles",
                           description: "相册很整洁", tint: Theme.success)
            } else {
                resultSummary
            }
        }
        .background(Theme.background)
        .navigationTitle("智能扫描")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 等待骨架恢复完成，避免重启后 pendingGroups 尚未加载就触发 fullScan
            await services.prepareAsync()
            if viewModel.cleanupGroups.isEmpty && !viewModel.isScanning {
                await viewModel.loadOrScan(services: services)
            }
        }
    }

    // MARK: - 扫描中

    private var scanningView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            ScanProgressRing(
                phase: services.cleanupCoordinator.scanPhase.localizedName,
                progress: services.cleanupCoordinator.scanProgress
            )
            Button(AppStrings.cancel, action: viewModel.cancelScan)
                .secondaryActionStyle()
                .frame(maxWidth: 200)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 已暂停（用户取消扫描）

    private var pausedStateView: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            GlowIcon(systemImage: "pause.fill", tint: Theme.warning, size: 76)
            Text("已暂停扫描")
                .font(AppFont.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("扫描进度已保存，可随时继续")
                .font(AppFont.meta)
                .foregroundStyle(Theme.textSecondary)
            Button(action: resumeScan) {
                Label("继续扫描", systemImage: "arrow.clockwise")
            }
            .primaryActionStyle()
            .frame(maxWidth: 240)
            .padding(.top, Spacing.s)
            Spacer()
        }
        .padding(Spacing.l)
    }

    // MARK: - 扫描结果总览

    private var resultSummary: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                summaryHeader
                    .padding(.bottom, Spacing.s)

                ForEach(sortedTypes, id: \.0) { type, groups in
                    categoryCard(type: type, groups: groups)
                }

                Button(action: rescan) {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .secondaryActionStyle()
                .padding(.top, Spacing.s)
            }
            .padding(Spacing.l)
        }
    }

    /// 头部把"总共能释放多少"顶到主位 —— 这是用户真正关心的唯一数字
    private var summaryHeader: some View {
        VStack(spacing: Spacing.s) {
            GlowIcon(
                systemImage: viewModel.hasCompletedScan ? "checkmark" : "clock.arrow.circlepath",
                tint: viewModel.hasCompletedScan ? Theme.success : Theme.textSecondary,
                size: 64
            )
            Text(totalSavableSize.formattedFileSize)
                .font(AppFont.display)
                .foregroundStyle(Theme.accentGradient)
            Text(viewModel.hasCompletedScan ? "本次扫描可释放" : "上次扫描可释放")
                .font(AppFont.meta)
                .foregroundStyle(Theme.textSecondary)
            Text("点击分类前往对应页面查看详情")
                .font(AppFont.label)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 分类卡片

    @ViewBuilder
    private func categoryCard(type: CleanupGroup.GroupType, groups: [CleanupGroup]) -> some View {
        let card = CleanupCategoryCard(
            type: type,
            countText: countText(type, groups),
            sizeText: sizeText(groups),
            leavesCurrentStack: type == .largeVideo
        )

        switch type {
        case .waste:
            NavigationLink { WastePhotosView().navigationTitle("废片检测") } label: { card }
                .pressableCardStyle()
        case .similar:
            NavigationLink { SimilarPhotosView().navigationTitle("相似照片") } label: { card }
                .pressableCardStyle()
        case .burst:
            NavigationLink { BurstPhotosView().navigationTitle("连拍清理") } label: { card }
                .pressableCardStyle()
        case .largePhoto:
            NavigationLink { LargePhotosView().navigationTitle("超大照片") } label: { card }
                .pressableCardStyle()
        case .largeVideo:
            Button(action: switchToVideoTab) { card }
                .pressableCardStyle()
        case .screenshot:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func resumeScan() {
        Task { await viewModel.loadOrScan(services: services) }
    }

    private func rescan() {
        Task { await viewModel.forceRescan(services: services) }
    }

    private func switchToVideoTab() {
        NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": 1])
    }

    // MARK: - Helpers

    private var sortedTypes: [(CleanupGroup.GroupType, [CleanupGroup])] {
        let order: [CleanupGroup.GroupType] = [.waste, .similar, .burst, .largePhoto, .largeVideo]
        return order.compactMap { type in
            guard let groups = viewModel.groupsByType[type], !groups.isEmpty else { return nil }
            return (type, groups)
        }
    }

    private var totalSavableSize: Int64 {
        sortedTypes.reduce(Int64(0)) { partial, entry in
            partial + entry.1.reduce(Int64(0)) { $0 + $1.savableSize }
        }
    }

    private func countText(_ type: CleanupGroup.GroupType, _ groups: [CleanupGroup]) -> String {
        if type == .similar || type == .burst {
            return String(localized: "\(groups.count) 组")
        }
        let total = groups.reduce(0) { $0 + $1.items.count }
        return String(localized: "\(total) 项")
    }

    private func sizeText(_ groups: [CleanupGroup]) -> String {
        groups.reduce(Int64(0)) { $0 + $1.savableSize }.formattedFileSize
    }
}
