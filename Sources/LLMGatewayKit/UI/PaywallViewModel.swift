import Observation

@MainActor
@Observable
public final class PaywallViewModel {
    public private(set) var displayPrice: String?
    public private(set) var displayBillingPeriod: PurchaseBillingPeriod?
    public private(set) var purchaseState: PurchaseState = .idle

    private let subscriptionService: SubscriptionService

    public init(subscriptionService: SubscriptionService) {
        self.subscriptionService = subscriptionService
        self.displayPrice = subscriptionService.displayPrice
        self.displayBillingPeriod = subscriptionService.displayBillingPeriod
        self.purchaseState = subscriptionService.purchaseState
    }

    public func loadProducts() async {
        await subscriptionService.loadProducts()
        refresh()
    }

    public func purchase() async {
        await subscriptionService.purchase()
        refresh()
    }

    public func restore() async {
        await subscriptionService.restore()
        refresh()
    }

    private func refresh() {
        displayPrice = subscriptionService.displayPrice
        displayBillingPeriod = subscriptionService.displayBillingPeriod
        purchaseState = subscriptionService.purchaseState
    }
}
