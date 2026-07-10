import AppKit
import CoreGraphics

@MainActor
final class CuePasteService {
    enum PasteError: LocalizedError {
        case pasteInProgress
        case noTargetApplication
        case targetApplicationUnavailable
        case targetActivationFailed
        case pasteboardWriteFailed

        var errorDescription: String? {
            switch self {
            case .pasteInProgress:
                return "上一次 Cue 粘贴仍在进行，请稍后再试。"
            case .noTargetApplication:
                return "找不到可粘贴的目标应用。请先切回需要输入的应用后再试。"
            case .targetApplicationUnavailable:
                return "之前选择的目标应用已经退出，请切回需要输入的应用后再试。"
            case .targetActivationFailed:
                return "无法切回目标应用，未执行粘贴。Cue 内容已保留在剪贴板中。"
            case .pasteboardWriteFailed:
                return "无法把 Cue 内容写入剪贴板。"
            }
        }
    }

    private let pasteboard: NSPasteboard
    private var isPasting = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func paste(_ text: String, to application: NSRunningApplication?) async throws {
        guard !isPasting else {
            throw PasteError.pasteInProgress
        }
        guard let application else {
            throw PasteError.noTargetApplication
        }
        guard !application.isTerminated else {
            throw PasteError.targetApplicationUnavailable
        }

        isPasting = true
        defer { isPasting = false }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteError.pasteboardWriteFailed
        }

        if isFrontmost(application) {
            try await Task.sleep(nanoseconds: 80_000_000)
        } else {
            guard application.activate(options: []) else {
                throw PasteError.targetActivationFailed
            }
            try await Task.sleep(nanoseconds: 160_000_000)
            guard isFrontmost(application) else {
                throw PasteError.targetActivationFailed
            }
        }

        try Task.checkCancellation()
        postCommandV()
    }

    static func resolveTarget(
        frontmostApplication: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        latestExternalApplication: NSRunningApplication?,
        rememberedApplication: NSRunningApplication?
    ) -> NSRunningApplication? {
        let candidates = [
            frontmostApplication,
            latestExternalApplication,
            rememberedApplication
        ]
        return candidates
            .compactMap { $0 }
            .first(where: isUsableExternalApplication)
    }

    private static func isUsableExternalApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && !application.isTerminated
    }

    private func isFrontmost(_ application: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
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
