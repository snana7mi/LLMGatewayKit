public enum PurchaseState: Equatable, Sendable {
    case idle
    case purchasing
    case verifying
    case success
    case failed(String)
}

public struct PurchasePackage: Equatable, Identifiable, Sendable {
    public let id: String
    public let localizedPrice: String

    public init(id: String, localizedPrice: String) {
        self.id = id
        self.localizedPrice = localizedPrice
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
