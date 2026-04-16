import Foundation

struct SavedNote: Codable, Identifiable {
    let id: UUID
    let text: String
    let category: String
    let screenshotDate: Date?
    let savedDate: Date
}
