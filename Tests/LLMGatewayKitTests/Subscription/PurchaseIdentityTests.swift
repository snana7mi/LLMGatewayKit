import XCTest
@testable import LLMGatewayKit

/// 购买身份（RevenueCat logIn）：配了 provider 时购买/恢复前必须切到网关发的 id；没配时保持旧行为。
final class PurchaseIdentityTests: XCTestCase {
    @MainActor
    func test_purchase_logsInWithGatewayIDBeforePurchasing() async throws {
        let client = RecordingPurchaseClient(purchaseCancels: true)
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { "gwu_abc" }
        )

        await sut.purchase()

        XCTAssertEqual(client.calls, ["logIn:gwu_abc", "offering", "purchase:monthly"])
        XCTAssertEqual(sut.purchaseState, .idle)
    }

    @MainActor
    func test_purchase_doesNotBuyWhenIdentityIsUnavailable() async throws {
        let client = RecordingPurchaseClient()
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { throw AuthError.networkError }
        )

        await sut.purchase()

        XCTAssertEqual(client.calls, [])
        XCTAssertEqual(sut.purchaseState, .failed(SubscriptionService.purchaseIdentityUnavailableMessage))
    }

    @MainActor
    func test_purchase_doesNotBuyWhenSDKEndsUpOnAnotherID() async throws {
        let client = RecordingPurchaseClient(activeIDOverride: "$RCAnonymousID:x")
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { "gwu_abc" }
        )

        await sut.purchase()

        XCTAssertEqual(client.calls, ["logIn:gwu_abc"])
        XCTAssertEqual(sut.purchaseState, .failed(SubscriptionService.purchaseIdentityUnavailableMessage))
    }

    @MainActor
    func test_restore_requiresSignInWhenIdentityIsConfigured() async {
        let client = RecordingPurchaseClient()
        let sut = SubscriptionService(
            authService: makeLoggedOutAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { "gwu_abc" }
        )

        await sut.restore()

        XCTAssertEqual(client.calls, [])
        XCTAssertEqual(sut.purchaseState, .failed("Please sign in first"))
    }

    @MainActor
    func test_restore_logsInBeforeRestoring() async throws {
        let client = RecordingPurchaseClient(restoreEntitlements: [])
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { "gwu_abc" }
        )

        await sut.restore()

        XCTAssertEqual(client.calls, ["logIn:gwu_abc", "restore"])
        XCTAssertEqual(sut.purchaseState, .idle)
    }

    @MainActor
    func test_loadProducts_hidesPriceWhenSignedInIdentityFails() async throws {
        let client = RecordingPurchaseClient()
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { throw AuthError.networkError }
        )

        await sut.loadProducts()

        XCTAssertNil(sut.displayPrice)
    }

    @MainActor
    func test_loadProducts_showsPriceAfterIdentity() async throws {
        let client = RecordingPurchaseClient()
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client,
            appUserIDProvider: { "gwu_abc" }
        )

        await sut.loadProducts()

        XCTAssertEqual(sut.displayPrice, "$4.99")
        XCTAssertEqual(client.calls, ["logIn:gwu_abc", "offering"])
    }

    @MainActor
    func test_withoutProvider_neverSwitchesIdentity() async throws {
        let client = RecordingPurchaseClient(purchaseCancels: true)
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: client
        )

        await sut.loadProducts()
        await sut.purchase()

        XCTAssertFalse(client.calls.contains { $0.hasPrefix("logIn") })
    }

    @MainActor
    func test_legacyClientWithoutLogIn_failsHonestly() async throws {
        let sut = SubscriptionService(
            authService: try makeLoggedInSubscriptionAuth(),
            config: TestConfig.make(),
            purchaseClient: StaticPurchaseClient(offering: .init(packages: [.init(id: "m", localizedPrice: "$1")])),
            appUserIDProvider: { "gwu_abc" }
        )

        await sut.purchase()

        XCTAssertEqual(sut.purchaseState, .failed(SubscriptionService.purchaseIdentityUnavailableMessage))
    }

    @MainActor
    func test_fetchRevenueCatAppUserID_readsGatewayEndpoint() async throws {
        URLProtocolStub.reset(responses: [.success(body: #"{"appUserId":"gwu_0123"}"#, status: 200)])
        let auth = try makeLoggedInSubscriptionAuth()

        let id = try await auth.fetchRevenueCatAppUserID()

        XCTAssertEqual(id, "gwu_0123")
        XCTAssertEqual(URLProtocolStub.requests.first?.url?.path, "/account/revenuecat-app-user-id")
        XCTAssertEqual(URLProtocolStub.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }
}

@MainActor
private func makeLoggedInSubscriptionAuth() throws -> AuthService {
    let store = InMemoryTokenStore()
    try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
    let auth = AuthService(
        config: TestConfig.make(),
        tokenStore: store,
        appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
        session: URLSession(configuration: URLProtocolStub.makeConfig())
    )
    auth.restoreSession()
    return auth
}

private final class RecordingPurchaseClient: PurchaseClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private let purchaseCancels: Bool
    private let activeIDOverride: String?
    private let restoreEntitlements: Set<String>

    init(purchaseCancels: Bool = false, activeIDOverride: String? = nil, restoreEntitlements: Set<String> = ["pro"]) {
        self.purchaseCancels = purchaseCancels
        self.activeIDOverride = activeIDOverride
        self.restoreEntitlements = restoreEntitlements
    }

    var calls: [String] { lock.withLock { recorded } }
    private func record(_ call: String) { lock.withLock { recorded.append(call) } }

    func currentOffering() async throws -> PurchaseOffering? {
        record("offering")
        return .init(packages: [.init(id: "monthly", localizedPrice: "$4.99")])
    }

    func purchase(_ package: PurchasePackage) async throws -> PurchaseResult {
        record("purchase:\(package.id)")
        return .init(userCancelled: purchaseCancels, entitlementIDs: purchaseCancels ? [] : ["pro"])
    }

    func restore() async throws -> PurchaseCustomerInfo {
        record("restore")
        return .init(activeEntitlementIDs: restoreEntitlements)
    }

    func logIn(appUserID: String) async throws -> String {
        record("logIn:\(appUserID)")
        return activeIDOverride ?? appUserID
    }

    func customerInfoStream() -> AsyncStream<PurchaseCustomerInfo> {
        AsyncStream { $0.finish() }
    }
}
