import XCTest
@testable import LLMGatewayKit

final class SyncPayloadCodecTests: XCTestCase {
    func test_identityCodec_roundtrip() async throws {
        let codec = IdentityPayloadCodec()
        let data = Data("hello".utf8)

        let encoded = try await codec.encode(data, entityType: "X")
        let decoded = try await codec.decode(encoded, entityType: "X")

        XCTAssertEqual(decoded, data)
    }
}

final class SyncAPIClientTests: XCTestCase {
    @MainActor
    func test_push_postsEntriesAndReportsPruned() async throws {
        let auth = try makeLoggedInAuth()
        URLProtocolStub.reset(responses: [.success(body: #"{"success":true,"stored_entries":1,"pruned_count":2}"#, status: 200)])
        let client = SyncAPIClient(config: TestConfig.make(), auth: auth, session: URLSession(configuration: URLProtocolStub.makeConfig()))
        let env = SyncEnvelope(entityType: "T", entityID: "1", modifiedAt: Date(), data: Data("body".utf8))

        let result = try await client.push(entries: [env], codec: IdentityPayloadCodec(), deviceID: "dev", keyGeneration: 1)

        XCTAssertEqual(result.stored, 1)
        XCTAssertEqual(result.pruned, 2)
    }

    @MainActor
    private func makeLoggedInAuth() throws -> AuthService {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let auth = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        auth.restoreSession()
        return auth
    }
}

final class SyncEngineTests: XCTestCase {
    @MainActor
    func test_syncNow_pushesPendingAndPullsRemote() async throws {
        let auth = try makeLoggedInAuth()
        URLProtocolStub.reset(responses: [
            .success(body: #"{"success":true,"stored_entries":1,"pruned_count":0}"#, status: 200),
            .success(body: #"{"entries":[{"entity_type":"X","entity_id":"r1","modified_at":"2026-05-16T00:00:00Z","data":"YWJj"}],"next_cursor":null}"#, status: 200),
        ])
        let pending = SyncEnvelope(entityType: "X", entityID: "p1", modifiedAt: Date(), data: Data("body".utf8))
        let collector = ArrayCollector(pending: [pending])
        let merger = ArrayMerger()
        let engine = SyncEngine(
            apiClient: SyncAPIClient(config: TestConfig.make(), auth: auth, session: URLSession(configuration: URLProtocolStub.makeConfig())),
            codec: IdentityPayloadCodec(),
            collector: collector,
            merger: merger,
            state: SyncState(suite: UserDefaults(suiteName: "sync_\(UUID())")!),
            deviceID: "dev",
            isEligible: { true }
        )

        let result = try await engine.syncNow()

        XCTAssertEqual(result.pushedCount, 1)
        XCTAssertEqual(result.pulledCount, 1)
        let firstAppliedEntityID = await merger.firstAppliedEntityID()
        let didMarkSynced = await collector.didMarkSynced()
        XCTAssertEqual(firstAppliedEntityID, "r1")
        XCTAssertTrue(didMarkSynced)
    }

    @MainActor
    private func makeLoggedInAuth() throws -> AuthService {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let auth = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        auth.restoreSession()
        return auth
    }
}

final class SyncStatusObserverTests: XCTestCase {
    @MainActor
    func test_observerCapturesLastResult() async throws {
        let store = InMemoryTokenStore()
        try store.save(accessToken: "tok", refreshToken: "r", expiry: Date().addingTimeInterval(1000))
        let auth = AuthService(config: TestConfig.make(), tokenStore: store, appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))), session: URLSession(configuration: URLProtocolStub.makeConfig()))
        auth.restoreSession()
        URLProtocolStub.reset(responses: [
            .success(body: #"{"success":true,"stored_entries":0,"pruned_count":0}"#, status: 200),
            .success(body: #"{"entries":[],"next_cursor":null}"#, status: 200),
        ])
        let engine = SyncEngine(
            apiClient: SyncAPIClient(config: TestConfig.make(), auth: auth, session: URLSession(configuration: URLProtocolStub.makeConfig())),
            codec: IdentityPayloadCodec(),
            collector: ArrayCollector(pending: []),
            merger: ArrayMerger(),
            state: SyncState(suite: UserDefaults(suiteName: "obs_\(UUID())")!),
            deviceID: "dev",
            isEligible: { true }
        )
        let observer = SyncStatusObserver(engine: engine)

        _ = try await engine.syncNow()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNotNil(observer.lastResult)
        XCTAssertTrue(observer.lastResult?.success ?? false)
    }
}
