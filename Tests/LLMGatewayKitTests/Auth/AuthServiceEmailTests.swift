import XCTest
@testable import LLMGatewayKit

final class AuthServiceEmailTests: XCTestCase {
    @MainActor
    private func makeSUT(
        responses: [URLProtocolStub.Response],
        store: InMemoryTokenStore = InMemoryTokenStore()
    ) -> AuthService {
        URLProtocolStub.reset(responses: responses)
        return AuthService(
            config: TestConfig.make(),
            tokenStore: store,
            appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
            session: URLSession(configuration: URLProtocolStub.makeConfig()),
            googleProvider: nil
        )
    }

    // MARK: - Error mapping

    @MainActor
    func test_verify_400_invalidCode_mapsToEmailCodeInvalid() async {
        let sut = makeSUT(responses: [.success(body: #"{"error":"email_code_invalid"}"#, status: 400)])
        await assertThrows(.emailCodeInvalid) {
            try await sut.signInWithEmailCode(email: "a@x.com", code: "000000")
        }
    }

    @MainActor
    func test_verify_400_expired_mapsToEmailCodeExpired() async {
        let sut = makeSUT(responses: [.success(body: #"{"error":"email_code_expired"}"#, status: 400)])
        await assertThrows(.emailCodeExpired) {
            try await sut.signInWithEmailCode(email: "a@x.com", code: "000000")
        }
    }

    @MainActor
    func test_verify_400_tooMany_mapsToTooManyAttempts() async {
        let sut = makeSUT(responses: [.success(body: #"{"error":"email_too_many_attempts"}"#, status: 400)])
        await assertThrows(.emailTooManyAttempts) {
            try await sut.signInWithEmailCode(email: "a@x.com", code: "000000")
        }
    }

    @MainActor
    func test_verify_400_invalidEmail_mapsToInvalidEmail() async {
        let sut = makeSUT(responses: [.success(body: #"{"error":"invalid_email"}"#, status: 400)])
        await assertThrows(.invalidEmail) {
            try await sut.signInWithEmailCode(email: "invalid", code: "000000")
        }
    }

    @MainActor
    func test_start_429_mapsToRateLimited() async {
        let sut = makeSUT(responses: [.success(body: #"{"error":"rate_limited"}"#, status: 429)])
        await assertThrows(.emailRateLimited) {
            try await sut.startEmailCode(email: "a@x.com")
        }
    }

    @MainActor
    func test_start_networkFailure_mapsToNetworkError() async {
        let sut = makeSUT(responses: [.failure(URLError(.notConnectedToInternet))])
        await assertThrows(.networkError) {
            try await sut.startEmailCode(email: "a@x.com")
        }
    }

    // MARK: - Public email login

    @MainActor
    func test_startEmailCode_postsRawEmailAndLocale() async throws {
        let sut = makeSUT(responses: [.success(body: #"{"sent":true}"#, status: 200)])
        try await sut.startEmailCode(email: "  Me@X.com ", locale: "ja-JP")

        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/email/start")
        let body = try XCTUnwrap(URLProtocolStub.requestBodies.first ?? nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["email"] as? String, "  Me@X.com ")
        XCTAssertEqual(json["locale"] as? String, "ja-JP")
    }

    @MainActor
    func test_signInWithEmailCode_success_storesTokensAndUser() async throws {
        let store = InMemoryTokenStore()
        let sut = makeSUT(
            responses: [
                .success(
                    body: #"{"accessToken":"acc","refreshToken":"ref","user":{"id":"u","email":"log@x.com","tier":"free","linkedProviders":["email"]}}"#,
                    status: 200
                ),
                .success(
                    body: #"{"user":{"id":"u","email":"log@x.com","tier":"free","linkedProviders":["email"]}}"#,
                    status: 200
                ),
            ],
            store: store
        )

        try await sut.signInWithEmailCode(email: "log@x.com", code: "123456")

        XCTAssertTrue(sut.isLoggedIn)
        XCTAssertEqual(try store.loadAccessToken(), "acc")
        XCTAssertEqual(try store.loadRefreshToken(), "ref")
        XCTAssertEqual(sut.currentUser?.email, "log@x.com")
        XCTAssertEqual(sut.currentUser?.linkedProviders, ["email"])
        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/email/verify")
        let body = try XCTUnwrap(URLProtocolStub.requestBodies.first ?? nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["email"] as? String, "log@x.com")
        XCTAssertEqual(json["code"] as? String, "123456")
        XCTAssertEqual(json["deviceName"] as? String, "Test Device")
        XCTAssertEqual(json["appId"] as? String, "test-app")
    }

    // MARK: - Email linking

    @MainActor
    func test_startLinkEmailCode_sendsBearerAndRawEmail() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "acc", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [.success(body: #"{"sent":true}"#, status: 200)],
            store: store
        )

        try await sut.startLinkEmailCode(email: " Bind@X.com ", locale: "zh-Hans")

        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/link/email/start")
        XCTAssertEqual(
            URLProtocolStub.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer acc"
        )
        let body = try XCTUnwrap(URLProtocolStub.requestBodies.first ?? nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["email"] as? String, " Bind@X.com ")
        XCTAssertEqual(json["locale"] as? String, "zh-Hans")
    }

    @MainActor
    func test_startLinkEmailCode_401_refreshesBearerAndRetries() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "old", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [
                .success(body: #"{"error":"expired"}"#, status: 401),
                .success(body: #"{"accessToken":"new","refreshToken":"ref2","expiresIn":900}"#, status: 200),
                .success(body: #"{"sent":true}"#, status: 200),
            ],
            store: store
        )

        try await sut.startLinkEmailCode(email: "bind@x.com")

        XCTAssertEqual(URLProtocolStub.requests.map(\.url?.path), [
            "/auth/link/email/start", "/auth/refresh", "/auth/link/email/start",
        ])
        XCTAssertEqual(
            URLProtocolStub.requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer new"
        )
    }

    @MainActor
    func test_startLinkEmailCode_409_mapsToIdentityAlreadyLinked() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "acc", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [.success(body: #"{"error":"identity_already_linked"}"#, status: 409)],
            store: store
        )

        await assertThrows(.identityAlreadyLinked) {
            try await sut.startLinkEmailCode(email: "taken@x.com")
        }
    }

    @MainActor
    func test_linkEmail_success_refetchesAccount() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "acc", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [
                .success(body: #"{"linkedProviders":["apple","email"]}"#, status: 200),
                .success(
                    body: #"{"user":{"id":"u","email":"bind@x.com","tier":"free","linkedProviders":["apple","email"]}}"#,
                    status: 200
                ),
            ],
            store: store
        )

        try await sut.linkEmail(email: "bind@x.com", code: "123456")

        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/link/email")
        XCTAssertEqual(
            URLProtocolStub.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer acc"
        )
        let body = try XCTUnwrap(URLProtocolStub.requestBodies.first ?? nil)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["email"] as? String, "bind@x.com")
        XCTAssertEqual(json["code"] as? String, "123456")
        XCTAssertEqual(sut.currentUser?.linkedProviders, ["apple", "email"])
        XCTAssertEqual(sut.currentUser?.email, "bind@x.com")
    }

    @MainActor
    func test_unlinkEmail_reusesDeleteProviderPath() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "acc", refreshToken: "ref", expiry: Date().addingTimeInterval(600))
        let sut = makeSUT(
            responses: [
                .success(body: #"{"linkedProviders":["apple"]}"#, status: 200),
                .success(
                    body: #"{"user":{"id":"u","email":null,"tier":"free","linkedProviders":["apple"]}}"#,
                    status: 200
                ),
            ],
            store: store
        )

        try await sut.unlink(provider: .email)

        XCTAssertEqual(URLProtocolStub.requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/auth/link/email")
        XCTAssertNil(sut.currentUser?.email)
        XCTAssertEqual(sut.currentUser?.linkedProviders, ["apple"])
    }

    @MainActor
    private func assertThrows(
        _ expected: AuthError,
        _ body: @MainActor () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected throw")
        } catch let error as AuthError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
