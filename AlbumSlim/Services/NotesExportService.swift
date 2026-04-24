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

    func shareText(text: String, category: String, screenshotDate: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = screenshotDate.map { formatter.string(from: $0) } ?? String(localized: "未知日期")
        return "\(category) | \(dateStr)\n\n\(text)\n\n\(String(localized: "— 由闪图导出"))"
    }

    func shareText(for note: SavedNote) -> String {
        shareText(text: note.text, category: note.category, screenshotDate: note.screenshotDate)
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
