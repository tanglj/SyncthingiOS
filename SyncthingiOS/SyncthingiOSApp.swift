import BackgroundTasks
import SwiftUI

@main
struct SyncthingiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings()
    @StateObject private var store = SyncthingStore()
    @StateObject private var core = SyncthingCoreManager()
    private let backgroundSync: BackgroundSyncManager?

    init() {
        let core = SyncthingCoreManager()
        _core = StateObject(wrappedValue: core)
        let bg = BackgroundSyncManager(core: core)
        backgroundSync = bg
        _store = StateObject(wrappedValue: SyncthingStore())
        _settings = StateObject(wrappedValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(core)
                .task {
                    backgroundSync?.register()
                    await core.start()
                    if core.state.isRunning {
                        settings.useEmbeddedCore()
                        // Embedded core restart: stop+start instead of REST
                        // /rest/system/restart (which permanently kills the
                        // in-process core because there is no monitor).
                        store.embeddedRestart = {
                            await core.stop()
                            await core.start()
                        }
                    }
                    store.configure(with: settings.snapshot)
                    await store.refresh()
                    await store.startEventLoop()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task {
                            backgroundSync?.cancelBackgroundSync()
                            await core.start()
                            if core.state.isRunning {
                                settings.useEmbeddedCore()
                                store.configure(with: settings.snapshot)
                                await store.refresh()
                                await store.startEventLoop()
                            }
                        }
                    case .background:
                        Task {
                            await store.stopEventLoop()
                            backgroundSync?.scheduleBackgroundSync()
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
