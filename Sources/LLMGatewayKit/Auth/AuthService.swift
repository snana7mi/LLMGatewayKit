import Foundation
import Observation

@MainActor
@Observable
public final class AuthService {
    public private(set) var isLoggedIn = false
    public private(set) var currentUser: AccountUser?
    public private(set) var cachedAvatarData: Data?

    public var cachedAppleSub: String? {
        defaults.string(forKey: Keys.cachedAppleSub)
    }

    public enum Keys {
        public static let cachedAppleSub = "LLMGatewayKit.cachedAppleSub"
        public static let cachedAccountUser = AccountProfileCache.Keys.cachedAccountUser
        public static let migrationDone = "LLMGatewayKit.migrationDone"
    }

    private let config: LLMGatewayKitConfig
    private let tokenStore: TokenStoring
    private let appleBridge: AppleSignInAuthenticating
    private let session: URLSession
    private let defaults: UserDefaults
    private let profileCache: AccountProfileCache
    private var refreshTask: Task<String, Error>?
    private var cachedAvatarURL: String?

    public init(
        config: LLMGatewayKitConfig,
        tokenStore: TokenStoring = KeychainTokenStore(),
        appleBridge: AppleSignInAuthenticating? = nil,
        session: URLSession = .shared
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.appleBridge = appleBridge ?? AppleSignInBridge()
        self.session = session
        self.defaults = .standard
        self.profileCache = AccountProfileCache(defaults: .standard)
    }

    init(
        config: LLMGatewayKitConfig,
        tokenStore: TokenStoring,
        appleBridge: AppleSignInAuthenticating,
        session: URLSession,
        defaults: UserDefaults,
        profileCache: AccountProfileCache
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.appleBridge = appleBridge
        self.session = session
        self.defaults = defaults
        self.profileCache = profileCache
    }

    public func authenticate(identityToken: Data, fullName: String?, appleSub: String) async throws {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidResponse
        }
        var body: [String: Any] = [
            "identityToken": tokenString,
            "deviceName": config.deviceName,
        ]
        if let fullName, !fullName.isEmpty {
            body["displayName"] = fullName
        }

