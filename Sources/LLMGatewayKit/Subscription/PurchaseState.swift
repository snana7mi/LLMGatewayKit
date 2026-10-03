public enum PurchaseState: Equatable, Sendable {
    case idle
    case purchasing
    case verifying
    case success
    case failed(String)
}

/// 自动续订商品多久扣一次费，例如「1 个月」「3 个月」「1 年」。
/// 只描述周期；金额仍以商店格式化好的 `localizedPrice` 为准。
public struct PurchaseBillingPeriod: Equatable, Sendable {
    public enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
    }

    public let value: Int
    public let unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }
}

public struct PurchasePackage: Equatable, Identifiable, Sendable {
    public let id: String
    public let localizedPrice: String
    /// 非订阅商品或商店没给周期时为 nil。
    public let billingPeriod: PurchaseBillingPeriod?

    public init(id: String, localizedPrice: String, billingPeriod: PurchaseBillingPeriod? = nil) {
        self.id = id
        self.localizedPrice = localizedPrice
        self.billingPeriod = billingPeriod
    }
}

public struct PurchaseOffering: Equatable, Sendable {
    public let packages: [PurchasePackage]

    public init(packages: [PurchasePackage]) {
        self.packages = packages
    }
}

public struct PurchaseCustomerInfo: Equatable, Sendable {
    public let activeEntitlementIDs: Set<String>

    public init(activeEntitlementIDs: Set<String>) {
        self.activeEntitlementIDs = activeEntitlementIDs
    }

    public func hasActiveEntitlement(_ entitlementID: String) -> Bool {
        activeEntitlementIDs.contains(entitlementID)
    }
}

public struct PurchaseResult: Equatable, Sendable {
    public let userCancelled: Bool
    public let entitlementIDs: Set<String>

    public init(userCancelled: Bool, entitlementIDs: Set<String>) {
        self.userCancelled = userCancelled
        self.entitlementIDs = entitlementIDs
    }
}
