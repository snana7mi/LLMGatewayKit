import XCTest
@testable import LLMGatewayKit

final class AuthServiceTests: XCTestCase {
    @MainActor
    func test_authenticate_storesTokensAndUser() async throws {
        URLProtocolStub.reset(responses: [.success(body: #"{"accessToken":"acc","refreshToken":"ref","user":{"id":"u","tier":"paid","displayName":"D","email":"e@x"}}"#, status: 200)])
        let store = InMemoryTokenStore()
        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .success(.init(identityToken: "t", appleUserId: "sub"))),
            session: URLSession(configuration: URLProtocolStub.makeConfig())
        )

        try await sut.authenticate(identityToken: Data("rawToken".utf8), fullName: "Full Name", appleSub: "sub")

        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(sut.currentUser?.id, "u")
        XCTAssertEqual(try store.loadAccessToken(), "acc")
        XCTAssertEqual(try store.loadRefreshToken(), "ref")
    }

    @MainActor
    func test_validAccessToken_refreshesWhenNearExpiry() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "old", refreshToken: "ref", expiry: Date().addingTimeInterval(30))
        URLProtocolStub.reset(responses: [.success(body: #"{"accessToken":"new","refreshToken":"ref2"}"#, status: 200)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        let token = try await sut.validAccessToken()

        XCTAssertEqual(token, "new")
        XCTAssertEqual(try store.loadAccessToken(), "new")
    }

    @MainActor
    func test_concurrentRefresh_coalescesIntoOneRequest() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(10))
        URLProtocolStub.reset(responses: [.success(body: #"{"accessToken":"new","refreshToken":"r2"}"#, status: 200)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        async let t1 = sut.validAccessToken()
        async let t2 = sut.validAccessToken()
        let (a, b) = try await (t1, t2)

        XCTAssertEqual(a, "new")
        XCTAssertEqual(b, "new")
        XCTAssertEqual(URLProtocolStub.requests.count, 1)
    }

    @MainActor
    func test_logout_clearsAllState() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        UserDefaults.standard.set("sub", forKey: AuthService.Keys.cachedAppleSub)
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        await sut.logout()

        XCTAssertFalse(sut.isLoggedIn)
        XCTAssertNil(sut.currentUser)
        XCTAssertNil(try store.loadAccessToken())
        XCTAssertNil(UserDefaults.standard.string(forKey: AuthService.Keys.cachedAppleSub))
    }

    @MainActor
    func test_deleteAccount_callsEndpointAndLogsOut() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.reset(responses: [.success(body: #"{"success":true}"#, status: 200)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        try await sut.deleteAccount()

        XCTAssertFalse(sut.isLoggedIn)
    }

    @MainActor
    func test_fetchAccount_populatesUser() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.reset(responses: [.success(body: #"{"user":{"id":"u","email":"e","displayName":"D","tier":"paid","avatarURL":"https://x"},"usage":{"budgetUsed":1,"budgetLimit":10,"percentage":10.0}}"#, status: 200)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        try await sut.fetchAccount()

        XCTAssertEqual(sut.currentUser?.tier, "paid")
        XCTAssertEqual(sut.currentUser?.avatarURL, "https://x")
    }

    @MainActor
    func test_fetchUsage_returnsParsedInfo() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.reset(responses: [.success(body: #"{"budgetUsed":250000,"budgetLimit":1000000,"percentage":25.0,"resetsAt":"2026-06-01T00:00:00Z","tier":"paid","breakdown":[]}"#, status: 200)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        let info = try await sut.fetchUsage()

        XCTAssertEqual(info.percentage, 25.0)
        XCTAssertEqual(info.tier, "paid")
    }

    @MainActor
    func test_uploadAvatar_updatesUserAvatarURL() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.reset(responses: [.success(body: #"{"avatarURL":"https://avatars.x/u.jpg"}"#, status: 200)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()
        sut.updateCurrentUser(.init(id: "u", email: nil, displayName: nil, tier: "paid", tierExpiresAt: nil, createdAt: nil, avatarURL: nil))

        let url = try await sut.uploadAvatar(imageData: Data([0xFF, 0xD8]), mimeType: "image/jpeg")

        XCTAssertEqual(url, "https://avatars.x/u.jpg")
        XCTAssertEqual(sut.currentUser?.avatarURL, url)
    }

    @MainActor
    func test_authenticateInteractively_callsBridgeAndAuthenticate() async throws {
        URLProtocolStub.reset(responses: [.success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free"}}"#, status: 200)])
        let store = InMemoryTokenStore()
        let bridge = MockAppleSignInBridge(result: .success(.init(identityToken: "raw", appleUserId: "sub-x")))
        let sut = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: bridge, session: URLSession(configuration: URLProtocolStub.makeConfig()))

        try await sut.authenticateInteractively()

        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AuthService.Keys.cachedAppleSub), "sub-x")
    }
}
