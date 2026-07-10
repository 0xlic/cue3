import Foundation

@MainActor
final class CueActionCoordinator {
    private let store: CueStore
    private let panelController: PanelController
    private let applicationTracker: FrontmostApplicationTracker
    private let selectionCaptureService: SelectionCaptureService
    private let pasteService: CuePasteService
    private var captureTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?

    init(
        store: CueStore,
        panelController: PanelController,
        applicationTracker: FrontmostApplicationTracker,
        selectionCaptureService: SelectionCaptureService,
        pasteService: CuePasteService
    ) {
        self.store = store
        self.panelController = panelController
        self.applicationTracker = applicationTracker
        self.selectionCaptureService = selectionCaptureService
        self.pasteService = pasteService
    }

    func startNewCue() {
        do {
            let cue = try store.startNewCue()
            panelController.showNewCue(cueID: cue.id)
        } catch {
            present(error, cueID: store.currentCueID)
        }
    }

    func captureSelection(source: SelectionCaptureService.CaptureSource) {
        guard captureTask == nil else {
            present(
                SelectionCaptureService.CaptureError.captureInProgress,
                cueID: store.currentCueID
            )
            return
        }

        captureTask = Task { @MainActor [weak self] in
            await self?.performCapture(source: source)
        }
    }

    func pasteCue(cueID: UUID) {
        guard pasteTask == nil else {
            present(CuePasteService.PasteError.pasteInProgress, cueID: cueID)
            return
        }

        pasteTask = Task { @MainActor [weak self] in
            await self?.performPaste(cueID: cueID)
        }
    }

    private func performCapture(source: SelectionCaptureService.CaptureSource) async {
        defer { captureTask = nil }
        do {
            let text = try await selectionCaptureService.captureSelectedText(
                from: applicationTracker.lastExternalApplication,
                source: source
            )
            let item = try store.appendItem(quoteText: text, annotationText: nil)
            panelController.refreshAfterCapture(cueID: item.cueID)
        } catch is CancellationError {
            return
        } catch {
            present(error, cueID: store.currentCueID)
        }
    }

    private func performPaste(cueID: UUID) async {
        defer { pasteTask = nil }
        do {
            let text = try store.cueOutputText(cueID: cueID)
            let target = CuePasteService.resolveTarget(
                latestExternalApplication: applicationTracker.lastExternalApplication,
                rememberedApplication: panelController.state.targetApplication
            )
            try await pasteService.paste(text, to: target)
            panelController.hide()
        } catch is CancellationError {
            return
        } catch {
            present(error, cueID: cueID)
        }
    }

    private func present(_ error: Error, cueID: UUID?) {
        store.errorMessage = error.localizedDescription
        if !panelController.isVisible {
            panelController.show(cueID: cueID, activatingPanel: false)
        }
    }
}
