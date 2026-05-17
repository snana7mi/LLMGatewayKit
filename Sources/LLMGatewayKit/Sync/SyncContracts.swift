@MainActor
public protocol SyncChangeCollecting: Sendable {
    func collectPending() async throws -> [SyncEnvelope]
    func markSynced(_ envelopes: [SyncEnvelope]) async throws
}

@MainActor
public protocol SyncMerging: Sendable {
    func apply(_ envelope: SyncEnvelope) async throws
}
