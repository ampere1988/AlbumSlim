import Foundation

final class NotesExportService {
    static let folderName = "AlbumSlim 截图笔记"

    var notesFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.folderName)
    }

    @discardableResult
    func saveNote(title: String, content: String) throws -> URL {
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        let filename = sanitize(title) + ".txt"
        let url = notesFolder.appendingPathComponent(filename)
        let text = "\(title)\n\n\(content)\n\n— 由闪图导出"
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func saveBatch(_ notes: [(title: String, content: String)]) throws -> [URL] {
        try notes.map { try saveNote(title: $0.title, content: $0.content) }
    }

    func formatScreenshotNote(ocrResult: OCRResult, date: Date?) -> (title: String, content: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let dateStr = date.map { formatter.string(from: $0) } ?? "未知日期"
        let title = "\(dateStr) \(ocrResult.category.rawValue)"
        return (title, ocrResult.text)
    }

    func shareText(for ocrResult: OCRResult, date: Date?) -> String {
        let (title, content) = formatScreenshotNote(ocrResult: ocrResult, date: date)
        return "\(title)\n\n\(content)\n\n— 由闪图导出"
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "_")
    }
}
