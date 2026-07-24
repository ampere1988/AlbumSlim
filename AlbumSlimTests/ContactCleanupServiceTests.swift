import XCTest
@testable import AlbumSlim

final class ContactCleanupServiceTests: XCTestCase {

    private func contact(
        _ id: String,
        name: String = "张三",
        phones: [String] = [],
        emails: [String] = [],
        org: String = "",
        hasImage: Bool = false
    ) -> ContactSummary {
        ContactSummary(id: id, fullName: name, phones: phones, emails: emails,
                       organization: org, hasImage: hasImage)
    }

    // MARK: - 号码归一化

    func testNormalizePhoneStripsFormatting() {
        XCTAssertEqual(ContactCleanupService.normalizePhone("+86 138-0013-8000"), "13800138000")
    }

    func testNormalizePhoneStripsCountryCode() {
        // 同一个号码的两种写法必须归一到同一个键
        XCTAssertEqual(
            ContactCleanupService.normalizePhone("+8613800138000"),
            ContactCleanupService.normalizePhone("13800138000")
        )
    }

    func testNormalizeShortNumberKeptAsIs() {
        XCTAssertEqual(ContactCleanupService.normalizePhone("10086"), "10086")
    }

    // MARK: - 重复检测

    func testFindsDuplicatesBySharedPhone() {
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "张三", phones: ["13800138000"]),
            contact("2", name: "张三(工作)", phones: ["+86 138 0013 8000"]),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reason, .samePhone)
        XCTAssertEqual(groups.first?.contacts.count, 2)
    }

    func testFindsDuplicatesByIdenticalName() {
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "李四", phones: ["111"]),
            contact("2", name: "李四", phones: ["222"]),
        ])
        XCTAssertEqual(groups.first?.reason, .sameName)
    }

    func testDistinctContactsProduceNoGroups() {
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "张三", phones: ["111"]),
            contact("2", name: "李四", phones: ["222"]),
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyNameDoesNotGroup() {
        // 两个无名无号的条目不应被当成重复
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "", phones: []),
            contact("2", name: "", phones: []),
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testPhoneMatchTakesPriorityOverNameMatch() {
        // 同号码的分组不应再被同名规则重复收录
        let groups = ContactCleanupService.findDuplicates(in: [
            contact("1", name: "王五", phones: ["13900139000"]),
            contact("2", name: "王五", phones: ["13900139000"]),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reason, .samePhone)
    }

    // MARK: - 主记录选择

    func testPrimaryPrefersContactWithMostInformation() {
        let rich = contact("rich", phones: ["1", "2"], emails: ["a@b.com"], org: "Acme", hasImage: true)
        let sparse = contact("sparse", phones: ["1"])
        XCTAssertEqual(ContactCleanupService.pickPrimary(from: [sparse, rich]), "rich")
    }

    func testPrimaryIsStableForEqualContacts() {
        let a = contact("a", phones: ["1"])
        let b = contact("b", phones: ["1"])
        // 信息量相同时取第一个，保证结果可预测
        XCTAssertEqual(ContactCleanupService.pickPrimary(from: [a, b]), "a")
    }
}
