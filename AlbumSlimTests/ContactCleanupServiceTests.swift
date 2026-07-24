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

    // MARK: - 传递性分组

    func testTransitivePhoneOverlapMergesIntoOneGroup() {
        // A 持有 P1、P2；B 只有 P1；C 只有 P2。A-B、A-C 各自共享一个号码，
        // 三者必须传递归入同一组，不能因为字典遍历顺序把 C 甩出去。
        let a = contact("A", name: "A", phones: ["11100000001", "22200000002"])
        let b = contact("B", name: "B", phones: ["11100000001"])
        let c = contact("C", name: "C", phones: ["22200000002"])
        let groups = ContactCleanupService.findDuplicates(in: [a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reason, .samePhone)
        XCTAssertEqual(Set(groups.first?.contacts.map(\.id) ?? []), ["A", "B", "C"])
    }

    func testTransitivePhoneGroupingIsOrderIndependent() {
        // 同样的三个联系人，换一个输入顺序，分组结果必须完全一致（成员集合与 group id）。
        let a = contact("A", name: "A", phones: ["11100000001", "22200000002"])
        let b = contact("B", name: "B", phones: ["11100000001"])
        let c = contact("C", name: "C", phones: ["22200000002"])
        let order1 = ContactCleanupService.findDuplicates(in: [a, b, c])
        let order2 = ContactCleanupService.findDuplicates(in: [c, a, b])
        XCTAssertEqual(order1.count, 1)
        XCTAssertEqual(order2.count, 1)
        XCTAssertEqual(
            Set(order1.first?.contacts.map(\.id) ?? []),
            Set(order2.first?.contacts.map(\.id) ?? [])
        )
        XCTAssertEqual(order1.first?.id, order2.first?.id)
    }

    func testContactBridgingTwoClustersMergesThemIntoOneGroup() {
        // D-E 共享号码 P3，F-G 共享号码 P4，两簇原本无关；H 同时持有 P3 和 P4，把它们桥接成一组，
        // 而不是让其中一簇因为“已被认领”被丢弃。
        let d = contact("D", name: "D", phones: ["33300000003"])
        let e = contact("E", name: "E", phones: ["33300000003"])
        let f = contact("F", name: "F", phones: ["44400000004"])
        let g = contact("G", name: "G", phones: ["44400000004"])
        let h = contact("H", name: "H", phones: ["33300000003", "44400000004"])
        let groups = ContactCleanupService.findDuplicates(in: [d, e, f, g, h])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reason, .samePhone)
        XCTAssertEqual(Set(groups.first?.contacts.map(\.id) ?? []), ["D", "E", "F", "G", "H"])
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
