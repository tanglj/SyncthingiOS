import SwiftUI

@main
struct SyncthingiOSApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = SyncthingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .task {
                    store.configure(with: settings.snapshot)
                    await store.refresh()
                }
        }
    }
}
