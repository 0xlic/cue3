import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PanelState {
    var selectedCueID: UUID?
    var isPinned: Bool
    @ObservationIgnored var targetApplication: NSRunningApplication?
    @ObservationIgnored var fallbackTargetApplication: (() -> NSRunningApplication?)?
    @ObservationIgnored var hidePanel: (() -> Void)?
    @ObservationIgnored var pinnedDidChange: ((Bool) -> Void)?
    @ObservationIgnored var captureSelection: (() -> Void)?
    @ObservationIgnored var pasteCue: ((UUID) -> Void)?
    @ObservationIgnored var openSettings: (() -> Void)?

    init(isPinned: Bool = true) {
        self.isPinned = isPinned
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        pinnedDidChange?(pinned)
    }

    var resolvedTargetApplication: NSRunningApplication? {
        CuePasteService.resolveTarget(
            latestExternalApplication: fallbackTargetApplication?(),
            rememberedApplication: targetApplication
        )
    }

    func rememberTargetApplication(_ application: NSRunningApplication?) {
        guard let application, isExternalApplication(application) else { return }
        targetApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let preferredPanelWidth: CGFloat = 340

    private let panel: CuePanel
    let state: PanelState

    var isVisible: Bool { panel.isVisible }
    var screen: NSScreen? { panel.screen }
    var window: NSWindow { panel }

    init(
        store: CueStore,
        isPinned: Bool = true,
        onPinnedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        state = PanelState(isPinned: isPinned)
        panel = CuePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.preferredPanelWidth, height: 680),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.level = isPinned ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 300, height: 500)
        panel.setFrameAutosaveName("Cue3FloatingPanel")
        panel.contentView = PanelHostingView(rootView: MainPanelView(store: store, panelState: state))
        state.pinnedDidChange = { [weak panel] isPinned in
            panel?.level = isPinned ? .floating : .normal
            onPinnedChange(isPinned)
        }
        state.hidePanel = { [weak self] in
            self?.hide()
        }

        if !panel.setFrameUsingName("Cue3FloatingPanel") {
            positionDefault()
        }
        applyPreferredWidth()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show(cueID: UUID? = nil, activatingPanel: Bool = false) {
        rememberCurrentTarget()
        selectCue(cueID)
        showPanel(activatingPanel: activatingPanel)
    }

    func showNewCue(cueID: UUID) {
        state.setPinned(true)
        rememberCurrentTarget()
        selectCue(cueID)
        showPanel(activatingPanel: false)
    }

    func refreshAfterCapture(cueID: UUID) {
        rememberCurrentTarget()
        selectCue(cueID)
        if state.isPinned {
            showPanel(activatingPanel: false)
        }
    }

    private func rememberCurrentTarget() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        state.rememberTargetApplication(frontmostApplication)
    }

    private func selectCue(_ cueID: UUID?) {
        if let cueID {
            state.selectedCueID = cueID
        }
    }

    private func showPanel(activatingPanel: Bool) {
        if activatingPanel {
            NSApplication.shared.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResize(_ notification: Notification) {
        panel.saveFrame(usingName: "Cue3FloatingPanel")
        panel.invalidateShadow()
    }

    func windowDidMove(_ notification: Notification) {
        panel.saveFrame(usingName: "Cue3FloatingPanel")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }

    private func positionDefault() {
        let currentFrame = panel.frame
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let margin: CGFloat = 12
        let x = visibleFrame.maxX - currentFrame.width - margin
        let y = visibleFrame.minY + ((visibleFrame.height - currentFrame.height) / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func applyPreferredWidth() {
        var frame = panel.frame
        guard frame.width > Self.preferredPanelWidth else { return }
        frame.origin.x += frame.width - Self.preferredPanelWidth
        frame.size.width = Self.preferredPanelWidth
        panel.setFrame(frame, display: true)
    }
}

private final class CuePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
