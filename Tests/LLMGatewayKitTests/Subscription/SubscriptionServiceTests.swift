import XCTest
@testable import LLMGatewayKit

final class SubscriptionServiceTests: XCTestCase {
    @MainActor
    func test_purchase_requiresLogin() async {
        let auth = makeLoggedOutAuth()
        let sut = SubscriptionService(authService: auth, config: TestConfig.make(), purchaseClient: NoopPurchaseClient())

        await sut.purchase()

        if case .failed = sut.purchaseState { return }
        XCTFail("Expected .failed, got \(sut.purchaseState)")
    }

    @MainActor
    func test_loadProducts_usesFirstPackagePrice() async {
        let sut = SubscriptionService(
            authService: makeLoggedOutAuth(),
            config: TestConfig.make(),
            purchaseClient: StaticPurchaseClient(offering: .init(packages: [.init(id: "monthly", localizedPrice: "$4.99")]))
        )

        await sut.loadProducts()

        XCTAssertEqual(sut.displayPrice, "$4.99")
    }
}

struct StaticPurchaseClient: PurchaseClient {
    var offering: PurchaseOffering?

    func currentOffering() async throws -> PurchaseOffering? {
        offering
    }

    func purchase(_ package: PurchasePackage) async throws -> PurchaseResult {
        .init(userCancelled: false, entitlementIDs: ["pro"])
    }

    func restore() async throws -> PurchaseCustomerInfo {
        .init(activeEntitlementIDs: ["pro"])
    }

    func customerInfoStream() -> AsyncStream<PurchaseCustomerInfo> {
        AsyncStream { $0.finish() }
    }
}
