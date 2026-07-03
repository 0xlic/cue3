import XCTest
@testable import Cue3

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchCurrentShortcutsAndPrompt() {
        let defaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: defaults)

        XCTAssertEqual(settings.appearanceMode, .automatic)
        XCTAssertEqual(settings.openShortcut, AppSettings.MenuAction.open.defaultShortcut)
        XCTAssertEqual(settings.newCueShortcut, AppSettings.MenuAction.newCue.defaultShortcut)
        XCTAssertEqual(settings.captureShortcut, AppSettings.MenuAction.capture.defaultShortcut)
        XCTAssertEqual(settings.cueShortcut, AppSettings.MenuAction.cue.defaultShortcut)
        XCTAssertEqual(settings.resolvedCuePromptTemplate, AppSettings.defaultCuePrompt)
        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertFalse(settings.openMainWindowOnLaunch)
        XCTAssertTrue(settings.panelIsPinned)
    }

    func testResolvedCuePromptFallsBackToDefaultWhenBlank() {
        let defaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: defaults)

        settings.cuePrompt = "   \n"

        XCTAssertEqual(settings.resolvedCuePromptTemplate, AppSettings.defaultCuePrompt)
    }

    func testShortcutAndPromptPersistAcrossReload() {
        let defaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: defaults)
        let customShortcut = ShortcutConfiguration(
            key: .k,
            modifiers: ShortcutModifiers(command: true, option: false, control: true, shift: true)
        )

        settings.openShortcut = customShortcut
        settings.cueShortcut = AppSettings.MenuAction.cue.defaultShortcut
        settings.cuePrompt = "这是新的提示词"

        let reloaded = AppSettings(userDefaults: defaults)

        XCTAssertEqual(reloaded.openShortcut, customShortcut)
        XCTAssertEqual(reloaded.cueShortcut, AppSettings.MenuAction.cue.defaultShortcut)
        XCTAssertEqual(reloaded.resolvedCuePromptTemplate, "这是新的提示词")
    }

    func testGeneralSettingsPersistAcrossReload() {
        let defaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: defaults)

        settings.appearanceMode = .dark
        settings.launchAtLoginEnabled = true
        settings.openMainWindowOnLaunch = true

        let reloaded = AppSettings(userDefaults: defaults)

        XCTAssertEqual(reloaded.appearanceMode, .dark)
        XCTAssertTrue(reloaded.launchAtLoginEnabled)
        XCTAssertTrue(reloaded.openMainWindowOnLaunch)
    }

    func testPanelPinnedStatePersistsAcrossReload() {
        let defaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: defaults)

        settings.panelIsPinned = false

        let reloaded = AppSettings(userDefaults: defaults)

        XCTAssertFalse(reloaded.panelIsPinned)
    }

    func testDeletedShortcutPersistsAsNil() {
        let defaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: defaults)

        settings.captureShortcut = nil

        let reloaded = AppSettings(userDefaults: defaults)

        XCTAssertNil(reloaded.captureShortcut)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "Cue3Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
