import Foundation

public struct UsageInfo: Codable, Equatable, Sendable {
    public let budgetUsed: Int
    public let budgetLimit: Int
    public let percentage: Double
    public let resetsAt: String?
    public let tier: String
    public let breakdown: [UsageBreakdown]

    public init(
        budgetUsed: Int,
        budgetLimit: Int,
        percentage: Double,
        resetsAt: String?,
        tier: String,
        breakdown: [UsageBreakdown]
    ) {
        self.budgetUsed = budgetUsed
        self.budgetLimit = budgetLimit
        self.percentage = percentage
        self.resetsAt = resetsAt
        self.tier = tier
        self.breakdown = breakdown
    }

    public var formattedBudgetUsed: String {
        Self.formatMicroUSD(budgetUsed)
    }

    public var formattedBudgetLimit: String {
        Self.formatMicroUSD(budgetLimit)
    }

    private static func formatMicroUSD(_ value: Int) -> String {
        String(format: "$%.2f", Double(value) / 1_000_000.0)
    }
}

public struct UsageBreakdown: Codable, Equatable, Sendable {
    public let appId: String
    public let callCount: Int
    public let costUsed: Int

    public init(appId: String, callCount: Int, costUsed: Int) {
        self.appId = appId
        self.callCount = callCount
        self.costUsed = costUsed
    }
}
