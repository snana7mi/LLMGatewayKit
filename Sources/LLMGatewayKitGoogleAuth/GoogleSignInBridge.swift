import Foundation
import LLMGatewayKit

#if os(iOS)
import GoogleSignIn
import UIKit

/// GoogleSignInProviding 的默认实现：写一次、所有 App 复用。
/// GIDSignIn 自动读 App Info.plist 的 GIDClientID，本类 app 无关；
/// App 侧只需：链接本 product + Info.plist 配置 + onOpenURL 转发 handle(_:) + 注入 AuthService。
@MainActor
public final class GoogleSignInBridge: GoogleSignInProviding {
    public init() {}

    /// App 的 .onOpenURL 里调用；返回 true 表示该 URL 是 Google 登录回调、已消费。
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    public func signIn() async throws -> SignInCredential {
        guard let presenter = Self.topViewController() else {
            throw AuthError.serverError("No presenting view controller")
        }
        // GoogleSignIn 8.x 的 signIn API 无 nonce 参数（仅 7.1 短暂存在过）→ rawNonce 传 nil。
        // 网关侧 nonce 校验本就是可选的；id_token 仍经 JWKS 验签 + aud/iss/exp 校验。
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil)
            guard let idToken = result.user.idToken?.tokenString,
                  let uid = result.user.userID else {
                throw AuthError.invalidResponse
            }
            return SignInCredential(provider: .google, idToken: idToken, providerUid: uid, displayName: nil, rawNonce: nil)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AuthError.userCancelled
        }
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#else
/// 非 iOS 平台占位（同 AppleSignInBridge 模式）：编译通过、调用即抛。
@MainActor
public final class GoogleSignInBridge: GoogleSignInProviding {
    public init() {}

    public static func handle(_ url: URL) -> Bool { false }

    public func signIn() async throws -> SignInCredential {
        throw AuthError.serverError("Google sign-in unavailable on this platform")
    }
}
#endif
