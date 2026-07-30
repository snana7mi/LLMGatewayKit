import Foundation

public enum AuthProvider: String, Sendable, CaseIterable {
    case apple
    case google
}

/// provider 中立的登录凭证：AuthService 只管「拿到 idToken 之后」的事，
/// 凭证怎么来（SIWA / GoogleSignIn / 未来的 LINE）由桥接层负责。
public struct SignInCredential: Equatable, Sendable {
    public let provider: AuthProvider
    public let idToken: String
    public let providerUid: String      // apple sub / google sub
    public let displayName: String?     // Apple 首次授权才有；Google 传 nil（后端取 token claim）
    public let rawNonce: String?        // Google 登录必填；随请求上行供网关校验 token nonce claim

    public init(provider: AuthProvider, idToken: String, providerUid: String, displayName: String? = nil, rawNonce: String? = nil) {
        self.provider = provider
        self.idToken = idToken
        self.providerUid = providerUid
        self.displayName = displayName
        self.rawNonce = rawNonce
    }
}

/// Google 授权 UI 提供者。实现放独立 product LLMGatewayKitGoogleAuth（GoogleSignInBridge），
/// 不链接该 product 的 App 不拉 GoogleSignIn 依赖；protocol 放核心以便测试注入 mock。
@MainActor
public protocol GoogleSignInProviding: Sendable {
    func signIn() async throws -> SignInCredential
}
