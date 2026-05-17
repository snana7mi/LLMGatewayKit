import XCTest
@testable import LLMGatewayKit

final class KeychainTokenStoreTests: XCTestCase {
    func test_roundTrip() throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "A", refreshToken: "R", expiry: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(try store.loadAccessToken(), "A")
        XCTAssertEqual(try store.loadRefreshToken(), "R")
        XCTAssertEqual(try store.loadExpiry()?.timeIntervalSince1970, 1000)
    }

    func test_clear() throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "A", refreshToken: "R", expiry: Date())
        try store.clear()

        XCTAssertNil(try store.loadAccessToken())
    }
}

final class AppleSignInBridgeTests: XCTestCase {
    @MainActor
    func test_protocolConformance() async throws {
        let mock = MockAppleSignInBridge(result: .success(.init(identityToken: "tok", appleUserId: "sub")))
        let result = try await mock.authenticate(nonceRaw: "n", hashedNonce: "h")

        XCTAssertEqual(result.identityToken, "tok")
        XCTAssertEqual(result.appleUserId, "sub")
    }
}

final class NonceGeneratorTests: XCTestCase {
    func test_pairHasNonEmptyRawAndHashedDifferent() {
        let pair = NonceGenerator.makePair()

        XCTAssertFalse(pair.raw.isEmpty)
        XCTAssertFalse(pair.hashedSHA256.isEmpty)
        XCTAssertNotEqual(pair.raw, pair.hashedSHA256)
    }

    func test_hashIsSHA256Hex() {
        let pair = NonceGenerator.makePair()

        XCTAssertEqual(pair.hashedSHA256.count, 64)
        XCTAssertTrue(pair.hashedSHA256.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
