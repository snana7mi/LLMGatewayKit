import Foundation
import LLMGatewayKit

#if os(iOS)
import GoogleSignIn

/// GoogleSignIn 8.x compatibility bridge.
///
/// Version 8 cannot bind an ID token to a caller-provided nonce, so `signIn()` fails
/// closed. Apps must inject a nonce-capable `GoogleSignInProviding` implementation.
@MainActor
public final class GoogleSignInBridge: GoogleSignInProviding {
    public init() {}

    /// App 的 .onOpenURL 里调用；返回 true 表示该 URL 是 Google 登录回调、已消费。
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    public func signIn() async throws -> SignInCredential {
        // GoogleSignIn 8.x cannot bind its ID token to a caller-provided nonce. Do not
        // silently downgrade replay protection; callers must inject a nonce-capable flow.
        throw AuthError.googleNonceRequired
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
