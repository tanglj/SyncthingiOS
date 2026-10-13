import BackgroundTasks
import Foundation

/// Manages background sync via BGTaskScheduler.
/// On entering background, schedules a BGProcessingTask that briefly starts
/// the embedded core so pending sync work can complete.
@MainActor
final class BackgroundSyncManager {
    static let taskIdentifier = "me.tanglj.SyncthingiOS.background-sync"

    private let core: SyncthingCoreManager

    init(core: SyncthingCoreManager) {
        self.core = core
    }

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { await self.handle(task: task) }
        }
    }

    func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 min from now
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Non-fatal: background sync is opportunistic.
        }
    }

    func cancelBackgroundSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func handle(task: BGProcessingTask) async {
        let expirationHandler = { task.setTaskCompleted(success: false) }
        task.expirationHandler = expirationHandler

        // Start core if not running, let it sync briefly, then stop.
        if !core.state.isRunning {
            await core.start()
        }

        // Give the core a window to do useful work.
        try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 s

        if core.state.isRunning {
            await core.stop()
        }

        // Schedule the next background sync.
        scheduleBackgroundSync()
        task.setTaskCompleted(success: true)
    }
}
