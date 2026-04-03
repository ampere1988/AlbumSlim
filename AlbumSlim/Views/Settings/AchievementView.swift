import SwiftUI

struct AchievementView: View {
    @Environment(AppServiceContainer.self) private var services

    var body: some View {
        List {
            statsSection
            achievementsSection
        }
        .navigationTitle("清理成就")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 统计卡片

    private var statsSection: some View {
        Section {
            HStack(spacing: 0) {
                statItem(
                    value: services.achievement.totalFreedSpace.formattedFileSize,
                    label: "累计释放"
                )
                Divider().frame(height: 40)
                statItem(
                    value: "\(services.achievement.totalCleanupCount)",
                    label: "清理次数"
                )
                Divider().frame(height: 40)
                statItem(
                    value: "\(services.achievement.totalDeletedCount)",
                    label: "清理项目"
                )
            }
            .padding(.vertical, 8)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.orange)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 成就列表

    private var achievementsSection: some View {
        Section("全部成就") {
            ForEach(services.achievement.achievements) { achievement in
                achievementRow(achievement)
            }
        }
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        let unlocked = services.achievement.isUnlocked(achievement)
        let progress = services.achievement.progress(for: achievement)

        return HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.title2)
                .foregroundStyle(unlocked ? .orange : .gray)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(unlocked ? .primary : .secondary)
                Text(achievement.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !unlocked {
                    ProgressView(value: progress)
                        .tint(.orange)
                }
            }

            Spacer()

            if unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .opacity(unlocked ? 1.0 : 0.6)
    }
}