        let data = try await postJSON(path: "/auth/apple", body: body)
        let parsed = try Self.parseTokenResponse(data)
        try tokenStore.save(accessToken: parsed.accessToken, refreshToken: parsed.refreshToken, expiry: parsed.expiry)
        isLoggedIn = true
        if let parsedUser = parsed.user {
            setCurrentUser(parsedUser)
        }
        defaults.set(appleSub, forKey: Keys.cachedAppleSub)
        try? await fetchAccount()
    }

    public func authenticateInteractively() async throws {
        let pair = NonceGenerator.makePair()
        let result = try await appleBridge.authenticate(nonceRaw: pair.raw, hashedNonce: pair.hashedSHA256)
        try await authenticate(identityToken: Data(result.identityToken.utf8), fullName: nil, appleSub: result.appleUserId)
    }

    public func restoreSession() {
        let hasAccess = ((try? tokenStore.loadAccessToken()) ?? nil) != nil
        let hasRefresh = ((try? tokenStore.loadRefreshToken()) ?? nil) != nil
        isLoggedIn = hasAccess && hasRefresh
        if isLoggedIn {
            restorePersistedProfile()
        }
    }

    public func validAccessToken() async throws -> String {
        guard let access = try tokenStore.loadAccessToken() else {
            throw AuthError.notLoggedIn
        }
        if let expiry = try tokenStore.loadExpiry(), expiry.timeIntervalSinceNow < 60 {
            try await refreshAccessToken()
            guard let renewed = try tokenStore.loadAccessToken() else {
                throw AuthError.notLoggedIn
            }
            return renewed
        }
        return access
    }

    public func refreshAccessToken() async throws {
        if let refreshTask {
            _ = try await refreshTask.value
            return
        }

        let task = Task { try await self.performRefresh() }
        refreshTask = task
        do {
            _ = try await task.value
            refreshTask = nil
        } catch {
            refreshTask = nil
            throw error
        }
    }

    public func logout() async {
        let userID = currentUser?.id
        try? tokenStore.clear()
        isLoggedIn = false
        currentUser = nil
        cachedAvatarData = nil
        cachedAvatarURL = nil
        profileCache.clear(userID: userID)
        defaults.removeObject(forKey: Keys.cachedAppleSub)
    }

    public func deleteAccount() async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: try endpoint("/auth/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await performJSON(request)
        await logout()
    }

    public func fetchAccount() async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: try endpoint("/account"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await performJSON(request)
        let payload = try JSONDecoder.gateway.decode(AccountPayload.self, from: data)
        setCurrentUser(payload.user)
    }

    public func updateDisplayName(_ name: String) async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: try endpoint("/account"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["displayName": name])
        let data = try await performJSON(request)
        let payload = try JSONDecoder.gateway.decode(AccountPayload.self, from: data)
        setCurrentUser(payload.user)
    }

    public func updateBio(_ bio: String?) async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: try endpoint("/account"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bioValue: Any = bio ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: ["bio": bioValue])
        let data = try await performJSON(request)
        let payload = try JSONDecoder.gateway.decode(AccountPayload.self, from: data)
        setCurrentUser(payload.user)
    }

    public func fetchUsage() async throws -> UsageInfo {
        let token = try await validAccessToken()
        var request = URLRequest(url: try endpoint("/usage"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await performJSON(request)
        return try JSONDecoder.gateway.decode(UsageInfo.self, from: data)
    }

    public func uploadAvatar(imageData: Data, mimeType: String = "image/jpeg") async throws -> String {
        let token = try await validAccessToken()
        let boundary = UUID().uuidString
        var request = URLRequest(url: try endpoint("/account/avatar"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartAvatarBody(imageData: imageData, mimeType: mimeType, boundary: boundary)

        let data = try await performJSON(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let avatarURL = json["avatarURL"] as? String ?? json["avatar_url"] as? String else {
            throw AuthError.invalidResponse
        }

        if let user = currentUser {
            setCurrentUser(AccountUser(
                id: user.id,
                email: user.email,
                displayName: user.displayName,
                tier: user.tier,
                tierExpiresAt: user.tierExpiresAt,
                createdAt: user.createdAt,
                avatarURL: avatarURL,
                memberNo: user.memberNo,
                bio: user.bio
            ))
        }
        cachedAvatarData = imageData
        cachedAvatarURL = avatarURL
        if let userID = currentUser?.id {
            profileCache.saveAvatar(imageData, userID: userID, avatarURL: avatarURL)
        }
        return avatarURL
    }

    public func loadAvatarDataIfNeeded() async -> Data? {
        guard let urlString = currentUser?.avatarURL, !urlString.isEmpty else { return nil }
        if urlString == cachedAvatarURL, let cachedAvatarData {
            return cachedAvatarData
        }
        if let userID = currentUser?.id,
           let diskData = profileCache.loadAvatar(userID: userID, expectedAvatarURL: urlString) {
            cachedAvatarData = diskData
            cachedAvatarURL = urlString
            return diskData
        }
        guard let url = URL(string: urlString),
              let (data, _) = try? await session.data(from: url) else {
            return nil
        }
        cachedAvatarData = data
        cachedAvatarURL = urlString
        if let userID = currentUser?.id {
            profileCache.saveAvatar(data, userID: userID, avatarURL: urlString)
        }
        return data
    }

    public func updateCurrentUser(_ user: AccountUser) {
        setCurrentUser(user)
    }

    private func setCurrentUser(_ user: AccountUser) {
        currentUser = user
        profileCache.saveUser(user)
    }

    private func restorePersistedProfile() {
        guard let user = profileCache.loadUser() else { return }
        currentUser = user
        guard let avatarURL = user.avatarURL, !avatarURL.isEmpty else { return }
        if let data = profileCache.loadAvatar(userID: user.id, expectedAvatarURL: avatarURL) {
            cachedAvatarData = data
            cachedAvatarURL = avatarURL
        }
    }

    private func performRefresh() async throws -> String {
        guard let refresh = try tokenStore.loadRefreshToken() else {
            await logout()
            throw AuthError.notLoggedIn
        }
        do {
            let data = try await postJSON(path: "/auth/refresh", body: ["refreshToken": refresh, "deviceName": config.deviceName])
            let parsed = try Self.parseTokenResponse(data)
            try tokenStore.save(accessToken: parsed.accessToken, refreshToken: parsed.refreshToken, expiry: parsed.expiry)
            return parsed.accessToken
        } catch is URLError {
            throw AuthError.networkError
        } catch {
            await logout()
            throw AuthError.sessionExpired
        }
    }

    private func postJSON(path: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        return try await performJSON(request)
    }

    private func performJSON(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AuthError.networkError
            }
            guard (200...299).contains(http.statusCode) else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["error"] as? String ?? json["message"] as? String {
                    throw AuthError.serverError(message)
                }
                throw AuthError.serverError("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as AuthError {
            throw error
        } catch is URLError {
            throw AuthError.networkError
        } catch {
            throw error
        }
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: config.baseURL)?.absoluteURL else {
            throw AuthError.invalidURL
        }
        return url
    }

    private func multipartAvatarBody(imageData: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func parseTokenResponse(_ data: Data) throws -> TokenResponse {
        try JSONDecoder.gateway.decode(TokenResponse.self, from: data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: AccountUser?
    let expiresAt: Date?
    let expiresIn: TimeInterval?

    var expiry: Date {
        if let expiresAt { return expiresAt }
        if let expiresIn { return Date().addingTimeInterval(expiresIn) }
        return Date().addingTimeInterval(15 * 60)
    }
}

private struct AccountPayload: Decodable {
    let user: AccountUser
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

extension JSONDecoder {
    static var gateway: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.gateway.date(from: string) ?? ISO8601DateFormatter.gatewayWithoutFractions.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
        return decoder
    }
}

extension ISO8601DateFormatter {
    static var gateway: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static var gatewayWithoutFractions: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
