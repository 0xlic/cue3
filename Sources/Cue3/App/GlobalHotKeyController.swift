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
        let action: AppSettings.MenuAction
        let shortcut: ShortcutConfiguration?
        let handler: () -> Void
    }

    private var hotKeys: [HotKey] = []
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private let signature = fourCharCode("Cue3")
    private(set) var registrationErrorMessage: String?

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
                action: .capture,
                shortcut: captureShortcut,
                handler: captureHandler
            ),
            HotKey(
                id: .open,
                action: .open,
                shortcut: openShortcut,
                handler: openHandler
            ),
            HotKey(
                id: .newCue,
                action: .newCue,
                shortcut: newCueShortcut,
                handler: newCueHandler
            ),
            HotKey(
                id: .cue,
                action: .cue,
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
            HotKey(id: .capture, action: .capture, shortcut: capture, handler: hotKeys[0].handler),
            HotKey(id: .open, action: .open, shortcut: open, handler: hotKeys[1].handler),
            HotKey(id: .newCue, action: .newCue, shortcut: newCue, handler: hotKeys[2].handler),
            HotKey(id: .cue, action: .cue, shortcut: cue, handler: hotKeys[3].handler)
        ]
        unregisterHotKeys()
        install()
    }

    private func install() {
        var failures: [String] = []
        let handlerStatus = installEventHandlerIfNeeded()
        guard handlerStatus == noErr else {
            registrationErrorMessage = "无法安装全局快捷键事件处理器：\(statusDescription(handlerStatus))"
            return
        }

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
            } else {
                failures.append("\(hotKey.action.title)（\(hotKey.shortcut?.displayString ?? "未设置")）：\(statusDescription(status))")
            }
        }
        registrationErrorMessage = failures.isEmpty
            ? nil
            : "以下全局快捷键未能注册：\(failures.joined(separator: "；"))"
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs.compactMap({ $0 }) {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        return InstallEventHandler(
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
                guard receivedID.signature == controller.signature,
                      let actionID = ActionID(rawValue: receivedID.id),
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

    private func statusDescription(_ status: OSStatus) -> String {
        let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        return "\(error.localizedDescription)（\(status)）"
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, byte in
        (result << 8) + OSType(byte)
    }
}
