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

    @MainActor
    func test_restoreSession_loadsPersistedUserAndAvatar() throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let avatarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMGatewayKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: avatarDir) }

        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))

        let user = AccountUser(
            id: "u1", email: "e@x.com", displayName: "Lee", tier: "paid",
            tierExpiresAt: nil, createdAt: nil, avatarURL: "https://cdn.test/a.jpg")
        let avatarData = Data([0xFF, 0xD8, 0xFF])
        let cache = AccountProfileCache(defaults: defaults, avatarDirectory: avatarDir)
        cache.saveUser(user)
        cache.saveAvatar(avatarData, userID: user.id, avatarURL: user.avatarURL!)

        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: cache
        )
        sut.restoreSession()

        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(sut.currentUser?.displayName, "Lee")
        XCTAssertEqual(sut.cachedAvatarData, avatarData)
    }

    @MainActor
    func test_fetchAccount_persistsUserForNextLaunch() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let avatarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMGatewayKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: avatarDir) }

        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        URLProtocolStub.reset(responses: [.success(body: #"{"user":{"id":"u","email":"e","displayName":"D","tier":"paid","avatarURL":"https://x"}}"#, status: 200)])
        let cache = AccountProfileCache(defaults: defaults, avatarDirectory: avatarDir)
        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: cache
        )
        sut.restoreSession()

        try await sut.fetchAccount()

        let relaunched = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: cache
        )
        relaunched.restoreSession()

        XCTAssertEqual(relaunched.currentUser?.tier, "paid")
        XCTAssertEqual(relaunched.currentUser?.avatarURL, "https://x")
    }

    @MainActor
    func test_loadAvatarDataIfNeeded_usesDiskCacheWithoutNetwork() async {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let avatarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMGatewayKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: avatarDir) }

        let store = InMemoryTokenStore()
        try? store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let avatarURL = "https://cdn.test/avatar.jpg"
        let avatarData = Data([0x01, 0x02, 0x03])
        let cache = AccountProfileCache(defaults: defaults, avatarDirectory: avatarDir)
        cache.saveUser(.init(id: "u", email: nil, displayName: nil, tier: "free",
                             tierExpiresAt: nil, createdAt: nil, avatarURL: avatarURL))
        cache.saveAvatar(avatarData, userID: "u", avatarURL: avatarURL)

        URLProtocolStub.reset()
        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: cache
        )
        sut.restoreSession()

        let loaded = await sut.loadAvatarDataIfNeeded()

        XCTAssertEqual(loaded, avatarData)
        XCTAssertTrue(URLProtocolStub.requests.isEmpty)
    }

    @MainActor
    func test_logout_clearsPersistedProfile() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let avatarDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMGatewayKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: avatarDir) }

        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let cache = AccountProfileCache(defaults: defaults, avatarDirectory: avatarDir)
        cache.saveUser(.init(id: "u", email: nil, displayName: "N", tier: "free",
                             tierExpiresAt: nil, createdAt: nil, avatarURL: "https://x"))
        cache.saveAvatar(Data([0xAA]), userID: "u", avatarURL: "https://x")
        defaults.set("sub", forKey: AuthService.Keys.cachedAppleSub)

        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: cache
        )
        sut.restoreSession()

        await sut.logout()

        XCTAssertNil(defaults.data(forKey: AuthService.Keys.cachedAccountUser))
        XCTAssertNil(defaults.string(forKey: AccountProfileCache.Keys.cachedAvatarURL(userID: "u")))
    }

    @MainActor
    func test_updateDisplayName_patchesAndUpdatesCurrentUser() async throws {
        URLProtocolStub.reset(responses: [.success(body: #"{"user":{"id":"u","tier":"free","displayName":"New","memberNo":7}}"#, status: 200)])
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(3600))
        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .success(.init(identityToken: "t", appleUserId: "sub"))),
            session: URLSession(configuration: URLProtocolStub.makeConfig())
        )

        try await sut.updateDisplayName("New")

        XCTAssertEqual(sut.currentUser?.displayName, "New")
        XCTAssertEqual(sut.currentUser?.memberNo, 7)
        let last = URLProtocolStub.requests.last
        XCTAssertEqual(last?.httpMethod, "PATCH")
        XCTAssertEqual(last?.url?.path, "/account")
    }

    @MainActor
    func test_updateBio_patchesAndUpdatesCurrentUser() async throws {
        URLProtocolStub.reset(responses: [.success(body: #"{"user":{"id":"u","tier":"free","displayName":"New","memberNo":7,"bio":"hi"}}"#, status: 200)])
        let store = InMemoryTokenStore()
        try store.save(accessToken: "a", refreshToken: "r", expiry: Date().addingTimeInterval(3600))
        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .success(.init(identityToken: "t", appleUserId: "sub"))),
            session: URLSession(configuration: URLProtocolStub.makeConfig())
        )

        try await sut.updateBio("hi")

        XCTAssertEqual(sut.currentUser?.bio, "hi")
        let last = URLProtocolStub.requests.last
        XCTAssertEqual(last?.httpMethod, "PATCH")
        XCTAssertEqual(last?.url?.path, "/account")
    }

    func test_updateBio_nilSerializesToJSONNull() throws {
        let bio: String? = nil
        let bioValue: Any = bio ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: ["bio": bioValue])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("null"), "expected JSON null for cleared bio, got: \(json)")
    }
}
