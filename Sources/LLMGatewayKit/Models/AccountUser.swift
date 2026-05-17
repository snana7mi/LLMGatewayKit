import Foundation

public struct AccountUser: Codable, Equatable, Sendable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let tier: String
    public let tierExpiresAt: String?
    public let createdAt: String?
    public let avatarURL: String?

    public init(
        id: String,
        email: String?,
        displayName: String?,
        tier: String,
        tierExpiresAt: String?,
        createdAt: String?,
        avatarURL: String?
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.tier = tier
        self.tierExpiresAt = tierExpiresAt
        self.createdAt = createdAt
        self.avatarURL = avatarURL
    }
}
