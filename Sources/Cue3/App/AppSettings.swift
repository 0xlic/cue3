import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case automatic
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic:
                return "自动"
            case .light:
                return "浅色"
            case .dark:
                return "深色"
            }
        }

        var appearance: NSAppearance? {
            switch self {
            case .automatic:
                return nil
            case .light:
                return NSAppearance(named: .aqua)
            case .dark:
                return NSAppearance(named: .darkAqua)
            }
        }
    }

    enum MenuAction: String, CaseIterable, Identifiable {
        case open
        case newCue
        case capture
        case cue

        var id: String { rawValue }

        var title: String {
            switch self {
            case .open:
                return "打开"
            case .newCue:
                return "新建"
            case .capture:
                return "捕获"
            case .cue:
                return "Cue"
            }
        }

        var storageKey: String {
            "settings.shortcut.\(rawValue)"
        }

        var disabledStorageKey: String {
            "settings.shortcut.\(rawValue).disabled"
        }

        var defaultShortcut: ShortcutConfiguration {
            switch self {
            case .open:
                return .init(key: .o, modifiers: .controlOption)
            case .newCue:
                return .init(key: .n, modifiers: .controlOption)
            case .capture:
                return .init(key: .c, modifiers: .controlOption)
            case .cue:
                return .init(key: .v, modifiers: .controlOption)
            }
        }
    }

    nonisolated static let cuePlaceholder = CueOutputFormatter.cuePlaceholder
    nonisolated static let defaultCleanupDescription = "24 小时（默认）"
    nonisolated static let defaultCuePrompt = CueOutputFormatter.defaultPrompt

    private static func normalizedCuePrompt(_ prompt: String?) -> String {
        guard let prompt,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultCuePrompt
        }
        return prompt
    }


    private enum StorageKey {
        static let appearanceMode = "settings.appearanceMode"
        static let cuePrompt = "settings.cuePrompt"
        static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
        static let openMainWindowOnLaunch = "settings.openMainWindowOnLaunch"
        static let panelIsPinned = "settings.panel.isPinned"
        static let didCompleteInitialLaunch = "settings.didCompleteInitialLaunch"
    }

    var appearanceMode: AppearanceMode {
        didSet {
            userDefaults.set(appearanceMode.rawValue, forKey: StorageKey.appearanceMode)
            onAppearanceModeChanged?(appearanceMode)
        }
    }

    var cuePrompt: String {
        didSet {
            userDefaults.set(cuePrompt, forKey: StorageKey.cuePrompt)
        }
    }

    var launchAtLoginEnabled: Bool {
        didSet {
            userDefaults.set(launchAtLoginEnabled, forKey: StorageKey.launchAtLoginEnabled)
            if !isReconcilingLaunchAtLogin {
                onLaunchAtLoginChanged?(launchAtLoginEnabled)
            }
        }
    }

    var openMainWindowOnLaunch: Bool {
        didSet {
            userDefaults.set(openMainWindowOnLaunch, forKey: StorageKey.openMainWindowOnLaunch)
        }
    }

    var panelIsPinned: Bool {
        didSet {
            userDefaults.set(panelIsPinned, forKey: StorageKey.panelIsPinned)
        }
    }

    var openShortcut: ShortcutConfiguration? {
        didSet {
            shortcutDidChange(for: .open, oldValue: oldValue)
        }
    }

    var newCueShortcut: ShortcutConfiguration? {
        didSet {
            shortcutDidChange(for: .newCue, oldValue: oldValue)
        }
    }

    var captureShortcut: ShortcutConfiguration? {
        didSet {
            shortcutDidChange(for: .capture, oldValue: oldValue)
        }
    }

    var cueShortcut: ShortcutConfiguration? {
        didSet {
            shortcutDidChange(for: .cue, oldValue: oldValue)
        }
    }

    private(set) var systemErrorMessage: String?

    var onShortcutsChanged: (() -> Void)?
    var onAppearanceModeChanged: ((AppearanceMode) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?

    private(set) var didCompleteInitialLaunch: Bool

    private let userDefaults: UserDefaults
    private var isApplyingShortcutChange = false
    private var isReconcilingLaunchAtLogin = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedCuePrompt = userDefaults.string(forKey: StorageKey.cuePrompt)
        let initialCuePrompt = Self.normalizedCuePrompt(storedCuePrompt)
        appearanceMode = AppearanceMode(
            rawValue: userDefaults.string(forKey: StorageKey.appearanceMode) ?? ""
        ) ?? .automatic
        cuePrompt = initialCuePrompt
        launchAtLoginEnabled = userDefaults.object(forKey: StorageKey.launchAtLoginEnabled) as? Bool ?? false
        openMainWindowOnLaunch = userDefaults.object(forKey: StorageKey.openMainWindowOnLaunch) as? Bool ?? false
        panelIsPinned = userDefaults.object(forKey: StorageKey.panelIsPinned) as? Bool ?? true
        didCompleteInitialLaunch = userDefaults.object(forKey: StorageKey.didCompleteInitialLaunch) as? Bool ?? false
        openShortcut = Self.loadShortcut(from: userDefaults, for: .open)
        newCueShortcut = Self.loadShortcut(from: userDefaults, for: .newCue)
        captureShortcut = Self.loadShortcut(from: userDefaults, for: .capture)
        cueShortcut = Self.loadShortcut(from: userDefaults, for: .cue)

        if storedCuePrompt != initialCuePrompt {
            userDefaults.set(initialCuePrompt, forKey: StorageKey.cuePrompt)
        }
        sanitizeLoadedShortcuts()
    }

    var resolvedCuePromptTemplate: String {
        let trimmed = cuePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultCuePrompt : trimmed
    }

    var shouldShowMainPanelOnLaunch: Bool {
        openMainWindowOnLaunch || !didCompleteInitialLaunch
    }

    func markInitialLaunchCompleted() {
        guard !didCompleteInitialLaunch else {
            return
        }
        didCompleteInitialLaunch = true
        userDefaults.set(true, forKey: StorageKey.didCompleteInitialLaunch)
    }

    func shortcut(for action: MenuAction) -> ShortcutConfiguration? {
        switch action {
        case .open:
            return openShortcut
        case .newCue:
            return newCueShortcut
        case .capture:
            return captureShortcut
        case .cue:
            return cueShortcut
        }
    }

    func setShortcut(_ shortcut: ShortcutConfiguration?, for action: MenuAction) {
        switch action {
        case .open:
            openShortcut = shortcut
        case .newCue:
            newCueShortcut = shortcut
        case .capture:
            captureShortcut = shortcut
        case .cue:
            cueShortcut = shortcut
        }
    }

    func resetShortcut(for action: MenuAction) {
        setShortcut(action.defaultShortcut, for: action)
    }

    func resetCuePrompt() {
        cuePrompt = Self.defaultCuePrompt
    }

    func reconcileLaunchAtLogin(enabled: Bool, errorMessage: String? = nil) {
        isReconcilingLaunchAtLogin = true
        launchAtLoginEnabled = enabled
        isReconcilingLaunchAtLogin = false
        if let errorMessage {
            presentSystemError(errorMessage)
        }
    }

    func presentSystemError(_ message: String) {
        systemErrorMessage = message
    }

    func clearSystemError() {
        systemErrorMessage = nil
    }

    var duplicateShortcutWarning: String? {
        let actions = MenuAction.allCases
        let assignedActions = actions.compactMap { action in
            shortcut(for: action).map { (action, $0) }
        }
        let groups = Dictionary(grouping: assignedActions, by: { $0.1.storageSignature })
        let duplicates = groups.values
            .filter { $0.count > 1 }
            .map { group in
                group.map { $0.0.title }.sorted().joined(separator: "、")
            }
            .sorted()

        guard !duplicates.isEmpty else {
            return nil
        }

        return "以下动作使用了相同快捷键：\(duplicates.joined(separator: "；"))。"
    }

    private func persistShortcut(_ shortcut: ShortcutConfiguration?, for action: MenuAction) {
        guard let shortcut else {
            userDefaults.set(true, forKey: action.disabledStorageKey)
            userDefaults.removeObject(forKey: action.storageKey)
            return
        }

        userDefaults.set(false, forKey: action.disabledStorageKey)
        if let data = try? JSONEncoder().encode(shortcut) {
            userDefaults.set(data, forKey: action.storageKey)
        }
    }

    private func notifyShortcutChange() {
        onShortcutsChanged?()
    }

    private func shortcutDidChange(
        for action: MenuAction,
        oldValue: ShortcutConfiguration?
    ) {
        guard !isApplyingShortcutChange else { return }

        if let validationMessage = shortcutValidationMessage(
            shortcut(for: action),
            for: action
        ) {
            isApplyingShortcutChange = true
            assignShortcut(oldValue, for: action)
            isApplyingShortcutChange = false
            presentSystemError(validationMessage)
            return
        }

        persistShortcut(shortcut(for: action), for: action)
        notifyShortcutChange()
    }

    private func shortcutValidationMessage(
        _ shortcut: ShortcutConfiguration?,
        for action: MenuAction
    ) -> String? {
        guard let shortcut else { return nil }
        guard shortcut.modifiers.hasGlobalHotKeyModifier else {
            return "“\(action.title)”快捷键至少需要包含 Command、Control 或 Option 中的一个修饰键。"
        }

        if let conflictingAction = MenuAction.allCases.first(where: { candidate in
            candidate != action && self.shortcut(for: candidate) == shortcut
        }) {
            return "“\(action.title)”与“\(conflictingAction.title)”不能使用相同的全局快捷键。"
        }
        return nil
    }

    private func sanitizeLoadedShortcuts() {
        var usedShortcuts = Set<ShortcutConfiguration>()
        isApplyingShortcutChange = true
        defer { isApplyingShortcutChange = false }

        for action in MenuAction.allCases {
            let loaded = shortcut(for: action)
            let resolved: ShortcutConfiguration?
            if let loaded,
               loaded.modifiers.hasGlobalHotKeyModifier,
               !usedShortcuts.contains(loaded) {
                resolved = loaded
                usedShortcuts.insert(loaded)
            } else if loaded == nil {
                resolved = nil
            } else {
                let defaultShortcut = action.defaultShortcut
                resolved = usedShortcuts.contains(defaultShortcut) ? nil : defaultShortcut
                if let resolved {
                    usedShortcuts.insert(resolved)
                }
            }

            assignShortcut(resolved, for: action)
            persistShortcut(resolved, for: action)
        }
    }

    private func assignShortcut(
        _ shortcut: ShortcutConfiguration?,
        for action: MenuAction
    ) {
        switch action {
        case .open:
            openShortcut = shortcut
        case .newCue:
            newCueShortcut = shortcut
        case .capture:
            captureShortcut = shortcut
        case .cue:
            cueShortcut = shortcut
        }
    }

    private static func loadShortcut(
        from userDefaults: UserDefaults,
        for action: MenuAction
    ) -> ShortcutConfiguration? {
        if userDefaults.bool(forKey: action.disabledStorageKey) {
            return nil
        }

        guard let data = userDefaults.data(forKey: action.storageKey),
              let shortcut = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data) else {
            return action.defaultShortcut
        }
        return shortcut
    }
}

