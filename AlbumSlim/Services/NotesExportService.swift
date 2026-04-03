import Foundation
import UIKit

final class NotesExportService {

    func exportToNotes(title: String, content: String) {
        // 通过 URL Scheme 打开备忘录并创建内容
        let noteText = """
        \(title)

        \(content)

        — 由相册瘦身导出
        """

        let encoded = noteText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mobilenotes://create?body=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    func formatScreenshotNote(ocrResult: OCRResult, date: Date?) -> (title: String, content: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = date.map { formatter.string(from: $0) } ?? "未知日期"

        let title = "截图内容 - \(ocrResult.category.rawValue) (\(dateStr))"
        return (title, ocrResult.text)
    }
}
