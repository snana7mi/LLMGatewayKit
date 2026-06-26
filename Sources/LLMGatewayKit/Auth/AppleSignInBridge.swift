import Foundation

public struct AppleSignInResult: Equatable, Sendable {
    public let identityToken: String
    public let appleUserId: String
    public let fullName: String?

    public init(identityToken: String, appleUserId: String, fullName: String? = nil) {
        self.identityToken = identityToken
        self.appleUserId = appleUserId
        self.fullName = fullName
    }
}

@MainActor
public protocol AppleSignInAuthenticating: Sendable {
    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult
}

#if os(iOS)
import AuthenticationServices
import UIKit

@MainActor
public final class AppleSignInBridge: NSObject, AppleSignInAuthenticating {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    public override init() {
        super.init()
    }

    public func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        guard continuation == nil else {
            throw AuthError.serverError("Sign-in already in progress")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleSignInBridge: ASAuthorizationControllerDelegate {
    public nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            defer { continuation = nil }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                continuation?.resume(throwing: AuthError.invalidResponse)
                return
            }
            continuation?.resume(returning: .init(
                identityToken: token,
                appleUserId: credential.user,
                fullName: AppleNameFormatter.string(from: credential.fullName)
            ))
        }
    }

    public nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AppleSignInBridge: ASAuthorizationControllerPresentationContextProviding {
    public nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
#else
@MainActor
public final class AppleSignInBridge: AppleSignInAuthenticating {
    public init() {}

    public func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        throw AuthError.serverError("Apple sign-in unavailable on this platform")
    }
}
#endif