struct ShortcutConfiguration: Codable, Equatable, Hashable {
    var key: ShortcutKey
    var modifiers: ShortcutModifiers

    var keyEquivalent: KeyEquivalent {
        key.keyEquivalent
    }

    var eventModifiers: SwiftUI.EventModifiers {
        modifiers.eventModifiers
    }

    var carbonModifiers: UInt32 {
        modifiers.carbonModifiers
    }

    var carbonKeyCode: UInt32 {
        key.carbonKeyCode
    }

    var displayString: String {
        "\(modifiers.displayString)\(key.displayTitle)"
    }

    var storageSignature: String {
        "\(key.rawValue)|\(modifiers.storageSignature)"
    }
}

extension ShortcutConfiguration {
    init?(event: NSEvent) {
        guard let key = ShortcutKey(keyCode: event.keyCode) else {
            return nil
        }
        self.init(
            key: key,
            modifiers: ShortcutModifiers(eventModifiers: event.modifierFlags)
        )
    }
}

struct ShortcutModifiers: Codable, Equatable, Hashable {
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false

    static let controlOption = ShortcutModifiers(command: false, option: true, control: true, shift: false)

    init(
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) {
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    init(eventModifiers: NSEvent.ModifierFlags) {
        command = eventModifiers.contains(.command)
        option = eventModifiers.contains(.option)
        control = eventModifiers.contains(.control)
        shift = eventModifiers.contains(.shift)
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if command {
            modifiers.insert(.command)
        }
        if option {
            modifiers.insert(.option)
        }
        if control {
            modifiers.insert(.control)
        }
        if shift {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if command {
            modifiers |= UInt32(cmdKey)
        }
        if option {
            modifiers |= UInt32(optionKey)
        }
        if control {
            modifiers |= UInt32(controlKey)
        }
        if shift {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    var displayString: String {
        var parts: [String] = []
        if control {
            parts.append("⌃")
        }
        if option {
            parts.append("⌥")
        }
        if shift {
            parts.append("⇧")
        }
        if command {
            parts.append("⌘")
        }
        return parts.joined()
    }

    var storageSignature: String {
        [command, option, control, shift]
            .map { $0 ? "1" : "0" }
            .joined()
    }

    var hasGlobalHotKeyModifier: Bool {
        command || option || control
    }
}

enum ShortcutKey: String, CaseIterable, Codable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"

    var id: String { rawValue }

    var displayTitle: String {
        rawValue.uppercased()
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(rawValue))
    }

    var carbonKeyCode: UInt32 {
        switch self {
        case .a: return UInt32(kVK_ANSI_A)
        case .b: return UInt32(kVK_ANSI_B)
        case .c: return UInt32(kVK_ANSI_C)
        case .d: return UInt32(kVK_ANSI_D)
        case .e: return UInt32(kVK_ANSI_E)
        case .f: return UInt32(kVK_ANSI_F)
        case .g: return UInt32(kVK_ANSI_G)
        case .h: return UInt32(kVK_ANSI_H)
        case .i: return UInt32(kVK_ANSI_I)
        case .j: return UInt32(kVK_ANSI_J)
        case .k: return UInt32(kVK_ANSI_K)
        case .l: return UInt32(kVK_ANSI_L)
        case .m: return UInt32(kVK_ANSI_M)
        case .n: return UInt32(kVK_ANSI_N)
        case .o: return UInt32(kVK_ANSI_O)
        case .p: return UInt32(kVK_ANSI_P)
        case .q: return UInt32(kVK_ANSI_Q)
        case .r: return UInt32(kVK_ANSI_R)
        case .s: return UInt32(kVK_ANSI_S)
        case .t: return UInt32(kVK_ANSI_T)
        case .u: return UInt32(kVK_ANSI_U)
        case .v: return UInt32(kVK_ANSI_V)
        case .w: return UInt32(kVK_ANSI_W)
        case .x: return UInt32(kVK_ANSI_X)
        case .y: return UInt32(kVK_ANSI_Y)
        case .z: return UInt32(kVK_ANSI_Z)
        case .zero: return UInt32(kVK_ANSI_0)
        case .one: return UInt32(kVK_ANSI_1)
        case .two: return UInt32(kVK_ANSI_2)
        case .three: return UInt32(kVK_ANSI_3)
        case .four: return UInt32(kVK_ANSI_4)
        case .five: return UInt32(kVK_ANSI_5)
        case .six: return UInt32(kVK_ANSI_6)
        case .seven: return UInt32(kVK_ANSI_7)
        case .eight: return UInt32(kVK_ANSI_8)
        case .nine: return UInt32(kVK_ANSI_9)
        }
    }

    init?(keyCode: UInt16) {
        switch Int(keyCode) {
        case kVK_ANSI_A: self = .a
        case kVK_ANSI_B: self = .b
        case kVK_ANSI_C: self = .c
        case kVK_ANSI_D: self = .d
        case kVK_ANSI_E: self = .e
        case kVK_ANSI_F: self = .f
        case kVK_ANSI_G: self = .g
        case kVK_ANSI_H: self = .h
        case kVK_ANSI_I: self = .i
        case kVK_ANSI_J: self = .j
        case kVK_ANSI_K: self = .k
        case kVK_ANSI_L: self = .l
        case kVK_ANSI_M: self = .m
        case kVK_ANSI_N: self = .n
        case kVK_ANSI_O: self = .o
        case kVK_ANSI_P: self = .p
        case kVK_ANSI_Q: self = .q
        case kVK_ANSI_R: self = .r
        case kVK_ANSI_S: self = .s
        case kVK_ANSI_T: self = .t
        case kVK_ANSI_U: self = .u
        case kVK_ANSI_V: self = .v
        case kVK_ANSI_W: self = .w
        case kVK_ANSI_X: self = .x
        case kVK_ANSI_Y: self = .y
        case kVK_ANSI_Z: self = .z
        case kVK_ANSI_0: self = .zero
        case kVK_ANSI_1: self = .one
        case kVK_ANSI_2: self = .two
        case kVK_ANSI_3: self = .three
        case kVK_ANSI_4: self = .four
        case kVK_ANSI_5: self = .five
        case kVK_ANSI_6: self = .six
        case kVK_ANSI_7: self = .seven
        case kVK_ANSI_8: self = .eight
        case kVK_ANSI_9: self = .nine
        default:
            return nil
        }
    }
}
