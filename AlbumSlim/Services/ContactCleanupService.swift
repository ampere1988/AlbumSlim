import Foundation
import Contacts

@MainActor @Observable
final class ContactCleanupService {

    private(set) var groups: [ContactDuplicateGroup] = []
    private(set) var isScanning = false
    private(set) var totalContactCount = 0
    var errorMessage: String?

    private let store = CNContactStore()

    // MARK: - 权限

    /// 只在用户主动进入联系人模块时调用，绝不在启动或引导流程里请求
    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - 扫描

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        errorMessage = nil

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]

        var summaries: [ContactSummary] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                summaries.append(Self.summarize(contact))
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        totalContactCount = summaries.count
        groups = Self.findDuplicates(in: summaries)
    }

    private static func summarize(_ contact: CNContact) -> ContactSummary {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? "\(contact.familyName)\(contact.givenName)"
        return ContactSummary(
            id: contact.identifier,
            fullName: name.trimmingCharacters(in: .whitespaces),
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String },
            organization: contact.organizationName,
            hasImage: contact.imageDataAvailable
        )
    }

    // MARK: - 归一化与匹配（纯函数，可单测）

    /// 抹掉格式差异，并去掉中国大陆 +86 国家码，让同一号码的多种写法归到同一个键
    nonisolated static func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count > 11 else { return digits }
        if digits.hasPrefix("86") {
            return String(digits.dropFirst(2))
        }
        // 其它国家码：保留后 11 位做近似匹配
        return String(digits.suffix(11))
    }

    /// 先按号码分组，剩下的再按姓名分组。号码优先——同号码的条目不会被姓名规则重复收录。
    nonisolated static func findDuplicates(in contacts: [ContactSummary]) -> [ContactDuplicateGroup] {
        var groups: [ContactDuplicateGroup] = []
        var claimed = Set<String>()

        // 1) 号码相同
        var byPhone: [String: [ContactSummary]] = [:]
        for contact in contacts {
            for phone in contact.phones {
                let key = normalizePhone(phone)
                guard !key.isEmpty else { continue }
                if byPhone[key]?.contains(where: { $0.id == contact.id }) == true { continue }
                byPhone[key, default: []].append(contact)
            }
        }
        for (key, members) in byPhone where members.count > 1 {
            let fresh = members.filter { !claimed.contains($0.id) }
            guard fresh.count > 1 else { continue }
            fresh.forEach { claimed.insert($0.id) }
            groups.append(ContactDuplicateGroup(
                id: "phone-\(key)",
                reason: .samePhone,
                contacts: fresh,
                primaryID: pickPrimary(from: fresh)
            ))
        }

        // 2) 姓名相同（排除已被号码规则收走的，以及空名）
        var byName: [String: [ContactSummary]] = [:]
        for contact in contacts where !claimed.contains(contact.id) {
            let key = contact.fullName.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            byName[key, default: []].append(contact)
        }
        for (key, members) in byName where members.count > 1 {
            members.forEach { claimed.insert($0.id) }
            groups.append(ContactDuplicateGroup(
                id: "name-\(key)",
                reason: .sameName,
                contacts: members,
                primaryID: pickPrimary(from: members)
            ))
        }

        // 结果按可删除数量降序，收益大的排前面；同数量时按 id 保证顺序稳定
        return groups.sorted {
            $0.removableCount == $1.removableCount
                ? $0.id < $1.id
                : $0.removableCount > $1.removableCount
        }
    }

    /// 信息最全的作为主记录；并列时取输入顺序里的第一个，保证结果可预测
    nonisolated static func pickPrimary(from contacts: [ContactSummary]) -> String {
        guard var best = contacts.first else { return "" }
        for candidate in contacts.dropFirst() where candidate.richness > best.richness {
            best = candidate
        }
        return best.id
    }

    // MARK: - 合并

    /// 把组内其余条目的号码与邮箱并入主记录，然后删除其余条目。
    /// 不可逆——调用方必须先弹确认。
    func merge(group: ContactDuplicateGroup) async throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]

        let ids = group.contacts.map(\.id)
        let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
        let fetched = try store.unifiedContacts(matching: predicate, keysToFetch: keys)

        guard let primaryContact = fetched.first(where: { $0.identifier == group.primaryID }) else {
            throw NSError(domain: "ContactCleanup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "找不到主联系人")
            ])
        }

        let mutable = primaryContact.mutableCopy() as! CNMutableContact
        let others = fetched.filter { $0.identifier != group.primaryID }

        // 按归一化号码去重后并入
        var seenPhones = Set(mutable.phoneNumbers.map { Self.normalizePhone($0.value.stringValue) })
        var seenEmails = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })

        for other in others {
            for phone in other.phoneNumbers {
                let key = Self.normalizePhone(phone.value.stringValue)
                guard !key.isEmpty, !seenPhones.contains(key) else { continue }
                seenPhones.insert(key)
                mutable.phoneNumbers.append(phone)
            }
            for email in other.emailAddresses {
                let key = (email.value as String).lowercased()
                guard !key.isEmpty, !seenEmails.contains(key) else { continue }
                seenEmails.insert(key)
                mutable.emailAddresses.append(email)
            }
            if mutable.organizationName.isEmpty, !other.organizationName.isEmpty {
                mutable.organizationName = other.organizationName
            }
        }

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        for other in others {
            guard let deletable = other.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(deletable)
        }
        try store.execute(saveRequest)

        groups.removeAll { $0.id == group.id }
    }
}
