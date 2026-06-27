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

    // MARK: - Refresh resilience: only an authoritative 401 may destroy the session
    // 反复登陆根因：临时失败（网络抖动/5xx/解析）不得清 token；只有服务端权威 401 才登出。

    @MainActor
    func test_refresh_networkError_preservesSession() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "old", refreshToken: "ref", expiry: Date().addingTimeInterval(30))
        URLProtocolStub.reset(responses: [.failure(URLError(.notConnectedToInternet))])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        do {
            _ = try await sut.validAccessToken()
            XCTFail("expected a transient error")
        } catch AuthError.networkError {
            // expected: transient → session must survive
        } catch {
            XCTFail("expected networkError, got \(error)")
        }

        XCTAssertTrue(sut.isLoggedIn, "a network blip during refresh must NOT log the user out")
        XCTAssertEqual(try store.loadAccessToken(), "old")
        XCTAssertEqual(try store.loadRefreshToken(), "ref")
    }

    @MainActor
    func test_refresh_serverError5xx_preservesSession() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "old", refreshToken: "ref", expiry: Date().addingTimeInterval(30))
        URLProtocolStub.reset(responses: [.success(body: #"{"error":"upstream unavailable"}"#, status: 503)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        do {
            _ = try await sut.validAccessToken()
            XCTFail("expected a transient error")
        } catch AuthError.networkError {
            // expected: 5xx is transient → session must survive
        } catch {
            XCTFail("expected networkError, got \(error)")
        }

        XCTAssertTrue(sut.isLoggedIn, "a transient 5xx during refresh must NOT log the user out")
        XCTAssertEqual(try store.loadRefreshToken(), "ref")
    }

    @MainActor
    func test_refresh_401_logsOut() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "old", refreshToken: "ref", expiry: Date().addingTimeInterval(30))
        URLProtocolStub.reset(responses: [.success(body: #"{"error":"Session revoked or not found"}"#, status: 401)])
        let sut = AuthService(config: TestConfig.make(), tokenStore: store,
                              appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
                              session: URLSession(configuration: URLProtocolStub.makeConfig()))
        sut.restoreSession()

        do {
            _ = try await sut.validAccessToken()
            XCTFail("expected session expiry")
        } catch AuthError.sessionExpired {
            // expected: authoritative rejection → log out
        } catch {
            XCTFail("expected sessionExpired, got \(error)")
        }

        XCTAssertFalse(sut.isLoggedIn, "an authoritative 401 must log the user out")
        XCTAssertNil(try store.loadRefreshToken())
    }

    @MainActor
    func test_restoreSession_keychainReadError_keepsPriorLogin() {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("sub-x", forKey: AuthService.Keys.cachedAppleSub)   // evidence of a prior successful login

        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: ThrowingTokenStore(),
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: AccountProfileCache(defaults: defaults)
        )

        sut.restoreSession()

        XCTAssertTrue(sut.isLoggedIn, "a transient keychain read error (e.g. locked device) must NOT be treated as logged out")
    }

    @MainActor
    func test_restoreSession_absentTokens_isLoggedOut() {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("sub-x", forKey: AuthService.Keys.cachedAppleSub)

        let sut = AuthService(
            config: TestConfig.make(),
            tokenStore: InMemoryTokenStore(),   // empty: loads return nil (not throw)
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults,
            profileCache: AccountProfileCache(defaults: defaults)
        )

        sut.restoreSession()

        XCTAssertFalse(sut.isLoggedIn, "genuinely absent tokens (nil, not an error) means logged out")
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

    @MainActor
    func test_authenticateInteractively_forwardsFullNameAsDisplayName() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        URLProtocolStub.reset(responses: [.success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free"}}"#, status: 200)])
        let bridge = MockAppleSignInBridge(result: .success(.init(identityToken: "raw", appleUserId: "sub", fullName: "Taro Tanaka")))
        let sut = AuthService(config: TestConfig.make(), tokenStore: InMemoryTokenStore(), appleBridge: bridge, session: URLSession(configuration: URLProtocolStub.makeConfig()), defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))

        try await sut.authenticateInteractively()

        let idx = try XCTUnwrap(URLProtocolStub.requests.firstIndex(where: { $0.url?.path.hasSuffix("/auth/apple") == true }))
        let bodyData = try XCTUnwrap(URLProtocolStub.requestBodies[idx])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(json["displayName"] as? String, "Taro Tanaka")
    }

    @MainActor
    func test_authenticateInteractively_nilFullName_omitsDisplayName() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        URLProtocolStub.reset(responses: [.success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free"}}"#, status: 200)])
        let bridge = MockAppleSignInBridge(result: .success(.init(identityToken: "raw", appleUserId: "sub", fullName: nil)))
        let sut = AuthService(config: TestConfig.make(), tokenStore: InMemoryTokenStore(), appleBridge: bridge, session: URLSession(configuration: URLProtocolStub.makeConfig()), defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))

        try await sut.authenticateInteractively()

        let idx = try XCTUnwrap(URLProtocolStub.requests.firstIndex(where: { $0.url?.path.hasSuffix("/auth/apple") == true }))
        let bodyData = try XCTUnwrap(URLProtocolStub.requestBodies[idx])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNil(json["displayName"])
    }

    // MARK: - Apple's once-only full name: persist on capture + replay until the server has it
    // Apple delivers credential.fullName only on the FIRST authorization per Apple-ID/app-group.
    // The SDK must persist it the instant it arrives (before the fallible POST) and replay it on
    // later sign-ins until the gateway has a name, so a transient failure never loses it forever.

    @MainActor
    func test_authenticate_persistsFullName_andReplaysAfterFailedPost() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // First attempt: Apple delivered the once-only name, but the /auth/apple POST fails.
        URLProtocolStub.reset(responses: [.failure(URLError(.timedOut))])
        let first = AuthService(
            config: TestConfig.make(), tokenStore: InMemoryTokenStore(),
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))
        do {
            try await first.authenticate(identityToken: Data("t".utf8), fullName: "Taro Tanaka", appleSub: "sub")
            XCTFail("expected the failed POST to throw")
        } catch { /* expected: transient failure */ }

        // Relaunch + retry: Apple no longer provides the name (group already authorized).
        URLProtocolStub.reset(responses: [
            .success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free"}}"#, status: 200),
            .success(body: #"{"user":{"id":"u","tier":"free"}}"#, status: 200),   // fetchAccount
        ])
        let second = AuthService(
            config: TestConfig.make(), tokenStore: InMemoryTokenStore(),
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))
        try await second.authenticate(identityToken: Data("t".utf8), fullName: nil, appleSub: "sub")

        let idx = try XCTUnwrap(URLProtocolStub.requests.firstIndex(where: { $0.url?.path.hasSuffix("/auth/apple") == true }))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.requestBodies[idx])) as? [String: Any])
        XCTAssertEqual(body["displayName"] as? String, "Taro Tanaka", "the once-only Apple name must be replayed after a failed first POST")
    }

    @MainActor
    func test_authenticate_doesNotReplay_afterServerHasName() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // First sign-in: name captured AND the server stores & returns it.
        URLProtocolStub.reset(responses: [
            .success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free","displayName":"Taro Tanaka"}}"#, status: 200),
            .success(body: #"{"user":{"id":"u","tier":"free","displayName":"Taro Tanaka"}}"#, status: 200),
        ])
        let sut = AuthService(
            config: TestConfig.make(), tokenStore: InMemoryTokenStore(),
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))
        try await sut.authenticate(identityToken: Data("t".utf8), fullName: "Taro Tanaka", appleSub: "sub")

        // Later sign-in, Apple gives no name: nothing to replay (server already has one).
        URLProtocolStub.reset(responses: [
            .success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u","tier":"free","displayName":"Taro Tanaka"}}"#, status: 200),
            .success(body: #"{"user":{"id":"u","tier":"free","displayName":"Taro Tanaka"}}"#, status: 200),
        ])
        try await sut.authenticate(identityToken: Data("t".utf8), fullName: nil, appleSub: "sub")

        let idx = try XCTUnwrap(URLProtocolStub.requests.firstIndex(where: { $0.url?.path.hasSuffix("/auth/apple") == true }))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.requestBodies[idx])) as? [String: Any])
        XCTAssertNil(body["displayName"], "once the server has a name, the SDK should stop replaying")
    }

    @MainActor
    func test_authenticate_pendingNameIsKeyedByAppleSub() async throws {
        let suiteName = "LLMGatewayKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // subA captured a name but the POST failed → pending stored for subA only.
        URLProtocolStub.reset(responses: [.failure(URLError(.timedOut))])
        let a = AuthService(
            config: TestConfig.make(), tokenStore: InMemoryTokenStore(),
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))
        _ = try? await a.authenticate(identityToken: Data("t".utf8), fullName: "Taro Tanaka", appleSub: "subA")

        // A different Apple user signs in with no name → must NOT inherit subA's pending name.
        URLProtocolStub.reset(responses: [
            .success(body: #"{"accessToken":"a","refreshToken":"r","user":{"id":"u2","tier":"free"}}"#, status: 200),
            .success(body: #"{"user":{"id":"u2","tier":"free"}}"#, status: 200),
        ])
        let b = AuthService(
            config: TestConfig.make(), tokenStore: InMemoryTokenStore(),
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            defaults: defaults, profileCache: AccountProfileCache(defaults: defaults))
        try await b.authenticate(identityToken: Data("t".utf8), fullName: nil, appleSub: "subB")

        let idx = try XCTUnwrap(URLProtocolStub.requests.firstIndex(where: { $0.url?.path.hasSuffix("/auth/apple") == true }))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.requestBodies[idx])) as? [String: Any])
        XCTAssertNil(body["displayName"], "a pending name for one Apple sub must not leak to another")
    }
}

/// 模拟 Keychain 读/写抛错（如锁屏时 errSecInteractionNotAllowed -25308），区别于「无 token」(返回 nil)。
private final class ThrowingTokenStore: TokenStoring, @unchecked Sendable {
    func save(accessToken: String, refreshToken: String, expiry: Date) throws {
        throw AuthError.serverError("Keychain add -25308")
    }
    func loadAccessToken() throws -> String? { throw AuthError.serverError("Keychain read -25308") }
    func loadRefreshToken() throws -> String? { throw AuthError.serverError("Keychain read -25308") }
    func loadExpiry() throws -> Date? { throw AuthError.serverError("Keychain read -25308") }
    func clear() throws {}
}
