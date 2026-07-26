import SwiftUI

struct AchievementView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        List {
            statsSection
            achievementsSection
        }
        .cardListStyle()
        .navigationTitle("清理成就")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareAchievements()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享成就")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ActivityShareSheet(items: [shareImage])
            }
        }
    }

    private func shareAchievements() {
        let totalFreed = services.achievement.totalFreedSpace
        let cleanupCount = services.achievement.totalCleanupCount
        guard let image = ShareCardGenerator.generateShareImage(
            freedSpace: totalFreed,
            totalFreed: totalFreed,
            cleanupCount: cleanupCount,
            isCumulative: true
        ) else { return }
        shareImage = image
        showShareSheet = true
    }

    // MARK: - 统计卡片

    private var statsSection: some View {
        Section {
            VStack(spacing: Spacing.l) {
                // 累计释放是这一页唯一的"成绩单"，单独放大一档
                VStack(spacing: Spacing.xs) {
                    Text(services.achievement.totalFreedSpace.formattedFileSize)
                        .font(AppFont.display)
                        .foregroundStyle(Theme.accentGradient)
                    Text("累计释放")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 0) {
                    statItem(value: "\(services.achievement.totalCleanupCount)", label: "清理次数")
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 32)
                    statItem(value: "\(services.achievement.totalDeletedCount)", label: "清理项目")
                }
            }
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: .infinity)
            .glassSurface()
            .cardListRow()
            .accessibilityElement(children: .combine)
        }
    }

    private func statItem(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(AppFont.metric)
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 成就列表

    private var achievementsSection: some View {
        Section {
            ForEach(services.achievement.achievements) { achievement in
                AchievementBadgeRow(
                    achievement: achievement,
                    isUnlocked: services.achievement.isUnlocked(achievement),
                    progress: services.achievement.progress(for: achievement)
                )
                .padding(Spacing.m)
                .glassSurface(radius: Radius.row)
                .cardListRow()
            }
        } header: {
            SectionHeader(title: "全部成就", tint: Theme.warning)
                .cardListRow()
        }
    }
}

// MARK: - UIActivityViewController SwiftUI 包装

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
