import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var baseURLString: String

    @Published private(set) var apiKey: String

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseURLString = defaults.string(forKey: Keys.baseURL) ?? SyncthingSnapshot.default.baseURL.absoluteString
        let migratedAPIKey = defaults.string(forKey: Keys.apiKey)
        if let migratedAPIKey, KeychainStore.string(for: Keys.apiKey) == nil {
            KeychainStore.set(migratedAPIKey, for: Keys.apiKey)
            defaults.removeObject(forKey: Keys.apiKey)
        }
        self.apiKey = KeychainStore.string(for: Keys.apiKey) ?? migratedAPIKey ?? ""
        clearLegacySyncFolderBookmark()
    }

    var snapshot: SyncthingSnapshot {
        SyncthingSnapshot(
            baseURL: URL(string: normalizedBaseURLString) ?? SyncthingSnapshot.default.baseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var normalizedBaseURLString: String {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    func update(baseURLString: String, apiKey: String) {
        self.baseURLString = baseURLString
        self.apiKey = apiKey
        persist()
    }

    func useEmbeddedCore() {
        update(
            baseURLString: SyncthingCoreManager.localBaseURLString,
            apiKey: SyncthingCoreManager.localAPIKey
        )
    }

    private func persist() {
        defaults.set(baseURLString, forKey: Keys.baseURL)
        KeychainStore.set(apiKey, for: Keys.apiKey)
        defaults.removeObject(forKey: Keys.apiKey)
    }

    private func clearLegacySyncFolderBookmark() {
        defaults.removeObject(forKey: Keys.syncFolderBookmark)
        defaults.removeObject(forKey: Keys.syncFolderName)
    }

    private enum Keys {
        static let baseURL = "syncthing.baseURL"
        static let apiKey = "syncthing.apiKey"
        static let syncFolderBookmark = "syncthing.syncFolderBookmark"
        static let syncFolderName = "syncthing.syncFolderName"
    }
}
