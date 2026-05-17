import Foundation
import Observation

@MainActor
@Observable
public final class SyncStatusObserver {
    public private(set) var lastResult: SyncResult?
    public private(set) var isSyncing = false

    private let engine: SyncEngine
    private var task: Task<Void, Never>?

    public init(engine: SyncEngine) {
        self.engine = engine
        task = Task { [weak self] in
            guard let self else { return }
            for await result in self.engine.results() {
                self.lastResult = result
                self.isSyncing = false
            }
        }
    }

    @discardableResult
    public func syncNow() async throws -> SyncResult {
        isSyncing = true
        do {
            return try await engine.syncNow()
        } catch {
            isSyncing = false
            throw error
        }
    }
}
