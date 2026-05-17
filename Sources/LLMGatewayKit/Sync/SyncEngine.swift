import Foundation

public final class SyncEngine: @unchecked Sendable {
    private let apiClient: SyncAPIClient
    private let codec: SyncPayloadCodec
    private let collector: SyncChangeCollecting
    private let merger: SyncMerging
    private let state: SyncState
    private let deviceID: String
    private let keyGeneration: Int
    private let isEligible: @Sendable () async -> Bool
    private let resultStream: AsyncStream<SyncResult>
    private let resultContinuation: AsyncStream<SyncResult>.Continuation
    private var autoSyncTask: Task<Void, Never>?

    public init(
        apiClient: SyncAPIClient,
        codec: SyncPayloadCodec,
        collector: SyncChangeCollecting,
        merger: SyncMerging,
        state: SyncState = .shared,
        deviceID: String,
        keyGeneration: Int = 1,
        isEligible: @escaping @Sendable () async -> Bool
    ) {
        self.apiClient = apiClient
        self.codec = codec
        self.collector = collector
        self.merger = merger
        self.state = state
        self.deviceID = deviceID
        self.keyGeneration = keyGeneration
        self.isEligible = isEligible
        (self.resultStream, self.resultContinuation) = AsyncStream.makeStream()
    }

    deinit {
        autoSyncTask?.cancel()
        resultContinuation.finish()
    }

    public func results() -> AsyncStream<SyncResult> {
        resultStream
    }

    @discardableResult
    public func syncNow() async throws -> SyncResult {
        guard state.isEnabled, await isEligible() else {
            let result = SyncResult(success: true)
            resultContinuation.yield(result)
            return result
        }

        do {
            let pending = try await collector.collectPending()
            let pushResult = try await apiClient.push(entries: pending, codec: codec, deviceID: deviceID, keyGeneration: keyGeneration)
            if !pending.isEmpty {
                try await collector.markSynced(pending)
            }

            let pullResult = try await apiClient.pull(
                since: state.lastPullSince,
                sinceID: state.lastPullSinceID,
                deviceID: deviceID,
                codec: codec
            )
            for envelope in pullResult.envelopes {
                try await merger.apply(envelope)
            }
            if let nextCursor = pullResult.nextCursor {
                state.lastPullSince = nextCursor.since
                state.lastPullSinceID = nextCursor.sinceID
            } else if let newest = pullResult.envelopes.max(by: { $0.modifiedAt < $1.modifiedAt }) {
                state.lastPullSince = ISO8601DateFormatter.gateway.string(from: newest.modifiedAt)
                state.lastPullSinceID = newest.entityID
            }

            let result = SyncResult(
                pushedCount: pushResult.stored,
                pulledCount: pullResult.envelopes.count,
                prunedCount: pushResult.pruned,
                success: true
            )
            resultContinuation.yield(result)
            return result
        } catch {
            let result = SyncResult(success: false, error: error.localizedDescription)
            resultContinuation.yield(result)
            throw error
        }
    }

    @discardableResult
    public func forceFullSync() async throws -> SyncResult {
        state.resetPullCursor()
        return try await syncNow()
    }

    public func disableAndDeleteCloud() async throws {
        try await apiClient.deleteAll()
        state.isEnabled = false
        state.resetPullCursor()
    }

    public func startAutoSync(repoChanges: AsyncStream<Void>) async {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            for await _ in repoChanges {
                guard !Task.isCancelled else { return }
                _ = try? await self?.syncNow()
            }
        }
    }
}
