import Foundation
@testable import LLMGatewayKit

enum TestConfig {
    static func make() -> LLMGatewayKitConfig {
        LLMGatewayKitConfig(
            baseURL: URL(string: "https://api.test")!,
            entitlementID: "pro",
            appDisplayName: "Test",
            companionAppNames: [],
            revenueCatAPIKey: nil,
            paywallFeatures: [],
            deviceName: "Test Device"
        )
    }
}

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case success(body: String, status: Int)
        case failure(URLError)
    }

    nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset(responses newResponses: [Response] = []) {
        responses = newResponses
        requests = []
    }

    static func makeConfig() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        let response = Self.responses.removeFirst()
        switch response {
        case .success(let body, let status):
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class MockAppleSignInBridge: AppleSignInAuthenticating, @unchecked Sendable {
    let result: Result<AppleSignInResult, Error>

    init(result: Result<AppleSignInResult, Error>) {
        self.result = result
    }

    func authenticate(nonceRaw: String, hashedNonce: String) async throws -> AppleSignInResult {
        try result.get()
    }
}

@MainActor
func makeLoggedOutAuth() -> AuthService {
    AuthService(
        config: TestConfig.make(),
        tokenStore: InMemoryTokenStore(),
        appleBridge: MockAppleSignInBridge(result: .failure(URLError(.unknown))),
        session: URLSession(configuration: URLProtocolStub.makeConfig())
    )
}

@MainActor
final class ArrayCollector: SyncChangeCollecting, @unchecked Sendable {
    var pending: [SyncEnvelope]
    private var markedSynced = false

    init(pending: [SyncEnvelope]) {
        self.pending = pending
    }

    func collectPending() async throws -> [SyncEnvelope] {
        pending
    }

    func markSynced(_ envelopes: [SyncEnvelope]) async throws {
        markedSynced = true
        pending.removeAll()
    }

    func didMarkSynced() -> Bool {
        markedSynced
    }
}

@MainActor
final class ArrayMerger: SyncMerging, @unchecked Sendable {
    private var applied: [SyncEnvelope] = []

    func apply(_ envelope: SyncEnvelope) async throws {
        applied.append(envelope)
    }

    func firstAppliedEntityID() -> String? {
        applied.first?.entityID
    }
}
