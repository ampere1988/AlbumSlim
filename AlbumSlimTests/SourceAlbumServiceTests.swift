import XCTest
@testable import AlbumSlim

final class SourceAlbumServiceTests: XCTestCase {

    func testMatchesWeChatByChineseName() {
        let app = SourceApp.match(albumTitle: "微信")
        XCTAssertEqual(app?.id, "wechat")
    }

    func testMatchesWeChatByEnglishName() {
        XCTAssertEqual(SourceApp.match(albumTitle: "WeChat")?.id, "wechat")
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(SourceApp.match(albumTitle: "whatsapp")?.id, "whatsapp")
        XCTAssertEqual(SourceApp.match(albumTitle: "WhatsApp")?.id, "whatsapp")
    }

    func testMatchTrimsWhitespace() {
        XCTAssertEqual(SourceApp.match(albumTitle: "  QQ  ")?.id, "qq")
    }

    func testUnknownAlbumReturnsNil() {
        XCTAssertNil(SourceApp.match(albumTitle: "我的旅行相册"))
    }

    func testDoesNotMatchOnPartialSubstring() {
        // "微信读书" 是另一个 app，不该被算成微信
        XCTAssertNil(SourceApp.match(albumTitle: "微信读书"))
    }

    func testAllKnownAppsHaveUniqueIDs() {
        let ids = SourceApp.known.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAllKnownAppsHaveAtLeastOneAlias() {
        for app in SourceApp.known {
            XCTAssertFalse(app.aliases.isEmpty, "\(app.id) 缺少别名")
        }
    }
}
