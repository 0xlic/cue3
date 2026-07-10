import AppKit
import SwiftData
import SwiftUI

@main
@MainActor
struct Cue3App: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    private let container: ModelContainer
    private let settings: AppSettings
    private let store: CueStore
    private let panelController: PanelController
    private let settingsWindowController: SettingsWindowController
    private let lifecycleCoordinator: LifecycleCoordinator?
    private let actionCoordinator: CueActionCoordinator
    private let systemIntegrationCoordinator: SystemIntegrationCoordinator?
    private let statusBarController: StatusBarController?

    init() {
        let isRunningTests = Self.isRunningTests
        let container: ModelContainer
        let startupErrorMessage: String?

        if isRunningTests {
            do {
                container = try Self.inMemoryModelContainer(name: "Cue3TestsHost")
                startupErrorMessage = nil
            } catch {
                fatalError("无法创建 Cue3 测试数据容器：\(error.localizedDescription)")
            }
        } else {
            do {
                container = try Self.persistentModelContainer()
                startupErrorMessage = nil
            } catch {
                let persistentError = error
                do {
                    container = try Self.inMemoryModelContainer(name: "Cue3Recovery")
                    startupErrorMessage = "无法打开本地 Cue 数据：\(persistentError.localizedDescription)\n\nCue3 已进入临时模式，本次运行中的更改不会保存。原数据没有被删除；请备份 ~/Library/Application Support/Cue3 后再处理或重建存储。"
                } catch {
                    fatalError("持久化和临时数据容器均创建失败：\(error.localizedDescription)")
                }
            }
        }

        let settingsDefaults: UserDefaults
        if isRunningTests {
            let suiteName = "Cue3Tests.Host"
            settingsDefaults = UserDefaults(suiteName: suiteName) ?? .standard
            settingsDefaults.removePersistentDomain(forName: suiteName)
        } else {
            settingsDefaults = .standard
        }

        let settings = AppSettings(userDefaults: settingsDefaults)
        let settingsWindowController = SettingsWindowController(settings: settings)
        let store = CueStore(
            context: container.mainContext,
            cuePromptProvider: { settings.resolvedCuePromptTemplate }
        )
        let applicationTracker = FrontmostApplicationTracker()
        let panelController = PanelController(
            store: store,
            isPinned: settings.panelIsPinned,
            onPinnedChange: { [settings] isPinned in
                settings.panelIsPinned = isPinned
            }
        )
        panelController.state.fallbackTargetApplication = {
            applicationTracker.lastExternalApplication
        }

        let actionCoordinator = CueActionCoordinator(
            store: store,
            panelController: panelController,
            applicationTracker: applicationTracker,
            selectionCaptureService: SelectionCaptureService(),
            pasteService: CuePasteService()
        )
        panelController.state.captureSelection = { [actionCoordinator] in
            actionCoordinator.captureSelection(source: .panel)
        }
        panelController.state.pasteCue = { [actionCoordinator] cueID in
            actionCoordinator.pasteCue(cueID: cueID)
        }
        panelController.state.openSettings = { [weak panelController, settingsWindowController] in
            settingsWindowController.show(on: panelController?.screen)
        }

        Self.applyAppearanceMode(settings.appearanceMode)
        settings.onAppearanceModeChanged = { appearanceMode in
            Self.applyAppearanceMode(appearanceMode)
        }

        let lifecycleCoordinator = isRunningTests ? nil : LifecycleCoordinator(store: store)
        let systemIntegrationCoordinator: SystemIntegrationCoordinator?
        let statusBarController: StatusBarController?
        if isRunningTests {
            systemIntegrationCoordinator = nil
            statusBarController = nil
        } else {
            systemIntegrationCoordinator = SystemIntegrationCoordinator(
                settings: settings,
                captureHandler: { [actionCoordinator] in
                    actionCoordinator.captureSelection(source: .hotKey)
                },
                openHandler: { [store, panelController] in
                    panelController.show(cueID: store.currentCueID, activatingPanel: true)
                },
                newCueHandler: { [actionCoordinator] in
                    actionCoordinator.startNewCue()
                },
                cueHandler: { [store, panelController, actionCoordinator] in
                    guard let cueID = store.currentCueID else {
                        store.errorMessage = "当前没有可输出的 Cue。"
                        panelController.show(cueID: nil, activatingPanel: false)
                        return
                    }
                    actionCoordinator.pasteCue(cueID: cueID)
                }
            )
            statusBarController = StatusBarController { [store, panelController] in
                panelController.show(cueID: store.currentCueID, activatingPanel: true)
            }
        }

        self.container = container
        self.settings = settings
        self.store = store
        self.panelController = panelController
        self.settingsWindowController = settingsWindowController
        self.lifecycleCoordinator = lifecycleCoordinator
        self.actionCoordinator = actionCoordinator
        self.systemIntegrationCoordinator = systemIntegrationCoordinator
        self.statusBarController = statusBarController

        if !isRunningTests {
            let launchErrorMessage = [
                startupErrorMessage,
                systemIntegrationCoordinator?.startupErrorMessage
            ]
                .compactMap { $0 }
                .joined(separator: "\n\n")
            applicationDelegate.handleDidFinishLaunching = { [settings, store, panelController] in
                Self.completeLaunch(
                    settings: settings,
                    store: store,
                    panelController: panelController,
                    startupErrorMessage: launchErrorMessage.isEmpty ? nil : launchErrorMessage
                )
            }
        }
    }

    private static func persistentModelContainer() throws -> ModelContainer {
        let storeURL = try modelStoreURL()
        let configuration = ModelConfiguration(
            "Cue3",
            schema: Cue3Schema.schema,
            url: storeURL
        )
        return try Cue3Schema.makeContainer(configurations: [configuration])
    }

    private static func inMemoryModelContainer(name: String) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            name,
            schema: Cue3Schema.schema,
            isStoredInMemoryOnly: true
        )
        return try Cue3Schema.makeContainer(configurations: [configuration])
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CUE3_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
    }

    private static func modelStoreURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("Cue3", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appendingPathComponent("Cue3.store")
    }

    var body: some Scene {
        Settings {
            SettingsRootView(settings: settings)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    settingsWindowController.show(on: panelController.screen)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private static func applyAppearanceMode(_ appearanceMode: AppSettings.AppearanceMode) {
        NSApp.appearance = appearanceMode.appearance
    }

    private static func completeLaunch(
        settings: AppSettings,
        store: CueStore,
        panelController: PanelController,
        startupErrorMessage: String?
    ) {
        closeUnexpectedStartupWindows(except: panelController.window)

        let cueID: UUID?
        do {
            cueID = try store.ensureCurrentCue().id
        } catch {
            store.errorMessage = error.localizedDescription
            cueID = store.currentCueID
        }

        if let startupErrorMessage {
            store.errorMessage = startupErrorMessage
            panelController.show(cueID: cueID, activatingPanel: true)
        } else if settings.shouldShowMainPanelOnLaunch {
            panelController.show(cueID: cueID, activatingPanel: true)
        }

        settings.markInitialLaunchCompleted()
    }

    private static func closeUnexpectedStartupWindows(except panelWindow: NSWindow) {
        for window in NSApp.windows where window !== panelWindow && window.isVisible {
            window.orderOut(nil)
        }
    }

}

@MainActor
private final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.window = window
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsRootView(settings: settings) { [weak window] size in
                Self.updateWindow(window, contentSize: size)
            }
        )
    }

    func show(on screen: NSScreen?) {
        NSApp.activate(ignoringOtherApps: true)
        position(on: screen)
        window.makeKeyAndOrderFront(nil)
    }

    private func position(on screen: NSScreen?) {
        guard let screen else {
            if !window.isVisible {
                window.center()
            }
            return
        }

        let visibleFrame = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        window.setFrame(frame, display: false)
    }

    private static func updateWindow(_ window: NSWindow?, contentSize: CGSize) {
        guard let window else {
            return
        }

        let currentFrame = window.frame
        let currentContentSize = window.contentRect(forFrameRect: currentFrame).size
        guard currentContentSize != contentSize else {
            return
        }

        var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        targetFrame.origin.x = currentFrame.midX - targetFrame.width / 2
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height
        window.setFrame(targetFrame, display: true, animate: window.isVisible)
    }
}

private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var handleDidFinishLaunching: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in
            self?.handleDidFinishLaunching?()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

@MainActor
private final class StatusBarController {
    private let statusItem: NSStatusItem
    private let action: () -> Void
    private let menu: NSMenu

    init(action: @escaping () -> Void) {
        self.action = action
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        configureMenu()
        configureButton()
    }

    private func configureMenu() {
        let quitItem = NSMenuItem(
            title: "退出 Cue3",
            action: #selector(handleQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Cue3")
        button.image?.isTemplate = true
        button.toolTip = "显示主面板"
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let button = statusItem.button else { return }
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height + 4),
                in: button
            )
            return
        }
        action()
    }

    @objc
    private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
