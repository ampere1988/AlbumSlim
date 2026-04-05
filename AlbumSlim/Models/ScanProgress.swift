import Foundation

struct ScanProgress: Codable {
    enum Phase: String, Codable, CaseIterable {
        case waste      // 废片检测
        case similar    // 特征向量提取（相似照片分析的前置步骤）
        case done       // 完成
    }

    var phase: Phase = .waste
    var libraryVersion: Int = -1
    var startedAt: Date = .now
    var lastUpdatedAt: Date = .now

    // MARK: - 持久化

    private static let key = "ScanProgressCache"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func load() -> ScanProgress? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ScanProgress.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
