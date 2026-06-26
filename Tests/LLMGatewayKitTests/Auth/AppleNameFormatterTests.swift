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
}
