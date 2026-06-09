import SwiftUI

@main
struct SyncthingiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings()
    @StateObject private var store = SyncthingStore()
    @StateObject private var core = SyncthingCoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(core)
                .task {
                    await core.start()
                    if core.state.isRunning {
                        settings.useEmbeddedCore()
                    }
                    store.configure(with: settings.snapshot)
                    await store.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task {
                            await core.start()
                            if core.state.isRunning {
                                settings.useEmbeddedCore()
                                store.configure(with: settings.snapshot)
                                await store.refresh()
                            }
                        }
                    case .background:
                        break
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
