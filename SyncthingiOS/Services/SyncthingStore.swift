import Foundation

@MainActor
final class SyncthingStore: ObservableObject {
    @Published private(set) var overview = SyncthingOverview()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastConnectedAt: Date?

    private var api = SyncthingAPI(snapshot: .default)
    private var snapshot = SyncthingSnapshot.default

    func configure(with snapshot: SyncthingSnapshot) {
        self.snapshot = snapshot
        api = SyncthingAPI(snapshot: snapshot)
    }

    func refresh() async {
        guard isConfigured else {
            overview = SyncthingOverview()
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            overview = try await api.overview()
            lastConnectedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isConfigured: Bool {
        !snapshot.apiKey.isEmpty
    }

    func restart() async {
        await runCommand {
            try await api.restart()
        }
    }

    func rescan(folderID: String? = nil) async {
        await runCommand {
            try await api.rescan(folderID: folderID)
        }
    }

    private func runCommand(_ command: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await command()
            overview = try await api.overview()
            lastConnectedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
