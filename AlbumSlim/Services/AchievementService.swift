import Foundation

@MainActor @Observable
final class AchievementService {
    private(set) var achievements: [Achievement] = Achievement.allAchievements

    var totalFreedSpace: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: "totalFreedSpace")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "totalFreedSpace") }
    }

    var totalCleanupCount: Int {
        get { UserDefaults.standard.integer(forKey: "totalCleanupCount") }
        set { UserDefaults.standard.set(newValue, forKey: "totalCleanupCount") }
    }

    var totalDeletedCount: Int {
        get { UserDefaults.standard.integer(forKey: "totalDeletedCount") }
        set { UserDefaults.standard.set(newValue, forKey: "totalDeletedCount") }
    }

    @discardableResult
    func recordCleanup(freedSpace: Int64, deletedCount: Int) -> [Achievement] {
        totalFreedSpace += freedSpace
        totalCleanupCount += 1
        totalDeletedCount += deletedCount
        return checkNewUnlocks()
    }

    func isUnlocked(_ achievement: Achievement) -> Bool {
        switch achievement.requirement {
        case .freedSpace(let bytes):
            return totalFreedSpace >= bytes
        case .cleanupCount(let count):
            return totalCleanupCount >= count
        case .deletedCount(let count):
            return totalDeletedCount >= count
        }
    }

    func progress(for achievement: Achievement) -> Double {
        switch achievement.requirement {
        case .freedSpace(let bytes):
            return min(1.0, Double(totalFreedSpace) / Double(bytes))
        case .cleanupCount(let count):
            return min(1.0, Double(totalCleanupCount) / Double(count))
        case .deletedCount(let count):
            return min(1.0, Double(totalDeletedCount) / Double(count))
        }
    }

    private func checkNewUnlocks() -> [Achievement] {
        let previouslyUnlocked = Set(UserDefaults.standard.stringArray(forKey: "unlockedAchievements") ?? [])
        var newlyUnlocked: [Achievement] = []
        var allUnlocked = previouslyUnlocked

        for achievement in achievements {
            if !previouslyUnlocked.contains(achievement.id) && isUnlocked(achievement) {
                newlyUnlocked.append(achievement)
                allUnlocked.insert(achievement.id)
            }
        }

        UserDefaults.standard.set(Array(allUnlocked), forKey: "unlockedAchievements")
        return newlyUnlocked
    }
}

struct Achievement: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let requirement: Requirement

    enum Requirement: Sendable {
        case freedSpace(Int64)
        case cleanupCount(Int)
        case deletedCount(Int)
    }

    var targetDescription: String {
        switch requirement {
        case .freedSpace(let bytes): return bytes.formattedFileSize
        case .cleanupCount(let count): return "\(count) 次"
        case .deletedCount(let count): return "\(count) 项"
        }
    }

    static let allAchievements: [Achievement] = [
        Achievement(id: "space_100mb", title: "初试身手", description: "累计释放 100 MB", icon: "leaf.fill", requirement: .freedSpace(100 * 1024 * 1024)),
        Achievement(id: "space_500mb", title: "小有成效", description: "累计释放 500 MB", icon: "flame.fill", requirement: .freedSpace(500 * 1024 * 1024)),
        Achievement(id: "space_1gb", title: "空间大师", description: "累计释放 1 GB", icon: "star.fill", requirement: .freedSpace(1024 * 1024 * 1024)),
        Achievement(id: "space_5gb", title: "瘦身达人", description: "累计释放 5 GB", icon: "crown.fill", requirement: .freedSpace(5 * 1024 * 1024 * 1024)),
        Achievement(id: "space_10gb", title: "传奇清理师", description: "累计释放 10 GB", icon: "trophy.fill", requirement: .freedSpace(10 * 1024 * 1024 * 1024)),
        Achievement(id: "clean_1", title: "第一次清理", description: "完成首次清理", icon: "sparkles", requirement: .cleanupCount(1)),
        Achievement(id: "clean_10", title: "清理习惯", description: "累计清理 10 次", icon: "repeat", requirement: .cleanupCount(10)),
        Achievement(id: "clean_50", title: "清理达人", description: "累计清理 50 次", icon: "bolt.fill", requirement: .cleanupCount(50)),
        Achievement(id: "delete_100", title: "果断决策", description: "累计清理 100 个项目", icon: "hand.thumbsup.fill", requirement: .deletedCount(100)),
        Achievement(id: "delete_1000", title: "大扫除", description: "累计清理 1000 个项目", icon: "tornado", requirement: .deletedCount(1000)),
    ]
}
