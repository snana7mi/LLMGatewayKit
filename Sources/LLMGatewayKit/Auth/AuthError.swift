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
    case identityAlreadyLinked
    case cannotUnlinkLastIdentity
    case userCancelled
    case emailCodeInvalid
    case emailCodeExpired
    case emailTooManyAttempts
    case invalidEmail
    case emailRateLimited
    case blockedDisplayName
    case blockedAvatar
    case profileCheckUnavailable

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
        case .identityAlreadyLinked:
            return "This account is already linked to another user."
        case .cannotUnlinkLastIdentity:
            return "You can't unlink your only sign-in method."
        case .userCancelled:
            return "Sign-in was cancelled."   // 含 "cancel"：现有 UI 的取消静默过滤直接生效
        case .emailCodeInvalid:
            return "That code isn't right. Please check and try again."
        case .emailCodeExpired:
            return "That code has expired. Please request a new one."
        case .emailTooManyAttempts:
            return "Too many attempts. Please request a new code."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .emailRateLimited:
            return "Too many requests. Please wait a bit and try again."
        case .blockedDisplayName:
            return "This nickname isn't allowed. Please choose another."
        case .blockedAvatar:
            return "This photo can't be used as an avatar. Please choose another."
        case .profileCheckUnavailable:
            return "We couldn't check this photo right now. Please try again."
        }
    }
}
