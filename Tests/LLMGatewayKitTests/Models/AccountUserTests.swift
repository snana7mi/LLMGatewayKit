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

    func test_decode_proStoreBacked() throws {
        let json = Data(#"{"id":"u","tier":"paid","proStoreBacked":false}"#.utf8)
        let user = try JSONDecoder.gateway.decode(AccountUser.self, from: json)
        XCTAssertEqual(user.proStoreBacked, false)
    }

    func test_decode_nullOrMissingProStoreBacked_isNil() throws {
        let null = Data(#"{"id":"u","tier":"free","proStoreBacked":null}"#.utf8)
        XCTAssertNil(try JSONDecoder.gateway.decode(AccountUser.self, from: null).proStoreBacked)
        let missing = Data(#"{"id":"u","tier":"paid"}"#.utf8)
        XCTAssertNil(try JSONDecoder.gateway.decode(AccountUser.self, from: missing).proStoreBacked)
    }
}
