import AppKit

@MainActor
final class FrontmostApplicationTracker {
    private var observer: NSObjectProtocol?
    private let bundleIdentifier = Bundle.main.bundleIdentifier

    private(set) var lastExternalApplication: NSRunningApplication?

    init(workspace: NSWorkspace = .shared) {
        update(with: workspace.frontmostApplication)
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.update(with: application)
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func update(with application: NSRunningApplication?) {
        guard application?.bundleIdentifier != bundleIdentifier else {
            return
        }
        lastExternalApplication = application
    }
}
