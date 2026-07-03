import AppKit
import CoreGraphics
import OSLog

@MainActor
final class SelectionCaptureService {
    enum CaptureSource: String {
        case menu
        case hotKey
        case panel
    }

    enum CaptureError: LocalizedError {
        case accessibilityPermissionRequired(String)
        case noTargetApplication
        case noSelectedText

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired(let identity):
                return "系统仍未授予当前运行的 Cue3 辅助功能权限。请确认系统设置中授权的是这个程序：\(identity)"
            case .noTargetApplication:
                return "找不到可捕获文本的前台应用。"
            case .noSelectedText:
                return "没有可捕获的选中文本。"
            }
        }
    }

    private let logger = Logger(subsystem: "com.0xlic.cue3", category: "SelectionCapture")

    func captureSelectedText(
        from application: NSRunningApplication?,
        source: CaptureSource
    ) async throws -> String {
        guard let application else {
            logger.error("capture failed source=\(source.rawValue, privacy: .public) reason=noTargetApplication frontmost=\(self.frontmostDescription(), privacy: .public)")
            throw CaptureError.noTargetApplication
        }

        let axTrusted = AXIsProcessTrusted()
        let identity = currentProcessIdentityDescription()
        logger.notice("capture start source=\(source.rawValue, privacy: .public) target=\(self.applicationDescription(application), privacy: .public) frontmost=\(self.frontmostDescription(), privacy: .public) axTrusted=\(axTrusted) modifiers=\(self.modifierDescription(), privacy: .public) identity=\(identity, privacy: .public)")

        guard axTrusted else {
            requestAccessibilityTrustPrompt()
            logger.error("capture failed source=\(source.rawValue, privacy: .public) reason=accessibilityPermissionRequired target=\(self.applicationDescription(application), privacy: .public) identity=\(identity, privacy: .public)")
            throw CaptureError.accessibilityPermissionRequired(identity)
        }

        if let accessibilityText = selectedTextViaAccessibility(from: application) {
            logger.notice("capture success source=\(source.rawValue, privacy: .public) method=accessibility textLength=\(accessibilityText.count)")
            return accessibilityText
        }
        logger.notice("capture accessibility empty source=\(source.rawValue, privacy: .public) target=\(self.applicationDescription(application), privacy: .public)")

        let modifiersCleared = await waitForCaptureModifiersToClear()
        logger.notice("capture modifiers source=\(source.rawValue, privacy: .public) cleared=\(modifiersCleared) modifiers=\(self.modifierDescription(), privacy: .public)")

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        logger.notice("capture pasteboard snapshot source=\(source.rawValue, privacy: .public) items=\(snapshot.itemCount) types=\(snapshot.typeDescription, privacy: .public)")

        pasteboard.clearContents()
        let emptyChangeCount = pasteboard.changeCount

        application.activate(options: [])
        try await Task.sleep(nanoseconds: 120_000_000)
        logger.notice("capture activated source=\(source.rawValue, privacy: .public) target=\(self.applicationDescription(application), privacy: .public) frontmost=\(self.frontmostDescription(), privacy: .public) changeCount=\(pasteboard.changeCount)")

        postCommandC()

        let didChange = await waitForPasteboardChange(
            pasteboard,
            originalChangeCount: emptyChangeCount
        )
        let capturedText = didChange ? pasteboard.string(forType: .string) : nil
        let capturedLength = capturedText?.count ?? 0
        let pasteboardTypes = pasteboard.pasteboardItems?
            .flatMap(\.types)
            .map(\.rawValue)
            .joined(separator: ",") ?? "none"

        logger.notice("capture pasteboard result source=\(source.rawValue, privacy: .public) didChange=\(didChange) changeCount=\(pasteboard.changeCount) textLength=\(capturedLength) types=\(pasteboardTypes, privacy: .public)")
        snapshot.restore(to: pasteboard)

        guard let capturedText,
              !capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("capture failed source=\(source.rawValue, privacy: .public) reason=noSelectedText didChange=\(didChange) textLength=\(capturedLength) frontmost=\(self.frontmostDescription(), privacy: .public)")
            throw CaptureError.noSelectedText
        }
        logger.notice("capture success source=\(source.rawValue, privacy: .public) method=pasteboard textLength=\(capturedText.count)")
        return capturedText
    }

    private func waitForPasteboardChange(
        _ pasteboard: NSPasteboard,
        originalChangeCount: Int
    ) async -> Bool {
        for _ in 0..<16 {
            if pasteboard.changeCount != originalChangeCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return pasteboard.changeCount != originalChangeCount
    }

    private func waitForCaptureModifiersToClear() async -> Bool {
        let captureModifiers: NSEvent.ModifierFlags = [.control, .option]
        for _ in 0..<25 {
            if NSEvent.modifierFlags.intersection(captureModifiers).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return NSEvent.modifierFlags.intersection(captureModifiers).isEmpty
    }

    private func selectedTextViaAccessibility(from application: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success,
              let focusedElement = focusedValue else {
            logger.notice("capture accessibility focusedElement status=\(focusedStatus.rawValue) target=\(self.applicationDescription(application), privacy: .public)")
            return nil
        }

        var selectedTextValue: CFTypeRef?
        let selectedTextStatus = AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )
        guard selectedTextStatus == .success else {
            logger.notice("capture accessibility selectedText status=\(selectedTextStatus.rawValue) target=\(self.applicationDescription(application), privacy: .public)")
            return nil
        }

        guard let selectedText = selectedTextValue as? String else {
            logger.notice("capture accessibility selectedText typeMismatch target=\(self.applicationDescription(application), privacy: .public)")
            return nil
        }

        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : selectedText
    }

    private func requestAccessibilityTrustPrompt() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func applicationDescription(_ application: NSRunningApplication) -> String {
        let name = application.localizedName ?? "unknown"
        let bundleID = application.bundleIdentifier ?? "unknown"
        return "\(name) pid=\(application.processIdentifier) bundle=\(bundleID)"
    }

    private func frontmostDescription() -> String {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return "none"
        }
        return applicationDescription(application)
    }

    private func modifierDescription() -> String {
        let flags = NSEvent.modifierFlags
        var names: [String] = []
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.option) { names.append("option") }
        if flags.contains(.command) { names.append("command") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.function) { names.append("function") }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

    private func currentProcessIdentityDescription() -> String {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "nil"
        let bundlePath = bundle.bundleURL.path
        let executablePath = bundle.executableURL?.path ?? "nil"
        let processName = ProcessInfo.processInfo.processName
        return "process=\(processName) bundleID=\(bundleID) bundlePath=\(bundlePath) executablePath=\(executablePath)"
    }
}

private struct PasteboardSnapshot {
    private let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map(Item.init) ?? []
    }

    var itemCount: Int {
        items.count
    }

    var typeDescription: String {
        let types = items
            .flatMap { item in item.dataByType.keys.map(\.rawValue) }
            .sorted()
        return types.isEmpty ? "none" : types.joined(separator: ",")
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let pasteboardItems = items.map { item in
            let pasteboardItem = NSPasteboardItem()
            item.dataByType.forEach { type, data in
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    private struct Item {
        let dataByType: [NSPasteboard.PasteboardType: Data]

        init(pasteboardItem: NSPasteboardItem) {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            pasteboardItem.types.forEach { type in
                if let data = pasteboardItem.data(forType: type) {
                    dataByType[type] = data
                }
            }
            self.dataByType = dataByType
        }
    }
}

private func postCommandC() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
