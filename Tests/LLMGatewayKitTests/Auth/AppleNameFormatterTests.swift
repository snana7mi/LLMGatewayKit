import XCTest
@testable import LLMGatewayKit

final class AppleNameFormatterTests: XCTestCase {
    func test_nil_returnsNil() {
        XCTAssertNil(AppleNameFormatter.string(from: nil))
    }

    func test_emptyComponents_returnsNil() {
        XCTAssertNil(AppleNameFormatter.string(from: PersonNameComponents()))
    }

    func test_whitespaceOnly_returnsNil() {
        var c = PersonNameComponents()
        c.givenName = "   "
        XCTAssertNil(AppleNameFormatter.string(from: c))
    }

    func test_givenAndFamily_returnsNonEmptyContainingBoth() throws {
        var c = PersonNameComponents()
        c.givenName = "Taro"
        c.familyName = "Tanaka"
        let result = try XCTUnwrap(AppleNameFormatter.string(from: c))
        XCTAssertTrue(result.contains("Taro"), "got \(result)")
        XCTAssertTrue(result.contains("Tanaka"), "got \(result)")
    }

    func test_userEditedChineseName_isAccepted() throws {
        var c = PersonNameComponents()
        c.familyName = "公子"
        c.givenName = "浪"

        let result = try XCTUnwrap(AppleNameFormatter.string(from: c))

        XCTAssertTrue(result.contains("公子"), "got \(result)")
        XCTAssertTrue(result.contains("浪"), "got \(result)")
    }

    func test_sanitize_removesControlsAndTrimsWhitespace() {
        XCTAssertEqual(AppleNameFormatter.sanitize("  公\n子\t浪  "), "公子浪")
    }

    func test_sanitize_overlongNameReturnsNilInsteadOfBlockingSignIn() {
        XCTAssertNil(AppleNameFormatter.sanitize(String(repeating: "浪", count: 25)))
    }
}
