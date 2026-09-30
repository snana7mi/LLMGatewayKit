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
    /// 把后续购买/恢复挂到指定 app user id 上，返回切换后 SDK 实际使用的 id。
    /// 只有 `SubscriptionService` 配了 `appUserIDProvider` 才会调用。
    func logIn(appUserID: String) async throws -> String
}

extension PurchaseClient {
    /// 旧的自定义实现（SnapKei/ConchTalk 测试替身等）不认识身份切换；默认明确失败，绝不假装已切换。
    public func logIn(appUserID: String) async throws -> String {
        throw AuthError.serverError(SubscriptionService.purchaseIdentityUnavailableMessage)
    }
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

    public func logIn(appUserID: String) async throws -> String {
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else {
            throw AuthError.serverError("Purchases are not configured")
        }
        if Purchases.shared.appUserID != appUserID {
            _ = try await Purchases.shared.logIn(appUserID)
        }
        return Purchases.shared.appUserID
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

    public func logIn(appUserID: String) async throws -> String {
        throw AuthError.serverError("Purchases are not configured")
    }

    public func customerInfoStream() -> AsyncStream<PurchaseCustomerInfo> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
@Observable
public final class SubscriptionService {
    /// 拿不到或切不到购买身份时的固定失败句（与其它失败句一样由 App 自行翻译）。
    public nonisolated static let purchaseIdentityUnavailableMessage = "Purchase identity unavailable"

    /// 网关为当前账号发放的 RevenueCat app user id（`GET /account/revenuecat-app-user-id`）。
    public typealias AppUserIDProvider = @MainActor @Sendable () async throws -> String

    public private(set) var displayPrice: String?
    public private(set) var purchaseState: PurchaseState = .idle

    private let authService: AuthService
    private let config: LLMGatewayKitConfig
    private let client: any PurchaseClient
    private let appUserIDProvider: AppUserIDProvider?
    private var listeningTask: Task<Void, Never>?

    /// - Parameter appUserIDProvider: 传入后，每次取价格/购买/恢复前都先 `logIn` 到这个 id，
    ///   让 webhook 能把商店事件对回网关账号（Google/邮箱账号没有 apple_sub）；取不到 id 就不卖。
    ///   不传（SnapKei/ConchTalk 现状）保持原行为：不做身份切换。
    public init(
        authService: AuthService,
        config: LLMGatewayKitConfig,
        purchaseClient: (any PurchaseClient)? = nil,
        appUserIDProvider: AppUserIDProvider? = nil
    ) {
        self.authService = authService
        self.config = config
        self.client = purchaseClient ?? (config.revenueCatAPIKey.map { LivePurchaseClient(apiKey: $0) } ?? NoopPurchaseClient())
        self.appUserIDProvider = appUserIDProvider
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
            // 已登录却对不上购买身份：这次买了也归不到账号上，干脆不给价格（页面显示「买不了」）。
            if appUserIDProvider != nil, authService.isLoggedIn {
                try await identifyPurchaser()
            }
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
            try await identifyPurchaser()
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
        } catch is PurchaseIdentityUnavailable {
            purchaseState = .failed(Self.purchaseIdentityUnavailableMessage)
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    public func restore() async {
        // 配了身份时必须先登录：匿名 id 上恢复会把订阅从账号的 id 上转走，之后的续费事件就对不上人了。
        if appUserIDProvider != nil, !authService.isLoggedIn {
            purchaseState = .failed("Please sign in first")
            return
        }
        do {
            purchaseState = .verifying
            try await identifyPurchaser()
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
        } catch is PurchaseIdentityUnavailable {
            purchaseState = .failed(Self.purchaseIdentityUnavailableMessage)
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    private struct PurchaseIdentityUnavailable: Error {}

    /// 没配 provider 时什么也不做（旧行为）。配了就要求 SDK 最终使用的 id 与网关发的完全一致。
    private func identifyPurchaser() async throws {
        guard let appUserIDProvider else { return }
        let appUserID: String
        do {
            appUserID = try await appUserIDProvider()
        } catch {
            throw PurchaseIdentityUnavailable()
        }
        guard !appUserID.isEmpty else { throw PurchaseIdentityUnavailable() }
        let active: String
        do {
            active = try await client.logIn(appUserID: appUserID)
        } catch is AuthError {
            // 未配置 / 旧客户端不支持切换：同样视为拿不到身份。RevenueCat 自己的错误（网络等）原样上抛。
            throw PurchaseIdentityUnavailable()
        }
        guard active == appUserID else { throw PurchaseIdentityUnavailable() }
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
