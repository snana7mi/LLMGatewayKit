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
    /// 已绑定的登录 provider（"apple"/"google"/"email"）；旧网关响应无此字段 → nil
    public let linkedProviders: [String]?
    /// paid 时 true = 有真实商店期（含商店试用），false = 仅赠送。free 或旧网关响应 → nil
    public let proStoreBacked: Bool?

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
        linkedProviders: [String]? = nil,
        proStoreBacked: Bool? = nil
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
        self.proStoreBacked = proStoreBacked
    }
}
