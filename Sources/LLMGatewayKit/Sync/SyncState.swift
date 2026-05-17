import Foundation

public final class SyncState: @unchecked Sendable {
    public static let shared = SyncState()

    private enum Keys {
        static let isEnabled = "LLMGatewayKit.sync.isEnabled"
        static let lastPullSince = "LLMGatewayKit.sync.lastPullSince"
        static let lastPullSinceID = "LLMGatewayKit.sync.lastPullSinceID"
        static let disabledByUserID = "LLMGatewayKit.sync.disabledByUserID"
    }

    private let suite: UserDefaults

    public init(suite: UserDefaults = .standard) {
        self.suite = suite
    }

    public var isEnabled: Bool {
        get {
            guard suite.object(forKey: Keys.isEnabled) != nil else { return true }
            return suite.bool(forKey: Keys.isEnabled)
        }
        set { suite.set(newValue, forKey: Keys.isEnabled) }
    }

    public var lastPullSince: String? {
        get { suite.string(forKey: Keys.lastPullSince) }
        set { suite.set(newValue, forKey: Keys.lastPullSince) }
    }

    public var lastPullSinceID: String? {
        get { suite.string(forKey: Keys.lastPullSinceID) }
        set { suite.set(newValue, forKey: Keys.lastPullSinceID) }
    }

    public var disabledByUserID: String? {
        get { suite.string(forKey: Keys.disabledByUserID) }
        set { suite.set(newValue, forKey: Keys.disabledByUserID) }
    }

    public func resetPullCursor() {
        lastPullSince = nil
        lastPullSinceID = nil
    }
}
