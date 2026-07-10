import Foundation
import ServiceManagement

@MainActor
final class SystemIntegrationCoordinator {
    private let settings: AppSettings
    private let globalHotKeyController: GlobalHotKeyController
    let startupErrorMessage: String?

    init(
        settings: AppSettings,
        captureHandler: @escaping () -> Void,
        openHandler: @escaping () -> Void,
        newCueHandler: @escaping () -> Void,
        cueHandler: @escaping () -> Void
    ) {
        self.settings = settings

        var startupErrors: [String] = []
        let requestedLaunchAtLogin = settings.launchAtLoginEnabled
        let actualLaunchAtLogin = Self.isLaunchAtLoginEnabled
        if requestedLaunchAtLogin && !actualLaunchAtLogin {
            let message = "开机自启动尚未生效，请在系统设置的“登录项”中确认。"
            settings.reconcileLaunchAtLogin(
                enabled: actualLaunchAtLogin,
                errorMessage: message
            )
            startupErrors.append(message)
        } else {
            settings.reconcileLaunchAtLogin(enabled: actualLaunchAtLogin)
        }

        let hotKeyController = GlobalHotKeyController(
            captureShortcut: settings.captureShortcut,
            openShortcut: settings.openShortcut,
            newCueShortcut: settings.newCueShortcut,
            cueShortcut: settings.cueShortcut,
            captureHandler: captureHandler,
            openHandler: openHandler,
            newCueHandler: newCueHandler,
            cueHandler: cueHandler
        )
        globalHotKeyController = hotKeyController
        if let message = hotKeyController.registrationErrorMessage {
            settings.presentSystemError(message)
            startupErrors.append(message)
        }
        startupErrorMessage = startupErrors.isEmpty
            ? nil
            : startupErrors.joined(separator: "\n\n")

        settings.onShortcutsChanged = { [weak self] in
            self?.updateShortcuts()
        }
        settings.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.updateLaunchAtLogin(enabled: enabled)
        }
    }

    private func updateShortcuts() {
        globalHotKeyController.updateShortcuts(
            capture: settings.captureShortcut,
            open: settings.openShortcut,
            newCue: settings.newCueShortcut,
            cue: settings.cueShortcut
        )
        if let message = globalHotKeyController.registrationErrorMessage {
            settings.presentSystemError(message)
        }
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            try Self.setLaunchAtLogin(enabled: enabled)
            let actualEnabled = Self.isLaunchAtLoginEnabled
            let message = actualEnabled == enabled
                ? nil
                : "开机自启动需要在系统设置的“登录项”中进一步确认。"
            settings.reconcileLaunchAtLogin(
                enabled: actualEnabled,
                errorMessage: message
            )
        } catch {
            settings.reconcileLaunchAtLogin(
                enabled: Self.isLaunchAtLoginEnabled,
                errorMessage: "无法更新开机自启动：\(error.localizedDescription)"
            )
        }
    }

    private static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private static func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                break
            default:
                try SMAppService.mainApp.register()
            }
        } else {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        }
    }
}
