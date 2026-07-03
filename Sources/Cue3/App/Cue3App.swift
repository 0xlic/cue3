import AppKit
import ServiceManagement
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
    private let lifecycleCoordinator: LifecycleCoordinator
    private let applicationTracker: FrontmostApplicationTracker
    private let selectionCaptureService: SelectionCaptureService
    private let globalHotKeyController: GlobalHotKeyController
    private let statusBarController: StatusBarController

    init() {
        do {
            let storeURL = try Self.modelStoreURL()
            let configuration = ModelConfiguration(
                "Cue3",
                schema: Cue3Schema.schema,
                url: storeURL
            )
            let container = try ModelContainer(
                for: Cue3Schema.schema,
                configurations: [configuration]
            )
            let settings = AppSettings()
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
            let lifecycleCoordinator = LifecycleCoordinator(store: store)
            Self.applyAppearanceMode(settings.appearanceMode)
            try? Self.setLaunchAtLogin(enabled: settings.launchAtLoginEnabled)
            self.container = container
            self.settings = settings
            self.store = store
            self.panelController = panelController
            self.settingsWindowController = settingsWindowController
            self.lifecycleCoordinator = lifecycleCoordinator
            let selectionCaptureService = SelectionCaptureService()
            self.applicationTracker = applicationTracker
            self.selectionCaptureService = selectionCaptureService
            panelController.state.captureSelection = { [store, panelController, applicationTracker, selectionCaptureService] in
                Task { @MainActor in
                    await Self.captureSelection(
                        store: store,
                        panelController: panelController,
                        applicationTracker: applicationTracker,
                        selectionCaptureService: selectionCaptureService,
                        source: .panel
                    )
                }
            }
            panelController.state.openSettings = { [weak panelController, settingsWindowController] in
                settingsWindowController.show(on: panelController?.screen)
            }
            let globalHotKeyController = GlobalHotKeyController(
                captureShortcut: settings.captureShortcut,
                openShortcut: settings.openShortcut,
                newCueShortcut: settings.newCueShortcut,
                cueShortcut: settings.cueShortcut,
                captureHandler: { [store, panelController, applicationTracker, selectionCaptureService] in
                    Task { @MainActor in
                        await Self.captureSelection(
                            store: store,
                            panelController: panelController,
                            applicationTracker: applicationTracker,
                            selectionCaptureService: selectionCaptureService,
                            source: .hotKey
                        )
                    }
                },
                openHandler: { [store, panelController] in
                    panelController.show(cueID: store.currentCueID, activatingPanel: true)
                },
                newCueHandler: { [store, panelController] in
                    Self.startNewCue(store: store, panelController: panelController)
                },
                cueHandler: { [store, panelController, applicationTracker] in
                    Self.pasteCueOutput(
                        store: store,
                        panelController: panelController,
                        targetApplication: applicationTracker.lastExternalApplication
                    )
                }
            )
            settings.onShortcutsChanged = { [weak globalHotKeyController, weak settings] in
                guard let globalHotKeyController, let settings else {
                    return
                }
                globalHotKeyController.updateShortcuts(
                    capture: settings.captureShortcut,
                    open: settings.openShortcut,
                    newCue: settings.newCueShortcut,
                    cue: settings.cueShortcut
                )
            }
            settings.onAppearanceModeChanged = { appearanceMode in
                Self.applyAppearanceMode(appearanceMode)
            }
            settings.onLaunchAtLoginChanged = { enabled in
                try? Self.setLaunchAtLogin(enabled: enabled)
            }
            self.globalHotKeyController = globalHotKeyController
            self.statusBarController = StatusBarController { [store, panelController] in
                panelController.show(cueID: store.currentCueID, activatingPanel: true)
            }
            applicationDelegate.handleDidFinishLaunching = { [settings, store, panelController] in
                Self.completeLaunch(
                    settings: settings,
                    store: store,
                    panelController: panelController
                )
            }
        } catch {
            fatalError("无法创建 Cue3 数据容器：\(error.localizedDescription)")
        }
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

    private static func startNewCue(
        store: CueStore,
        panelController: PanelController
    ) {
        do {
            let cue = try store.startNewCue()
            panelController.showNewCue(cueID: cue.id)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private static func captureSelection(
        store: CueStore,
        panelController: PanelController,
        applicationTracker: FrontmostApplicationTracker,
        selectionCaptureService: SelectionCaptureService,
        source: SelectionCaptureService.CaptureSource
    ) async {
        do {
            let text = try await selectionCaptureService.captureSelectedText(
                from: applicationTracker.lastExternalApplication,
                source: source
            )
            let item = try store.appendItem(quoteText: text, annotationText: nil)
            panelController.refreshAfterCapture(cueID: item.cueID)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private static func pasteCueOutput(
        store: CueStore,
        panelController: PanelController,
        targetApplication: NSRunningApplication?
    ) {
        guard let cueID = store.currentCueID else {
            store.errorMessage = "当前没有可输出的 Cue。"
            return
        }
        guard let targetApplication else {
            store.errorMessage = "找不到可粘贴的目标应用。请先切回需要输入的应用后再使用 Cue 快捷键。"
            return
        }

        do {
            let text = try store.cueOutputText(cueID: cueID)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            panelController.hide()

            if isFrontmost(targetApplication) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    postCommandV()
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let activated = targetApplication.activate(options: [])
                guard activated else {
                    store.errorMessage = "无法切回目标应用，未执行粘贴。"
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    postCommandV()
                }
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private static func applyAppearanceMode(_ appearanceMode: AppSettings.AppearanceMode) {
        NSApp.appearance = appearanceMode.appearance
    }

    private static func setLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    private static func completeLaunch(
        settings: AppSettings,
        store: CueStore,
        panelController: PanelController
    ) {
        closeUnexpectedStartupWindows(except: panelController.window)

        if settings.shouldShowMainPanelOnLaunch {
            panelController.show(cueID: store.currentCueID, activatingPanel: true)
        }

        settings.markInitialLaunchCompleted()
    }

    private static func closeUnexpectedStartupWindows(except panelWindow: NSWindow) {
        for window in NSApp.windows where window !== panelWindow && window.isVisible {
            window.orderOut(nil)
        }
    }

}

private func postCommandV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

private func isFrontmost(_ application: NSRunningApplication) -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
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
            statusItem.popUpMenu(menu)
            return
        }
        action()
    }

    @objc
    private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
