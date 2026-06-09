import Foundation
import UIKit

#if canImport(Ioscore)
import Ioscore
#endif

enum SyncthingCoreState: Equatable {
    case stopped
    case starting
    case stopping
    case running
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .stopped:
            return "Core stopped"
        case .starting:
            return "Starting core"
        case .stopping:
            return "Stopping core"
        case .running:
            return "Core running"
        case .unavailable:
            return "Core not bundled"
        case .failed:
            return "Core failed"
        }
    }

    var message: String {
        switch self {
        case .stopped:
            return "Start the embedded Syncthing core to sync from this iPhone."
        case .starting:
            return "Preparing the local Syncthing home and REST API."
        case .stopping:
            return "Shutting down the embedded Syncthing core."
        case .running:
            return "Syncthing is running locally in the foreground and the REST API is reachable."
        case .unavailable(let reason), .failed(let reason):
            return reason
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    var isStopping: Bool {
        if case .stopping = self { return true }
        return false
    }

    var canStart: Bool {
        !isRunning && !isStarting && !isStopping
    }
}

@MainActor
final class SyncthingCoreManager: ObservableObject {
    static let localBaseURLString = "http://127.0.0.1:8384"
    static let localAPIKey = "ios-local-syncthing-core"

    @Published private(set) var state: SyncthingCoreState = .stopped {
        didSet {
            writeDebugStatus()
        }
    }
    private var startSequence = 0
    private var activeSyncRootURL: URL?

    var localSnapshot: SyncthingSnapshot {
        SyncthingSnapshot(
            baseURL: URL(string: Self.localBaseURLString)!,
            apiKey: Self.localAPIKey
        )
    }

    var syncRootURL: URL? {
        try? localSyncRootURL()
    }

    init() {
        writeDebugStatus()
    }

    func start() async {
        #if canImport(Ioscore)
        if state.isRunning {
            if IoscorePing() {
                return
            }
            state = .starting
            do {
                try await Task.detached(priority: .userInitiated) {
                    try waitForCoreReadiness()
                }.value
                state = .running
                return
            } catch {
                state = .stopped
            }
        }
        #endif

        guard state.canStart else { return }
        state = .starting
        startSequence += 1
        let sequence = startSequence

        #if canImport(Ioscore)
        do {
            let homeURL = try localHomeURL()
            let syncRootURL = try localSyncRootURL()
            let localBaseURLString = Self.localBaseURLString
            let localAPIKey = Self.localAPIKey
            let deviceName = UIDevice.current.name
            try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
            activeSyncRootURL = syncRootURL
            try FileManager.default.createDirectory(at: syncRootURL, withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) {
                var error: NSError?
                let didStart = IoscoreStartWithConfigDeviceNameAndSyncRoot(
                    homeURL.path,
                    localBaseURLString,
                    localAPIKey,
                    deviceName,
                    syncRootURL.path,
                    &error
                )
                if let error {
                    throw error
                }
                if !didStart {
                    throw SyncthingCoreManagerError.startFailed
                }
                try waitForCoreReadiness()
            }.value
            guard sequence == startSequence else { return }
            state = .running
        } catch {
            guard sequence == startSequence else { return }
            state = .failed(error.localizedDescription)
        }
        #else
        state = .unavailable("Syncthing core framework has not been generated yet. Run Scripts/build-ios-core.sh, then rebuild the app.")
        #endif
    }

    func stop() async {
        guard state.isRunning || state.isStarting else { return }
        startSequence += 1
        state = .stopping
        #if canImport(Ioscore)
        await Task.detached(priority: .userInitiated) {
            IoscoreStop()
        }.value
        #endif
        activeSyncRootURL = nil
        state = .stopped
    }

    private func localHomeURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("SyncthingCore", isDirectory: true)
    }

    private func localSyncRootURL() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documentsURL.appendingPathComponent("Syncthing", isDirectory: true)
    }

    private func writeDebugStatus() {
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let url = documentsURL.appendingPathComponent("CoreStatus.json")
            var payload: [String: Any] = [
                "stateTitle": state.title,
                "stateMessage": state.message,
                "updatedAt": ISO8601DateFormatter().string(from: Date()),
                "localBaseURL": Self.localBaseURLString,
                "syncRoot": (activeSyncRootURL ?? (try? localSyncRootURL()))?.path ?? ""
            ]

            #if canImport(Ioscore)
            payload["bridgeStatus"] = IoscoreStatus()
            payload["bridgeIsStarting"] = IoscoreIsStarting()
            payload["bridgeIsRunning"] = IoscoreIsRunning()
            payload["bridgePing"] = IoscorePing()
            payload["bridgeLastError"] = IoscoreLastError()
            #endif

            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            // Debug status is best-effort and should never affect app behavior.
        }
    }
}

private enum SyncthingCoreManagerError: LocalizedError {
    case startFailed
    case restAPITimeout
    case startupFailed(String)

    var errorDescription: String? {
        switch self {
        case .startFailed:
            return "Syncthing core did not start."
        case .restAPITimeout:
            return "Syncthing core started, but the local REST API did not become reachable."
        case .startupFailed(let message):
            return message
        }
    }
}

#if canImport(Ioscore)
private func waitForCoreReadiness() throws {
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
        if IoscorePing() {
            return
        }
        let lastError = IoscoreLastError()
        if !lastError.isEmpty {
            throw SyncthingCoreManagerError.startupFailed(lastError)
        }
        if !IoscoreIsStarting() && !IoscoreIsRunning() {
            throw SyncthingCoreManagerError.startFailed
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    throw SyncthingCoreManagerError.restAPITimeout
}
#endif
