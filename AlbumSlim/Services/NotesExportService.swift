import Foundation

@MainActor @Observable
final class NotesExportService {
    private static let storageKey = "savedScreenshotNotes"

    private(set) var notes: [SavedNote] = []

    init() {
        loadNotes()
    }

    @discardableResult
    func saveNote(text: String, category: ScreenshotCategory, screenshotDate: Date?) -> SavedNote {
        let note = SavedNote(
            id: UUID(),
            text: text,
            category: category.rawValue,
            screenshotDate: screenshotDate,
            savedDate: Date()
        )
        notes.insert(note, at: 0)
        persist()
        return note
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        notes.removeAll()
        persist()
    }

    func shareText(for note: SavedNote) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = note.screenshotDate.map { formatter.string(from: $0) } ?? "未知日期"
        return "\(note.category) | \(dateStr)\n\n\(note.text)\n\n— 由闪图导出"
    }

    private func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SavedNote].self, from: data) else { return }
        notes = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
