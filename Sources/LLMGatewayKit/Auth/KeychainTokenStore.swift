import Foundation
import Security

public protocol TokenStoring: Sendable {
    func save(accessToken: String, refreshToken: String, expiry: Date) throws
    func loadAccessToken() throws -> String?
    func loadRefreshToken() throws -> String?
    func loadExpiry() throws -> Date?
    func clear() throws
}

public final class KeychainTokenStore: TokenStoring, @unchecked Sendable {
    private enum Keys {
        static let access = "kit.accessToken"
        static let refresh = "kit.refreshToken"
        static let expiry = "kit.tokenExpiry"
    }

    private let service: String

    public init(service: String = "LLMGatewayKit") {
        self.service = service
    }

    public func save(accessToken: String, refreshToken: String, expiry: Date) throws {
        try writeString(accessToken, account: Keys.access)
        try writeString(refreshToken, account: Keys.refresh)
        try writeString(ISO8601DateFormatter().string(from: expiry), account: Keys.expiry)
    }

    public func loadAccessToken() throws -> String? {
        try readString(Keys.access)
    }

    public func loadRefreshToken() throws -> String? {
        try readString(Keys.refresh)
    }

    public func loadExpiry() throws -> Date? {
        guard let string = try readString(Keys.expiry) else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    public func clear() throws {
        try delete(Keys.access)
        try delete(Keys.refresh)
        try delete(Keys.expiry)
    }

    private func writeString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        try delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.serverError("Keychain add \(status)")
        }
    }

    private func readString(_ account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthError.serverError("Keychain read \(status)")
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.serverError("Keychain delete \(status)")
        }
    }
}

public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var access: String?
    private var refresh: String?
    private var expiry: Date?

    public init() {}

    public func save(accessToken: String, refreshToken: String, expiry: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        self.access = accessToken
        self.refresh = refreshToken
        self.expiry = expiry
    }

    public func loadAccessToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return access
    }

    public func loadRefreshToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return refresh
    }

    public func loadExpiry() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return expiry
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        access = nil
        refresh = nil
        expiry = nil
    }
}
