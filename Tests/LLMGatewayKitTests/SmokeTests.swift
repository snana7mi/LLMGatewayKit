import XCTest
@testable import LLMGatewayKit

final class SmokeTests: XCTestCase {
    func test_version() {
        XCTAssertEqual(LLMGatewayKit.version, "0.1.0")
    }
}
