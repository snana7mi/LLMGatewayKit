import XCTest
@testable import LLMGatewayKit

final class AccountUserTests: XCTestCase {
    func test_decode_withMemberNo() throws {
        let json = Data(#"{"id":"u","tier":"free","memberNo":42}"#.utf8)
        let user = try JSONDecoder.gateway.decode(AccountUser.self, from: json)
        XCTAssertEqual(user.memberNo, 42)
    }

    func test_decode_withoutMemberNo_isNil() throws {
        let json = Data(#"{"id":"u","tier":"free"}"#.utf8)
        let user = try JSONDecoder.gateway.decode(AccountUser.self, from: json)
        XCTAssertNil(user.memberNo)
    }
}
