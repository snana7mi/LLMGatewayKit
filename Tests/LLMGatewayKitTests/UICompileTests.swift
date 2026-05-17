import SwiftUI
import XCTest
@testable import LLMGatewayKit

final class UICompileTests: XCTestCase {
    @MainActor
    func test_profileInitial_usesFirstCharacter() {
        XCTAssertEqual(ProfileView.initial(from: "SnapKei"), "S")
    }

    @MainActor
    func test_paywallView_canBeConstructed() {
        let auth = makeLoggedOutAuth()
        let subscription = SubscriptionService(authService: auth, config: TestConfig.make(), purchaseClient: NoopPurchaseClient())
        let view = PaywallView(config: TestConfig.make(), viewModel: PaywallViewModel(subscriptionService: subscription))

        XCTAssertNotNil(view.body as Any)
    }
}
