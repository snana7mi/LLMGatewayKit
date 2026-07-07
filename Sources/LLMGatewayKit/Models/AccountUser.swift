import Foundation

public struct AccountUser: Codable, Equatable, Sendable {
    public let id: String
    public let email: String?
    public let displayName: String?
    public let tier: String
    public let tierExpiresAt: String?
    public let createdAt: String?
    public let avatarURL: String?
    public let memberNo: Int?
    public let bio: String?
    /// 已绑定的登录 provider（"apple"/"google"）；旧网关响应无此字段 → nil
    public let linkedProviders: [String]?

    public init(
        id: String,
        email: String?,
        displayName: String?,
        tier: String,
        tierExpiresAt: String?,
        createdAt: String?,
        avatarURL: String?,
        memberNo: Int? = nil,
        bio: String? = nil,
        linkedProviders: [String]? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.tier = tier
        self.tierExpiresAt = tierExpiresAt
        self.createdAt = createdAt
        self.avatarURL = avatarURL
        self.memberNo = memberNo
        self.bio = bio
        self.linkedProviders = linkedProviders
    }
}
