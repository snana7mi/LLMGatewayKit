import Foundation

public final class SyncAPIClient: @unchecked Sendable {
    public struct PushResult: Equatable, Sendable {
        public let stored: Int
        public let pruned: Int

        public init(stored: Int, pruned: Int) {
            self.stored = stored
            self.pruned = pruned
        }
    }

    public struct PullResult: Sendable {
        public let envelopes: [SyncEnvelope]
        public let nextCursor: Cursor?

        public init(envelopes: [SyncEnvelope], nextCursor: Cursor?) {
            self.envelopes = envelopes
            self.nextCursor = nextCursor
        }

        public struct Cursor: Codable, Equatable, Sendable {
            public let since: String
            public let sinceID: String

            enum CodingKeys: String, CodingKey {
                case since
                case sinceID = "since_id"
            }

            public init(since: String, sinceID: String) {
                self.since = since
                self.sinceID = sinceID
            }
        }
    }

    public struct StatusResult: Equatable, Sendable {
        public let storageBytes: Int
        public let entryCount: Int

        public init(storageBytes: Int, entryCount: Int) {
            self.storageBytes = storageBytes
            self.entryCount = entryCount
        }
    }

    private let config: LLMGatewayKitConfig
    private let auth: AuthService
    private let session: URLSession

    public init(config: LLMGatewayKitConfig, auth: AuthService, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    public func push(entries: [SyncEnvelope], codec: SyncPayloadCodec, deviceID: String, keyGeneration: Int) async throws -> PushResult {
        let token = try await auth.validAccessToken()
        let iso = ISO8601DateFormatter.gateway
        let wireEntries = try await entries.asyncMap { envelope in
            let encoded = try await codec.encode(envelope.data, entityType: envelope.entityType)
            return [
                "entity_type": envelope.entityType,
                "entity_id": envelope.entityID,
                "modified_at": iso.string(from: envelope.modifiedAt),
                "data": encoded.base64EncodedString(),
            ]
        }

        var request = URLRequest(url: try endpoint("/sync/push"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key_generation": keyGeneration,
            "device_id": deviceID,
            "entries": wireEntries,
        ])

        let data = try await perform(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return PushResult(
            stored: json["stored_entries"] as? Int ?? json["stored"] as? Int ?? 0,
            pruned: json["pruned_count"] as? Int ?? json["pruned"] as? Int ?? 0
        )
    }

    public func pull(since: String?, sinceID: String?, deviceID: String, codec: SyncPayloadCodec, limit: Int = 100) async throws -> PullResult {
        let token = try await auth.validAccessToken()
        var components = URLComponents(url: try endpoint("/sync/pull"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "since", value: since ?? "1970-01-01T00:00:00Z"),
            URLQueryItem(name: "since_id", value: sinceID ?? ""),
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await perform(request)
        let payload = try JSONDecoder.syncWire.decode(PullPayload.self, from: data)
        let envelopes = try await payload.entries.asyncMap { entry in
            let decoded = try await codec.decode(entry.data, entityType: entry.entityType)
            return SyncEnvelope(entityType: entry.entityType, entityID: entry.entityID, modifiedAt: entry.modifiedAt, data: decoded)
        }
        return PullResult(envelopes: envelopes, nextCursor: payload.nextCursor)
    }

    public func status() async throws -> StatusResult {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: try endpoint("/sync/status"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return StatusResult(
            storageBytes: json["storage_bytes"] as? Int ?? json["storageBytes"] as? Int ?? 0,
            entryCount: json["entry_count"] as? Int ?? json["entryCount"] as? Int ?? 0
        )
    }

    public func deleteAll() async throws {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: try endpoint("/sync"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.serverError("sync HTTP \(http.statusCode)")
        }
        return data
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: config.baseURL)?.absoluteURL else {
            throw AuthError.invalidURL
        }
        return url
    }
}

private struct PullPayload: Decodable {
    let entries: [WireEntry]
    let nextCursor: SyncAPIClient.PullResult.Cursor?

    enum CodingKeys: String, CodingKey {
        case entries
        case nextCursor = "next_cursor"
    }
}

private struct WireEntry: Decodable {
    let entityType: String
    let entityID: String
    let modifiedAt: Date
    let data: Data

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityID = "entity_id"
        case modifiedAt = "modified_at"
        case data
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            try await result.append(transform(element))
        }
        return result
    }
}

private extension JSONDecoder {
    static var syncWire: JSONDecoder {
        let decoder = JSONDecoder()
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
