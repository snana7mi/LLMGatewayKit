import Foundation

public protocol SyncPayloadCodec: Sendable {
    func encode(_ plaintext: Data, entityType: String) async throws -> Data
    func decode(_ wire: Data, entityType: String) async throws -> Data
}

public struct IdentityPayloadCodec: SyncPayloadCodec {
    public init() {}

    public func encode(_ plaintext: Data, entityType: String) async throws -> Data {
        plaintext
    }

    public func decode(_ wire: Data, entityType: String) async throws -> Data {
        wire
    }
}
