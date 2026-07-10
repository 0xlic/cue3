import AppKit
import Foundation

@MainActor
final class LifecycleCoordinator {
    private let store: CueStore
    private var activeObserver: NSObjectProtocol?
    private var cleanupTimer: Timer?

    init(store: CueStore) {
        self.store = store

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupAndSchedule()
            }
        }
        cleanupAndSchedule()
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        cleanupTimer?.invalidate()
    }

    private func cleanupAndSchedule() {
        do {
            try store.cleanupExpiredCues()
        } catch {
            store.errorMessage = error.localizedDescription
        }
        scheduleNextCleanup()
    }

    private func scheduleNextCleanup() {
        cleanupTimer?.invalidate()
        let timer = Timer(fire: Date().addingTimeInterval(60 * 60), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupAndSchedule()
            }
        }
        cleanupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
