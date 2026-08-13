import Foundation
import Security

public protocol TokenStoring: Sendable {
    var supportsPersistentRefreshRequestID: Bool { get }
    func save(accessToken: String, refreshToken: String, expiry: Date) throws
    func loadAccessToken() throws -> String?
    func loadRefreshToken() throws -> String?
    func loadExpiry() throws -> Date?
    /// Stable idempotency key for one in-flight refresh rotation. It must survive
    /// process suspension/termination and is cleared only after the successor pair is saved.
    func saveRefreshRequestID(_ id: String) throws
    func loadRefreshRequestID() throws -> String?
    func clearRefreshRequestID() throws
    func clear() throws
}

/// Older/custom stores remain source-compatible and stay on the server's legacy refresh path.
/// They must opt in only when the request id really survives process termination.
public extension TokenStoring {
    var supportsPersistentRefreshRequestID: Bool { false }
    func saveRefreshRequestID(_ id: String) throws {}
    func loadRefreshRequestID() throws -> String? { nil }
    func clearRefreshRequestID() throws {}
}

public final class KeychainTokenStore: TokenStoring, @unchecked Sendable {
    private enum Keys {
        static let access = "kit.accessToken"
        static let refresh = "kit.refreshToken"
        static let expiry = "kit.tokenExpiry"
        static let refreshRequestID = "kit.refreshRequestID"
        static let credentials = "kit.credentials.v1"
    }

    private struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiry: Date
    }

    private let service: String

    public init(service: String = "LLMGatewayKit") {
        self.service = service
    }

    public var supportsPersistentRefreshRequestID: Bool { true }

    public func save(accessToken: String, refreshToken: String, expiry: Date) throws {
        let credentials = Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiry: expiry
        )
        try writeData(JSONEncoder().encode(credentials), account: Keys.credentials)
        // The envelope is now authoritative; remove pre-envelope items so an old token
        // cannot reappear if the new item is later cleared or becomes unreadable.
        try? delete(Keys.access)
        try? delete(Keys.refresh)
        try? delete(Keys.expiry)
    }

    public func loadAccessToken() throws -> String? {
        if let credentials = try readCredentials() { return credentials.accessToken }
        return try readString(Keys.access)
    }

    public func loadRefreshToken() throws -> String? {
        if let credentials = try readCredentials() { return credentials.refreshToken }
        return try readString(Keys.refresh)
    }

    public func loadExpiry() throws -> Date? {
        if let credentials = try readCredentials() { return credentials.expiry }
        guard let string = try readString(Keys.expiry) else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    public func saveRefreshRequestID(_ id: String) throws {
        try writeString(id, account: Keys.refreshRequestID)
    }

    public func loadRefreshRequestID() throws -> String? {
        return try readString(Keys.refreshRequestID)
    }

    public func clearRefreshRequestID() throws {
        try delete(Keys.refreshRequestID)
    }

    public func clear() throws {
        var firstError: Error?
        for account in [Keys.credentials, Keys.access, Keys.refresh, Keys.expiry, Keys.refreshRequestID] {
            do { try delete(account) }
            catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }

    private func writeString(_ value: String, account: String) throws {
        try writeData(Data(value.utf8), account: account)
    }

    private func writeData(_ data: Data, account: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            // Available to background work after the first unlock, but never migrates
            // through device backups.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AuthError.serverError("Keychain update \(updateStatus)")
        }

        var insert = lookup
        insert.merge(update) { _, new in new }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthError.serverError("Keychain add \(addStatus)")
        }
    }

    private func readString(_ account: String) throws -> String? {
        guard let data = try readData(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readCredentials() throws -> Credentials? {
        guard let data = try readData(Keys.credentials) else { return nil }
        do { return try JSONDecoder().decode(Credentials.self, from: data) }
        catch { throw AuthError.serverError("Keychain credentials decode") }
    }

    private func readData(_ account: String) throws -> Data? {
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
        return data
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
    private var refreshRequestID: String?

    public init() {}

    public var supportsPersistentRefreshRequestID: Bool { true }

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

    public func saveRefreshRequestID(_ id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        refreshRequestID = id
    }

    public func loadRefreshRequestID() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return refreshRequestID
    }

    public func clearRefreshRequestID() throws {
        lock.lock()
        defer { lock.unlock() }
        refreshRequestID = nil
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        access = nil
        refresh = nil
        expiry = nil
        refreshRequestID = nil
    }
}
