import XCTest
@testable import LLMGatewayKit

final class LLMGatewayKitConfigTests: XCTestCase {
    func test_initStoresProperties() {
        let config = LLMGatewayKitConfig(
            baseURL: URL(string: "https://api.conch-talk.com")!,
            entitlementID: "pro",
            appDisplayName: "SnapKei",
            companionAppNames: ["ConchTalk"],
            revenueCatAPIKey: "key_abc",
            paywallFeatures: [.init(id: "f1", icon: "star", title: "Feature 1", subtitle: nil)],
            deviceName: "TestDevice"
        )

        XCTAssertEqual(config.entitlementID, "pro")
        XCTAssertEqual(config.companionAppNames, ["ConchTalk"])
        XCTAssertEqual(config.paywallFeatures.first?.title, "Feature 1")
    }
}
