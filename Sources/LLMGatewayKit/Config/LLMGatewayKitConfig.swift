import Foundation

public struct LLMGatewayKitConfig: Sendable {
    public let baseURL: URL
    public let entitlementID: String
    public let appDisplayName: String
    public let companionAppNames: [String]
    public let revenueCatAPIKey: String?
    public let paywallFeatures: [PaywallFeature]
    public let deviceName: String

    public init(
        baseURL: URL,
        entitlementID: String,
        appDisplayName: String,
        companionAppNames: [String],
        revenueCatAPIKey: String?,
        paywallFeatures: [PaywallFeature],
        deviceName: String
    ) {
        self.baseURL = baseURL
        self.entitlementID = entitlementID
        self.appDisplayName = appDisplayName
        self.companionAppNames = companionAppNames
        self.revenueCatAPIKey = revenueCatAPIKey
        self.paywallFeatures = paywallFeatures
        self.deviceName = deviceName
    }
}

public struct PaywallFeature: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let icon: String
    public let title: String
    public let subtitle: String?

    public init(id: String, icon: String, title: String, subtitle: String?) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}
