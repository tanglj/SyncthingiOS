import Foundation

@MainActor
final class SyncthingStore: ObservableObject {
    @Published private(set) var overview = SyncthingOverview()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastConnectedAt: Date?

    private var api = SyncthingAPI(snapshot: .default)
    private var snapshot = SyncthingSnapshot.default
    private var eventTask: Task<Void, Never>?
    private var lastEventID: Int64 = 0

    /// Set by the App when using the embedded core. When non-nil, restart
    /// routes through stop+start instead of /rest/system/restart (which
    /// permanently kills the in-process core).
    var embeddedRestart: (() async -> Void)?

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
        if let embeddedRestart {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            await embeddedRestart()
            do {
                overview = try await api.overview()
                lastConnectedAt = Date()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
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

    // MARK: - Event-driven refresh (P1-7)

    /// Starts a long-poll loop on /rest/events. When a relevant event arrives
    /// (state change, config saved, download complete), triggers a refresh.
    func startEventLoop() {
        guard isConfigured else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            await self?.pollEvents()
        }
    }

    func stopEventLoop() {
        eventTask?.cancel()
        eventTask = nil
    }

    private func pollEvents() async {
        while !Task.isCancelled {
            do {
                let events = try await api.pollEvents(since: lastEventID)
                guard !Task.isCancelled else { break }
                var shouldRefresh = false
                for event in events {
                    lastEventID = max(lastEventID, event.id)
                    if event.shouldRefreshOverview {
                        shouldRefresh = true
                    }
                }
                if shouldRefresh {
                    await refresh()
                }
            } catch {
                // Network error or timeout — back off briefly then retry.
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
            }
        }
    }
}
