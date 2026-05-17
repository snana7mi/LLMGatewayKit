import Foundation

public struct SyncEnvelope: Codable, Equatable, Sendable {
    public let entityType: String
    public let entityID: String
    public let modifiedAt: Date
    public let data: Data

    public init(entityType: String, entityID: String, modifiedAt: Date, data: Data) {
        self.entityType = entityType
        self.entityID = entityID
        self.modifiedAt = modifiedAt
        self.data = data
    }
}

public struct SyncResult: Equatable, Sendable {
    public let pushedCount: Int
    public let pulledCount: Int
    public let prunedCount: Int
    public let success: Bool
    public let error: String?
    public let timestamp: Date

    public init(
        pushedCount: Int = 0,
        pulledCount: Int = 0,
        prunedCount: Int = 0,
        success: Bool,
        error: String? = nil,
        timestamp: Date = Date()
    ) {
        self.pushedCount = pushedCount
        self.pulledCount = pulledCount
        self.prunedCount = prunedCount
        self.success = success
        self.error = error
        self.timestamp = timestamp
    }
}
