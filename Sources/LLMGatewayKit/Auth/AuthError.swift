import Foundation

public enum AuthError: Equatable, LocalizedError, Sendable {
    case notLoggedIn
    case sessionExpired
    case invalidURL
    case networkError
    case invalidResponse
    case serverError(String)
    case accountDeletionFailed

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
        }
    }
}
