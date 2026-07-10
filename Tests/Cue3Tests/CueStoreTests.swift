import Foundation
import SwiftData
import XCTest
@testable import Cue3

@MainActor
final class CueStoreTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    func testCreateCueRequiresQuoteAndCreatesCurrentCueWithFirstItem() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)

        XCTAssertThrowsError(try store.createCue(quoteText: "  \n", annotationText: nil)) { error in
            XCTAssertEqual(error as? CueStore.StoreError, .emptyQuote)
        }
        XCTAssertTrue(store.cues.isEmpty)

        let cue = try store.createCue(quoteText: "第一段引用", annotationText: "第一条批注")

        XCTAssertEqual(store.currentCueID, cue.id)
        XCTAssertEqual(store.currentCue?.id, cue.id)
        XCTAssertTrue(store.historyCues.isEmpty)
        XCTAssertEqual(cue.status, .current)
        XCTAssertEqual(store.orderedItems(for: cue).count, 1)
        XCTAssertEqual(store.orderedItems(for: cue)[0].quoteText, "第一段引用")
        XCTAssertEqual(store.orderedItems(for: cue)[0].annotationText, "第一条批注")
    }

    func testStartNewCueCreatesEmptyCurrentContext() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)

        let cue = try store.startNewCue()

        XCTAssertEqual(store.currentCueID, cue.id)
        XCTAssertEqual(store.currentCue?.id, cue.id)
        XCTAssertEqual(store.displayTitle(for: cue), "未命名 Cue")
        XCTAssertTrue(store.orderedItems(for: cue).isEmpty)
        XCTAssertTrue(store.historyCues.isEmpty)
    }

    func testEnsureCurrentCueCreatesMissingCurrentAndReusesExisting() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)

        let cue = try store.ensureCurrentCue()

        XCTAssertEqual(store.currentCueID, cue.id)
        XCTAssertEqual(store.currentCue?.id, cue.id)
        XCTAssertEqual(store.cues.map(\.id), [cue.id])
        XCTAssertTrue(store.orderedItems(for: cue).isEmpty)

        clock.advance(by: 10)
        let existing = try store.ensureCurrentCue()

        XCTAssertEqual(existing.id, cue.id)
        XCTAssertEqual(store.cues.map(\.id), [cue.id])
        XCTAssertEqual(cue.createdAt, date("2026-06-20T08:00:00Z"))
    }

    func testStartingNewCueArchivesPopulatedCurrentAndDropsEmptyCurrent() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let empty = try store.startNewCue()
        clock.advance(by: 10)
        let replacement = try store.startNewCue()

        XCTAssertFalse(store.cues.contains { $0.id == empty.id })
        XCTAssertEqual(store.currentCueID, replacement.id)
        XCTAssertTrue(store.historyCues.isEmpty)

        _ = try store.appendItem(quoteText: "已经捕获的上下文", annotationText: nil)
        clock.advance(by: 10)
        let next = try store.startNewCue()

        XCTAssertEqual(store.currentCueID, next.id)
        XCTAssertEqual(store.historyCues.map(\.id), [replacement.id])
    }

    func testAppendCreatesCurrentWhenNeededAndPreservesItemOrder() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)

        _ = try store.appendItem(quoteText: "一", annotationText: nil)
        let cue = try XCTUnwrap(store.currentCue)
        clock.advance(by: 10)
        let second = try store.appendItem(quoteText: "二", annotationText: "批注")
        XCTAssertEqual(cue.updatedAt, clock.value)
        clock.advance(by: 10)
        let third = try store.appendItem(quoteText: "三", annotationText: nil)
        XCTAssertEqual(cue.updatedAt, clock.value)

        XCTAssertEqual(store.orderedItems(for: cue).map(\.quoteText), ["一", "二", "三"])
        XCTAssertEqual(second.annotationText, "批注")
        XCTAssertNil(third.annotationText)

        clock.advance(by: 10)
        try store.updateAnnotation(itemID: second.id, annotationText: "修改后")
        XCTAssertEqual(second.annotationText, "修改后")
        XCTAssertEqual(cue.updatedAt, clock.value)
        XCTAssertEqual(cue.lastTouchedAt, clock.value)

        clock.advance(by: 10)
        try store.updateAnnotation(itemID: second.id, annotationText: "  ")
        XCTAssertNil(second.annotationText)
        XCTAssertEqual(cue.updatedAt, clock.value)
    }

    func testUpdateTitleOverridesDisplayTitleAndCanClearToAutomaticTitle() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let cue = try store.createCue(quoteText: "自动标题来源", annotationText: nil)

        clock.advance(by: 10)
        try store.updateTitle(cueID: cue.id, titleText: "  手动标题  ")

        XCTAssertEqual(cue.titleText, "手动标题")
        XCTAssertEqual(store.displayTitle(for: cue), "手动标题")
        XCTAssertEqual(cue.lastTouchedAt, clock.value)

        clock.advance(by: 10)
        try store.updateTitle(cueID: cue.id, titleText: "  ")

        XCTAssertNil(cue.titleText)
        XCTAssertEqual(store.displayTitle(for: cue), "未命名 Cue")
        XCTAssertEqual(cue.lastTouchedAt, clock.value)
    }

    func testUntitledTitlesIncrementWhenExistingUntitledCueExists() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let first = try store.createCue(quoteText: "第一段引用", annotationText: nil)

        clock.advance(by: 10)
        let second = try store.startNewCue()

        XCTAssertEqual(store.displayTitle(for: first), "未命名 Cue")
        XCTAssertEqual(store.displayTitle(for: second), "未命名 Cue 2")
    }

    func testCreatingNewCueArchivesPreviousCurrentAndKeepsOnlyOneCurrent() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        var created: [CueRecord] = []

        for index in 1...4 {
            created.append(try store.createCue(quoteText: "Cue \(index)", annotationText: nil))
            clock.advance(by: 10)
        }

        XCTAssertEqual(store.currentCueID, created[3].id)
        XCTAssertEqual(store.currentCue.map { store.orderedItems(for: $0)[0].quoteText }, "Cue 4")
        XCTAssertEqual(store.cues.filter { $0.status == .current }.map(\.id), [created[3].id])
        XCTAssertEqual(store.historyCues.map { store.orderedItems(for: $0)[0].quoteText }, ["Cue 3", "Cue 2", "Cue 1"])
    }

    func testClosingEmptyCurrentDropsItInsteadOfAddingHistory() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let cue = try store.startNewCue()

        try store.closeCurrent(cueID: cue.id)

        XCTAssertNil(store.currentCueID)
        XCTAssertTrue(store.cues.isEmpty)
        XCTAssertTrue(store.historyCues.isEmpty)
    }

    func testRestoringHistoryCueArchivesPreviousCurrent() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let first = try store.createCue(quoteText: "一", annotationText: nil)
        clock.advance(by: 10)
        let second = try store.createCue(quoteText: "二", annotationText: nil)

        clock.advance(by: 10)
        try store.restoreCurrent(cueID: first.id)

        XCTAssertEqual(store.currentCueID, first.id)
        XCTAssertEqual(first.status, .current)
        XCTAssertEqual(second.status, .history)
        XCTAssertEqual(store.historyCues.map(\.id), [second.id])
    }

    func testRestoringHistoryCueRefreshesRecentOrderByUpdatedTime() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let first = try store.createCue(quoteText: "Cue 1", annotationText: nil)
        clock.advance(by: 10)
        let second = try store.createCue(quoteText: "Cue 2", annotationText: nil)
        clock.advance(by: 10)
        let third = try store.createCue(quoteText: "Cue 3", annotationText: nil)
        clock.advance(by: 10)
        let fourth = try store.createCue(quoteText: "Cue 4", annotationText: nil)

        XCTAssertEqual(store.recentCues.map(\.id), [fourth.id, third.id, second.id])

        clock.advance(by: 10)
        try store.restoreCurrent(cueID: first.id)

        XCTAssertEqual(store.recentCues.map(\.id), [first.id, fourth.id, third.id])
        XCTAssertEqual(first.updatedAt, clock.value)
    }

    func testDeleteRemovesCueItemsAndClearsCurrentWhenNeeded() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, container) = try makeStore(clock: clock)
        let first = try store.createCue(quoteText: "一", annotationText: nil)
        clock.advance(by: 10)
        let second = try store.createCue(quoteText: "二", annotationText: nil)
        let deletedItemID = store.orderedItems(for: second)[0].id

        try store.delete(cueID: second.id)

        XCTAssertNil(store.currentCueID)
        XCTAssertTrue(store.historyCues.contains { $0.id == first.id })
        XCTAssertFalse(store.cues.contains { $0.id == second.id })
        let items = try container.mainContext.fetch(FetchDescriptor<CueItemRecord>())
        XCTAssertFalse(items.contains { $0.id == deletedItemID })
    }

    func testDeleteItemCanBeRestoredForUndo() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let cue = try store.createCue(quoteText: "一", annotationText: nil)
        let second = try store.appendItem(quoteText: "二", annotationText: "批注")

        let snapshot = try store.deleteItem(itemID: second.id)

        XCTAssertEqual(store.orderedItems(for: cue).map(\.quoteText), ["一"])

        try store.restoreItem(snapshot)

        XCTAssertEqual(store.orderedItems(for: cue).map(\.quoteText), ["一", "二"])
        XCTAssertEqual(store.orderedItems(for: cue)[1].annotationText, "批注")
    }

    func testOutputTextKeepsOrderAndOmitsEmptyAnnotations() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let cue = try store.createCue(quoteText: "第一段引用", annotationText: "第一条批注")
        clock.advance(by: 10)
        try store.appendItem(quoteText: "第二段引用", annotationText: nil)

        clock.advance(by: 10)
        let output = try store.outputText(cueID: cue.id)

        XCTAssertEqual(
            output,
            """
            第一段引用
            批注：第一条批注

            第二段引用
            """
        )
        XCTAssertEqual(cue.lastTouchedAt, clock.value)
    }

    func testCueOutputPrependsPrompt() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let cue = try store.createCue(quoteText: "第一段引用", annotationText: "第一条批注")

        let output = try store.cueOutputText(cueID: cue.id)

        XCTAssertEqual(
            output,
            """
            下面的内容是我标记的重点内容，以及我自己的批注：

            第一段引用
            批注：第一条批注
            """
        )
    }

    func testCueOutputUsesInjectedPromptProvider() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let configuration = ModelConfiguration(
            "Cue3PromptTests",
            schema: Cue3Schema.schema,
            isStoredInMemoryOnly: true
        )
        let container = try Cue3Schema.makeContainer(configurations: [configuration])
        retainedContainers.append(container)
        let store = CueStore(
            context: container.mainContext,
            now: clock.callAsFunction,
            cuePromptProvider: { "这是自定义 Cue 提示词：" }
        )
        let cue = try store.createCue(quoteText: "第一段引用", annotationText: nil)

        let output = try store.cueOutputText(cueID: cue.id)

        XCTAssertEqual(
            output,
            """
            这是自定义 Cue 提示词：

            第一段引用
            """
        )
    }

    func testCueOutputReplacesCuePlaceholderInsideTemplate() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let configuration = ModelConfiguration(
            "Cue3TemplatePromptTests",
            schema: Cue3Schema.schema,
            isStoredInMemoryOnly: true
        )
        let container = try Cue3Schema.makeContainer(configurations: [configuration])
        retainedContainers.append(container)
        let store = CueStore(
            context: container.mainContext,
            now: clock.callAsFunction,
            cuePromptProvider: {
                "请整理如下内容：\n\n\(AppSettings.cuePlaceholder)\n\n谢谢"
            }
        )
        let cue = try store.createCue(quoteText: "第一段引用", annotationText: nil)

        let output = try store.cueOutputText(cueID: cue.id)

        XCTAssertEqual(
            output,
            """
            请整理如下内容：

            第一段引用

            谢谢
            """
        )
    }

    func testOutputEmptyCueFails() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let cue = try store.startNewCue()

        XCTAssertThrowsError(try store.outputText(cueID: cue.id)) { error in
            XCTAssertEqual(error as? CueStore.StoreError, .emptyCue)
        }
    }

    func testCleanupDeletesExpiredCuesAndCreatesReplacementWhenEmpty() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let (store, _) = try makeStore(clock: clock)
        let expired = try store.createCue(quoteText: "将过期历史", annotationText: nil)
        clock.value = date("2026-06-20T09:00:00Z")
        let current = try store.createCue(quoteText: "当前保留", annotationText: nil)

        clock.value = date("2026-06-21T08:59:00Z")
        XCTAssertEqual(try store.cleanupExpiredCues(), 0)
        XCTAssertTrue(store.historyCues.contains { $0.id == expired.id })
        XCTAssertEqual(store.currentCueID, current.id)

        clock.value = date("2026-06-21T09:00:01Z")
        XCTAssertEqual(try store.cleanupExpiredCues(), 2)
        let replacement = try XCTUnwrap(store.currentCue)
        XCTAssertNotEqual(replacement.id, current.id)
        XCTAssertEqual(store.cues.map(\.id), [replacement.id])
        XCTAssertTrue(store.orderedItems(for: replacement).isEmpty)
        XCTAssertFalse(store.cues.contains { $0.id == expired.id })
        XCTAssertFalse(store.cues.contains { $0.id == current.id })
        XCTAssertEqual(try store.cleanupExpiredCues(), 0)
    }

    func testDiskContainerRestoresCueItemsAndCurrentCue() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cue3Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cue3.store")
        let currentID: UUID

        do {
            let container = try makeDiskContainer(url: storeURL)
            let clock = TestClock(date("2026-06-20T08:00:00Z"))
            let store = CueStore(context: container.mainContext, now: clock.callAsFunction)
            let cue = try store.createCue(quoteText: "持久化引用", annotationText: "持久化批注")
            currentID = cue.id
        }

        let reopenedContainer = try makeDiskContainer(url: storeURL)
        let reopened = CueStore(context: reopenedContainer.mainContext)

        XCTAssertEqual(reopened.currentCueID, currentID)
        XCTAssertEqual(reopened.currentCue.map { reopened.orderedItems(for: $0)[0].quoteText }, "持久化引用")
        XCTAssertEqual(reopened.currentCue.map { reopened.orderedItems(for: $0)[0].annotationText }, "持久化批注")
    }

    func testRepairingMultipleCurrentCuesIsPersisted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cue3RepairTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cue3.store")
        let firstID = UUID()

        do {
            let container = try makeDiskContainer(url: storeURL)
            let context = container.mainContext
            let timestamp = date("2026-06-20T08:00:00Z")
            context.insert(CueRecord(
                id: firstID,
                status: .current,
                createdAt: timestamp,
                updatedAt: timestamp,
                lastTouchedAt: timestamp
            ))
            context.insert(CueRecord(
                status: .current,
                createdAt: timestamp.addingTimeInterval(10),
                updatedAt: timestamp.addingTimeInterval(10),
                lastTouchedAt: timestamp.addingTimeInterval(10)
            ))
            context.insert(AppStateRecord(currentCueID: firstID))
            try context.save()
        }

        do {
            let container = try makeDiskContainer(url: storeURL)
            let repaired = CueStore(context: container.mainContext)
            XCTAssertEqual(repaired.currentCueID, firstID)
            XCTAssertEqual(repaired.cues.filter { $0.status == .current }.count, 1)
        }

        let reopenedContainer = try makeDiskContainer(url: storeURL)
        let persistedCues = try reopenedContainer.mainContext.fetch(FetchDescriptor<CueRecord>())
        XCTAssertEqual(persistedCues.filter { $0.status == .current }.map(\.id), [firstID])
    }

    func testRepairRemovesDuplicateMainStateRecords() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let configuration = ModelConfiguration(
            "Cue3DuplicateStateTests",
            schema: Cue3Schema.schema,
            isStoredInMemoryOnly: true
        )
        let container = try Cue3Schema.makeContainer(configurations: [configuration])
        retainedContainers.append(container)
        let context = container.mainContext
        let cue = CueRecord(
            status: .current,
            createdAt: clock.value,
            updatedAt: clock.value,
            lastTouchedAt: clock.value
        )
        context.insert(cue)
        context.insert(AppStateRecord(currentCueID: nil))
        context.insert(AppStateRecord(currentCueID: cue.id))
        try context.save()

        let store = CueStore(context: context, now: clock.callAsFunction)
        let mainStates = try context.fetch(FetchDescriptor<AppStateRecord>())
            .filter { $0.key == "main" }

        XCTAssertEqual(mainStates.count, 1)
        XCTAssertEqual(mainStates[0].currentCueID, store.currentCueID)
        XCTAssertEqual(store.currentCueID, cue.id)
    }

    func testRepairDeletesOrphanedItems() throws {
        let clock = TestClock(date("2026-06-20T08:00:00Z"))
        let configuration = ModelConfiguration(
            "Cue3OrphanRepairTests",
            schema: Cue3Schema.schema,
            isStoredInMemoryOnly: true
        )
        let container = try Cue3Schema.makeContainer(configurations: [configuration])
        retainedContainers.append(container)
        let context = container.mainContext
        context.insert(CueItemRecord(
            cueID: UUID(),
            quoteText: "孤儿引用",
            position: 0,
            createdAt: clock.value,
            updatedAt: clock.value
        ))
        try context.save()

        let store = CueStore(context: context, now: clock.callAsFunction)
        let persistedItems = try context.fetch(FetchDescriptor<CueItemRecord>())

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(persistedItems.isEmpty)
    }

    func testVersionedSchemaOpensExistingUnversionedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cue3LegacySchemaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cue3.store")
        let cueID = UUID()

        do {
            let legacySchema = Schema([
                CueRecord.self,
                CueItemRecord.self,
                AppStateRecord.self
            ])
            let configuration = ModelConfiguration(
                "Cue3LegacySchemaTests",
                schema: legacySchema,
                url: storeURL
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [configuration]
            )
            let timestamp = date("2026-06-20T08:00:00Z")
            legacyContainer.mainContext.insert(CueRecord(
                id: cueID,
                status: .current,
                createdAt: timestamp,
                updatedAt: timestamp,
                lastTouchedAt: timestamp
            ))
            legacyContainer.mainContext.insert(AppStateRecord(currentCueID: cueID))
            try legacyContainer.mainContext.save()
        }

        let migratedContainer = try makeDiskContainer(url: storeURL)
        let migratedStore = CueStore(context: migratedContainer.mainContext)

        XCTAssertEqual(migratedStore.currentCueID, cueID)
        XCTAssertEqual(migratedStore.currentCue?.id, cueID)
        XCTAssertEqual(migratedContainer.schema.version, Cue3SchemaV1.versionIdentifier)
    }

    func testCueOutputFormatterIsIndependentFromPersistence() {
        let formatter = CueOutputFormatter()
        let output = formatter.format(items: [
            .init(quoteText: "第一段", annotationText: "批注"),
            .init(quoteText: "第二段", annotationText: nil)
        ])

        XCTAssertEqual(output, "第一段\n批注：批注\n\n第二段")
        XCTAssertEqual(
            formatter.applyTemplate("整理：\n{{Cue}}", placeholder: "{{Cue}}", to: output),
            "整理：\n第一段\n批注：批注\n\n第二段"
        )
    }

    private func makeStore(clock: TestClock) throws -> (CueStore, ModelContainer) {
        let configuration = ModelConfiguration(
            "Cue3Tests",
            schema: Cue3Schema.schema,
            isStoredInMemoryOnly: true
        )
        let container = try Cue3Schema.makeContainer(configurations: [configuration])
        retainedContainers.append(container)
        return (
            CueStore(
                context: container.mainContext,
                now: clock.callAsFunction
            ),
            container
        )
    }

    private func makeDiskContainer(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Cue3PersistenceTests",
            schema: Cue3Schema.schema,
            url: url
        )
        return try Cue3Schema.makeContainer(configurations: [configuration])
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private final class TestClock {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func advance(by interval: TimeInterval) {
        value = value.addingTimeInterval(interval)
    }

    func callAsFunction() -> Date {
        value
    }
}
