import Foundation
import Observation
#if canImport(RevenueCat)
import RevenueCat
#endif

public protocol PurchaseClient: Sendable {
    func currentOffering() async throws -> PurchaseOffering?
    func purchase(_ package: PurchasePackage) async throws -> PurchaseResult
    func restore() async throws -> PurchaseCustomerInfo
    func customerInfoStream() -> AsyncStream<PurchaseCustomerInfo>
}

public struct LivePurchaseClient: PurchaseClient {
    private let apiKey: String?

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
        #if canImport(RevenueCat)
        if let apiKey, !apiKey.isEmpty {
            Purchases.configure(withAPIKey: apiKey)
        }
        #endif
    }

    public func currentOffering() async throws -> PurchaseOffering? {
        #if canImport(RevenueCat)
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else { return nil }
        return PurchaseOffering(
            packages: current.availablePackages.map {
                PurchasePackage(id: $0.identifier, localizedPrice: $0.storeProduct.localizedPriceString)
            }
        )
        #else
        throw AuthError.serverError("RevenueCat unavailable")
        #endif
    }

    public func purchase(_ package: PurchasePackage) async throws -> PurchaseResult {
        #if canImport(RevenueCat)
        guard let revenueCatPackage = try await findPackage(id: package.id) else {
            throw AuthError.serverError("Package not found")
        }
        let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: revenueCatPackage)
        return PurchaseResult(userCancelled: userCancelled, entitlementIDs: Set(customerInfo.entitlements.active.keys))
        #else
        throw AuthError.serverError("RevenueCat unavailable")
        #endif
    }

    public func restore() async throws -> PurchaseCustomerInfo {
        #if canImport(RevenueCat)
        let info = try await Purchases.shared.restorePurchases()
        return PurchaseCustomerInfo(activeEntitlementIDs: Set(info.entitlements.active.keys))
        #else
        throw AuthError.serverError("RevenueCat unavailable")
        #endif
    }

    public func customerInfoStream() -> AsyncStream<PurchaseCustomerInfo> {
        #if canImport(RevenueCat)
        AsyncStream { continuation in
            Task {
                for await info in Purchases.shared.customerInfoStream {
                    continuation.yield(PurchaseCustomerInfo(activeEntitlementIDs: Set(info.entitlements.active.keys)))
                }
                continuation.finish()
            }
        }
        #else
        AsyncStream { $0.finish() }
        #endif
    }

    #if canImport(RevenueCat)
    private func findPackage(id: String) async throws -> Package? {
        let offerings = try await Purchases.shared.offerings()
        return offerings.current?.availablePackages.first { $0.identifier == id }
    }
    #endif
}

public struct NoopPurchaseClient: PurchaseClient {
    public init() {}

    public func currentOffering() async throws -> PurchaseOffering? {
        nil
    }

    public func purchase(_ package: PurchasePackage) async throws -> PurchaseResult {
        throw AuthError.serverError("Purchases are not configured")
    }

    public func restore() async throws -> PurchaseCustomerInfo {
        throw AuthError.serverError("Purchases are not configured")
    }

    public func customerInfoStream() -> AsyncStream<PurchaseCustomerInfo> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
@Observable
public final class SubscriptionService {
    public private(set) var displayPrice: String?
    public private(set) var purchaseState: PurchaseState = .idle

    private let authService: AuthService
    private let config: LLMGatewayKitConfig
    private let client: any PurchaseClient
    private var listeningTask: Task<Void, Never>?

    public init(
        authService: AuthService,
        config: LLMGatewayKitConfig,
        purchaseClient: (any PurchaseClient)? = nil
    ) {
        self.authService = authService
        self.config = config
        self.client = purchaseClient ?? (config.revenueCatAPIKey.map { LivePurchaseClient(apiKey: $0) } ?? NoopPurchaseClient())
    }

    public func startListening() {
        stopListening()
        let stream = client.customerInfoStream()
        listeningTask = Task { [weak self] in
            for await info in stream {
                guard let self else { return }
                await self.handleCustomerInfo(info)
            }
        }
    }

    public func stopListening() {
        listeningTask?.cancel()
        listeningTask = nil
    }

    public func loadProducts() async {
        do {
            displayPrice = try await client.currentOffering()?.packages.first?.localizedPrice
        } catch {
            displayPrice = nil
        }
    }

    public func purchase() async {
        guard authService.isLoggedIn else {
            purchaseState = .failed("Please sign in first")
            return
        }

        do {
            guard let package = try await client.currentOffering()?.packages.first else {
                purchaseState = .failed("No subscription product is available")
                return
            }
            purchaseState = .purchasing
            let result = try await client.purchase(package)
            if result.userCancelled {
                purchaseState = .idle
                return
            }
            purchaseState = .verifying
            purchaseState = await waitForTierSync() ? .success : .failed("Sync timeout")
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    public func restore() async {
        do {
            purchaseState = .verifying
            let info = try await client.restore()
            guard info.hasActiveEntitlement(config.entitlementID) else {
                purchaseState = .idle
                return
            }
            guard authService.isLoggedIn else {
                purchaseState = .failed("Restore successful. Please sign in to activate paid features.")
                return
            }
            purchaseState = await waitForTierSync() ? .success : .failed("Sync timeout")
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    private func handleCustomerInfo(_ info: PurchaseCustomerInfo) async {
        let active = info.hasActiveEntitlement(config.entitlementID)
        let currentTier = authService.currentUser?.tier ?? "free"
        if (active && currentTier != "paid") || (!active && currentTier == "paid") {
            try? await authService.fetchAccount()
        }
    }

    private func waitForTierSync() async -> Bool {
        for _ in 0..<5 {
            try? await Task.sleep(for: .seconds(1))
            try? await authService.fetchAccount()
            if authService.currentUser?.tier == "paid" {
                return true
            }
        }
        return false
    }
}
