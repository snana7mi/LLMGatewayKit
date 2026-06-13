import Foundation

/// 账号资料与头像的本地缓存（UserDefaults + Application Support）。
struct AccountProfileCache {
    enum Keys {
        static let cachedAccountUser = "LLMGatewayKit.cachedAccountUser"

        static func cachedAvatarURL(userID: String) -> String {
            "LLMGatewayKit.cachedAvatarURL.\(userID)"
        }
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let avatarDirectory: URL

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        avatarDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        if let avatarDirectory {
            self.avatarDirectory = avatarDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.avatarDirectory = base.appendingPathComponent("LLMGatewayKit", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.avatarDirectory, withIntermediateDirectories: true)
    }

    func saveUser(_ user: AccountUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        defaults.set(data, forKey: Keys.cachedAccountUser)
    }

    func loadUser() -> AccountUser? {
        guard let data = defaults.data(forKey: Keys.cachedAccountUser) else { return nil }
        return try? JSONDecoder().decode(AccountUser.self, from: data)
    }

    func saveAvatar(_ data: Data, userID: String, avatarURL: String) {
        let fileURL = avatarFileURL(userID: userID)
        try? data.write(to: fileURL, options: .atomic)
        defaults.set(avatarURL, forKey: Keys.cachedAvatarURL(userID: userID))
    }

    func loadAvatar(userID: String, expectedAvatarURL: String) -> Data? {
        guard defaults.string(forKey: Keys.cachedAvatarURL(userID: userID)) == expectedAvatarURL else {
            return nil
        }
        return try? Data(contentsOf: avatarFileURL(userID: userID))
    }

    func clear(userID: String?) {
        defaults.removeObject(forKey: Keys.cachedAccountUser)
        if let userID {
            defaults.removeObject(forKey: Keys.cachedAvatarURL(userID: userID))
            try? fileManager.removeItem(at: avatarFileURL(userID: userID))
        }
    }

    private func avatarFileURL(userID: String) -> URL {
        avatarDirectory.appendingPathComponent("avatar-\(userID).dat")
    }
}
