import XCTest
@testable import LLMGatewayKit

final class AuthServiceGoogleTests: XCTestCase {

    @MainActor
    private func makeSUT(
        responses: [URLProtocolStub.Response],
        google: MockGoogleSignInProviding? = nil,
        store: InMemoryTokenStore = InMemoryTokenStore()
    ) -> AuthService {
        URLProtocolStub.reset(responses: responses)
        return AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            googleProvider: google
        )
    }

    @MainActor
    func test_googleSignIn_postsToAuthGoogle_andStoresTokens() async throws {
        let store = InMemoryTokenStore()
        let sut = makeSUT(
            responses: [.success(body: #"{"accessToken":"acc","refreshToken":"ref","user":{"id":"u","tier":"free","linkedProviders":["google"]}}"#, status: 200)],
            google: MockGoogleSignInProviding(result: .success(.init(provider: .google, idToken: "gid-token", providerUid: "g-sub", displayName: nil, rawNonce: "raw-n"))),
            store: store
        )

        try await sut.authenticateWithGoogleInteractively()

        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(try store.loadAccessToken(), "acc")
        XCTAssertEqual(sut.currentUser?.linkedProviders, ["google"])
        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/google")
        let body = try XCTUnwrap(URLProtocolStub.requestBodies.first ?? nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["idToken"] as? String, "gid-token")
        XCTAssertEqual(json["nonce"] as? String, "raw-n")
    }

    @MainActor
    func test_googleSignIn_withoutProvider_throwsUnavailable() async {
        let sut = makeSUT(responses: [], google: nil)
        do {
            try await sut.authenticateWithGoogleInteractively()
            XCTFail("expected throw")
        } catch let error as AuthError {
            XCTAssertEqual(error, .googleProviderUnavailable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    @MainActor
    func test_linkGoogle_conflict409_mapsToIdentityAlreadyLinked() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "acc", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [.success(body: #"{"error":"identity_already_linked"}"#, status: 409)],
            google: MockGoogleSignInProviding(result: .success(.init(provider: .google, idToken: "gid", providerUid: "g-sub"))),
            store: store
        )
        do {
            try await sut.linkGoogleAccount()
            XCTFail("expected throw")
        } catch let error as AuthError {
            XCTAssertEqual(error, .identityAlreadyLinked)
        }
    }

    @MainActor
    func test_unlink_sendsDelete_andLastIdentity400Maps() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "acc", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [.success(body: #"{"error":"cannot_unlink_last_identity"}"#, status: 400)],
            store: store
        )
        do {
            try await sut.unlink(provider: .apple)
            XCTFail("expected throw")
        } catch let error as AuthError {
            XCTAssertEqual(error, .cannotUnlinkLastIdentity)
        }
        XCTAssertEqual(URLProtocolStub.requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/link/apple")
    }

    @MainActor
    func test_accountUser_decodesLinkedProviders_missingKeyIsNil() throws {
        let withKey = #"{"id":"u","tier":"free","linkedProviders":["apple","google"]}"#
        let without = #"{"id":"u","tier":"free"}"#
        let a = try JSONDecoder.gateway.decode(AccountUser.self, from: Data(withKey.utf8))
        let b = try JSONDecoder.gateway.decode(AccountUser.self, from: Data(without.utf8))
        XCTAssertEqual(a.linkedProviders, ["apple", "google"])
        XCTAssertNil(b.linkedProviders)
    }
}
