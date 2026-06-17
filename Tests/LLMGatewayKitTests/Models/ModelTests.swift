import XCTest
@testable import LLMGatewayKit

final class AccountUserEqualityTests: XCTestCase {
    func test_equality() {
        let a = AccountUser(id: "u1", email: "e@x", displayName: "N", tier: "paid", tierExpiresAt: nil, createdAt: nil, avatarURL: nil)
        let b = AccountUser(id: "u1", email: "e@x", displayName: "N", tier: "paid", tierExpiresAt: nil, createdAt: nil, avatarURL: nil)

        XCTAssertEqual(a, b)
    }
}

final class UsageInfoTests: XCTestCase {
    func test_formattedAmounts() {
        let usage = UsageInfo(budgetUsed: 1_500_000, budgetLimit: 5_000_000, percentage: 30.0, resetsAt: nil, tier: "paid", breakdown: [])

        XCTAssertEqual(usage.formattedBudgetUsed, "$1.50")
        XCTAssertEqual(usage.formattedBudgetLimit, "$5.00")
    }
}
