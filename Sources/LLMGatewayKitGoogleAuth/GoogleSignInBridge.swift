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
        // GoogleSignIn 10.x 起 signIn 接受自定义 nonce（9.0 引入，`#637` 在 10.1.0 修了
        // Device Policy 重启后丢失 nonce 的问题）。
        //
        // **与 Apple 约定不同，别照抄。** Google 把传入值原样写进 id_token 的 nonce claim，网关也
        // 原样比较（`src/auth/google.ts`，Android 依赖这个行为），所以交给 SDK 和交给网关的必须是
        // 同一个值。Apple 那边 claim 是哈希、网关先哈希再比，才需要 raw / hashed 一对。
        let nonce = NonceGenerator.makePair().raw
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: nonce)
            guard let idToken = result.user.idToken?.tokenString,
                  let uid = result.user.userID else {
                throw AuthError.invalidResponse
            }
            return SignInCredential(
                provider: .google, idToken: idToken, providerUid: uid, displayName: nil, rawNonce: nonce)
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
