import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyController {
    private enum ActionID: UInt32 {
        case capture = 1
        case open = 2
        case newCue = 3
        case cue = 4
    }

    private struct HotKey {
        let id: ActionID
        let shortcut: ShortcutConfiguration?
        let handler: () -> Void
    }

    private var hotKeys: [HotKey] = []
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private let signature = fourCharCode("Cue3")

    init(
        captureShortcut: ShortcutConfiguration?,
        openShortcut: ShortcutConfiguration?,
        newCueShortcut: ShortcutConfiguration?,
        cueShortcut: ShortcutConfiguration?,
        captureHandler: @escaping () -> Void,
        openHandler: @escaping () -> Void,
        newCueHandler: @escaping () -> Void,
        cueHandler: @escaping () -> Void
    ) {
        hotKeys = [
            HotKey(
                id: .capture,
                shortcut: captureShortcut,
                handler: captureHandler
            ),
            HotKey(
                id: .open,
                shortcut: openShortcut,
                handler: openHandler
            ),
            HotKey(
                id: .newCue,
                shortcut: newCueShortcut,
                handler: newCueHandler
            ),
            HotKey(
                id: .cue,
                shortcut: cueShortcut,
                handler: cueHandler
            )
        ]
        install()
    }

    deinit {
        for hotKeyRef in hotKeyRefs.compactMap({ $0 }) {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func updateShortcuts(
        capture: ShortcutConfiguration?,
        open: ShortcutConfiguration?,
        newCue: ShortcutConfiguration?,
        cue: ShortcutConfiguration?
    ) {
        guard hotKeys.count == 4 else {
            return
        }

        hotKeys = [
            HotKey(id: .capture, shortcut: capture, handler: hotKeys[0].handler),
            HotKey(id: .open, shortcut: open, handler: hotKeys[1].handler),
            HotKey(id: .newCue, shortcut: newCue, handler: hotKeys[2].handler),
            HotKey(id: .cue, shortcut: cue, handler: hotKeys[3].handler)
        ]
        unregisterHotKeys()
        install()
    }

    private func install() {
        installEventHandlerIfNeeded()

        for hotKey in hotKeys {
            guard let shortcut = hotKey.shortcut else {
                continue
            }
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: hotKey.id.rawValue)
            let status = RegisterEventHotKey(
                shortcut.carbonKeyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                hotKeyRefs.append(hotKeyRef)
            }
        }
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs.compactMap({ $0 }) {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard status == noErr else {
                    return noErr
                }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                guard let actionID = ActionID(rawValue: receivedID.id),
                      let hotKey = controller.hotKeys.first(where: { $0.id == actionID }) else {
                    return noErr
                }

                DispatchQueue.main.async {
                    hotKey.handler()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, byte in
        (result << 8) + OSType(byte)
    }
}
