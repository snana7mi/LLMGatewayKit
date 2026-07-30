import Foundation

public enum AuthError: Equatable, LocalizedError, Sendable {
    case notLoggedIn
    case sessionExpired
    case invalidURL
    case networkError
    case invalidResponse
    case serverError(String)
    case accountDeletionFailed
    case googleProviderUnavailable
    case googleNonceRequired
    case identityAlreadyLinked
    case cannotUnlinkLastIdentity
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Please sign in to continue."
        case .sessionExpired:
            return "Session expired. Please sign in again."
        case .invalidURL:
            return "Invalid server URL."
        case .networkError:
            return "Network error."
        case .invalidResponse:
            return "Invalid server response."
        case .serverError(let message):
            return "Server error: \(message)"
        case .accountDeletionFailed:
            return "Failed to delete account."
        case .googleProviderUnavailable:
            return "Google sign-in is not configured for this app."
        case .googleNonceRequired:
            return "Google sign-in requires a nonce-bound ID token."
        case .identityAlreadyLinked:
            return "This account is already linked to another user."
        case .cannotUnlinkLastIdentity:
            return "You can't unlink your only sign-in method."
        case .userCancelled:
            return "Sign-in was cancelled."   // 含 "cancel"：现有 UI 的取消静默过滤直接生效
        }
    }
}
