import Foundation

struct ContactSummary: Identifiable, Sendable, Equatable {
    let id: String
    let fullName: String
    let phones: [String]
    let emails: [String]
    let organization: String
    let hasImage: Bool

    /// 信息完整度，用于挑选合并后的主记录
    var richness: Int {
        var score = phones.count * 2 + emails.count * 2
        if !organization.isEmpty { score += 1 }
        if hasImage { score += 3 }
        if !fullName.isEmpty { score += 1 }
        return score
    }

    var subtitle: String {
        if let phone = phones.first { return phone }
        if let email = emails.first { return email }
        return organization
    }
}

struct ContactDuplicateGroup: Identifiable, Sendable {
    enum MatchReason: String, Sendable {
        case samePhone
        case sameName

        var label: String {
            switch self {
            case .samePhone: return String(localized: "号码相同")
            case .sameName:  return String(localized: "姓名相同")
            }
        }
    }

    let id: String
    let reason: MatchReason
    let contacts: [ContactSummary]
    let primaryID: String

    var primary: ContactSummary? {
        contacts.first { $0.id == primaryID }
    }

    /// 合并后会被删掉的条目数
    var removableCount: Int { max(0, contacts.count - 1) }
}
