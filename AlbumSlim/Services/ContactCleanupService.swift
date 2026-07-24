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
    ///
    /// 号码分组用并查集把"共享同一归一化号码"关系做传递闭包连通：
    /// A、B 共享 P1，A、C 共享 P2 ⇒ A/B/C 归入同一组，不会因为字典遍历顺序把 C 甩出去。
    /// 合并方向固定取较小下标为根，结果与 Dictionary 遍历顺序无关，保证同一份输入每次跑出同样的分组。
    nonisolated static func findDuplicates(in contacts: [ContactSummary]) -> [ContactDuplicateGroup] {
        var groups: [ContactDuplicateGroup] = []
        var claimed = Set<String>()

        // 1) 号码相同——并查集做连通分量
        var parent = Array(contacts.indices)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            // 固定取较小下标为根，避免结果依赖联合顺序
            if ra < rb { parent[rb] = ra } else { parent[ra] = rb }
        }

        var byPhone: [String: [Int]] = [:]
        for (index, contact) in contacts.enumerated() {
            for phone in contact.phones {
                let key = normalizePhone(phone)
                guard !key.isEmpty else { continue }
                if byPhone[key]?.contains(index) == true { continue }
                byPhone[key, default: []].append(index)
            }
        }
        for (_, indices) in byPhone where indices.count > 1 {
            for i in indices.dropFirst() {
                union(indices[0], i)
            }
        }

        var components: [Int: [Int]] = [:]
        for index in contacts.indices {
            components[find(index), default: []].append(index)
        }
        for (_, indices) in components where indices.count > 1 {
            // indices 天然按输入顺序收集（0..<count 递增遍历），组内顺序与遍历顺序无关
            let members = indices.map { contacts[$0] }
            members.forEach { claimed.insert($0.id) }
            let groupID = "phone-" + members.map(\.id).sorted().joined(separator: "|")
            groups.append(ContactDuplicateGroup(
                id: groupID,
                reason: .samePhone,
                contacts: members,
                primaryID: pickPrimary(from: members)
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

    // MARK: - 合并去重键（纯函数）

    /// 邮寄地址去重键：拼接各字段、去空白、转小写，格式不同但内容相同的地址会归到同一个键
    nonisolated private static func postalAddressKey(_ address: CNPostalAddress) -> String {
        [address.street, address.city, address.state, address.postalCode, address.country]
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .joined(separator: "|")
    }

    /// 社交资料去重键：服务名 + 用户名（用户名为空则退回 URL 字符串）
    nonisolated private static func socialProfileKey(_ profile: CNSocialProfile) -> String {
        let identifier = profile.username.isEmpty ? profile.urlString : profile.username
        return "\(profile.service.lowercased())|\(identifier.lowercased())"
    }

    // MARK: - 合并

    /// 把组内其余条目的信息并入主记录（多值字段去重合并，单值字段仅在主记录为空时补齐），然后删除其余条目。
    /// 不可逆——调用方必须先弹确认。
    ///
    /// 注：不读取/合并 `note`——该字段在现代 iOS 上需要 `com.apple.developer.contacts.notes`
    /// 专属 entitlement，本应用未申请，读取会直接抛异常，故整段跳过。
    func merge(group: ContactDuplicateGroup) async throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactSocialProfilesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
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

        // 按归一化号码/邮箱去重后并入
        var seenPhones = Set(mutable.phoneNumbers.map { Self.normalizePhone($0.value.stringValue) })
        var seenEmails = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })
        // 多值字段去重键：地址按格式化文本，网址按小写字符串，社交资料按服务+用户名
        var seenAddresses = Set(mutable.postalAddresses.map { Self.postalAddressKey($0.value) })
        var seenURLs = Set(mutable.urlAddresses.map { ($0.value as String).lowercased() })
        var seenSocialProfiles = Set(mutable.socialProfiles.map { Self.socialProfileKey($0.value) })

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
            for address in other.postalAddresses {
                let key = Self.postalAddressKey(address.value)
                guard !key.isEmpty, !seenAddresses.contains(key) else { continue }
                seenAddresses.insert(key)
                mutable.postalAddresses.append(address)
            }
            for url in other.urlAddresses {
                let key = (url.value as String).lowercased()
                guard !key.isEmpty, !seenURLs.contains(key) else { continue }
                seenURLs.insert(key)
                mutable.urlAddresses.append(url)
            }
            for profile in other.socialProfiles {
                let key = Self.socialProfileKey(profile.value)
                guard !key.isEmpty, !seenSocialProfiles.contains(key) else { continue }
                seenSocialProfiles.insert(key)
                mutable.socialProfiles.append(profile)
            }

            // 单值字段：仅在主记录为空时用第一个非空来源补齐，绝不覆盖已有值
            if mutable.organizationName.isEmpty, !other.organizationName.isEmpty {
                mutable.organizationName = other.organizationName
            }
            if mutable.jobTitle.isEmpty, !other.jobTitle.isEmpty {
                mutable.jobTitle = other.jobTitle
            }
            if mutable.departmentName.isEmpty, !other.departmentName.isEmpty {
                mutable.departmentName = other.departmentName
            }
            if mutable.givenName.isEmpty, !other.givenName.isEmpty {
                mutable.givenName = other.givenName
            }
            if mutable.familyName.isEmpty, !other.familyName.isEmpty {
                mutable.familyName = other.familyName
            }
            if mutable.birthday == nil, other.birthday != nil {
                mutable.birthday = other.birthday
            }
            if mutable.imageData == nil, other.imageData != nil {
                mutable.imageData = other.imageData
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
