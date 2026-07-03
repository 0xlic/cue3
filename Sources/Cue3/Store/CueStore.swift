import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CueStore {
    struct DeletedItemSnapshot: Equatable {
        let cueID: UUID
        let itemID: UUID
        let quoteText: String
        let annotationText: String?
        let position: Int
        let createdAt: Date
        let updatedAt: Date
    }

    enum StoreError: LocalizedError, Equatable {
        case emptyQuote
        case emptyCue
        case cueNotFound
        case itemNotFound

        var errorDescription: String? {
            switch self {
            case .emptyQuote:
                return "引用文本不能为空。"
            case .emptyCue:
                return "当前 Cue 还没有可输出的引用。"
            case .cueNotFound:
                return "找不到该 Cue。"
            case .itemNotFound:
                return "找不到该条目。"
            }
        }
    }

    private let context: ModelContext
    private let now: () -> Date
    private let cuePromptProvider: () -> String

    private(set) var cues: [CueRecord] = []
    private(set) var items: [CueItemRecord] = []
    private(set) var currentCueID: UUID?
    var errorMessage: String?

    init(
        context: ModelContext,
        now: @escaping () -> Date = Date.init,
        cuePromptProvider: @escaping () -> String = { AppSettings.defaultCuePrompt }
    ) {
        self.context = context
        self.now = now
        self.cuePromptProvider = cuePromptProvider

        do {
            try reload(repairingCurrent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var currentCue: CueRecord? {
        guard let currentCueID else { return nil }
        return cues.first { $0.id == currentCueID && $0.status == .current }
    }

    var historyCues: [CueRecord] {
        sortedRecent(cues.filter { $0.status == .history })
    }

    var recentCues: [CueRecord] {
        Array(sortedRecent(cues).prefix(3))
    }

    func items(for cue: CueRecord) -> [CueItemRecord] {
        items.filter { $0.cueID == cue.id }
    }

    func orderedItems(for cue: CueRecord) -> [CueItemRecord] {
        items(for: cue).sorted {
            if $0.position != $1.position {
                return $0.position < $1.position
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func itemCount(for cue: CueRecord) -> Int {
        items(for: cue).count
    }

    func displayTitle(for cue: CueRecord) -> String {
        truncatedTitle(titleSource(for: cue))
    }

    func titleDraft(for cue: CueRecord) -> String {
        titleSource(for: cue)
    }

    func updateTitle(cueID: UUID, titleText: String?) throws {
        guard let cue = cues.first(where: { $0.id == cueID }) else {
            throw StoreError.cueNotFound
        }
        let timestamp = now()
        cue.titleText = normalizedTitle(titleText)
        touch(cue, at: timestamp)
        try persist()
    }

    private func titleSource(for cue: CueRecord) -> String {
        if let titleText = normalizedTitle(cue.titleText) {
            return titleText
        }
        return untitledTitle(for: cue)
    }

    private func truncatedTitle(_ source: String) -> String {
        let maxLength = 28
        if source.count <= maxLength {
            return source
        }
        return "\(source.prefix(maxLength))…"
    }

    private func untitledTitle(for cue: CueRecord) -> String {
        let untitledCues = cues
            .filter { normalizedTitle($0.titleText) == nil }
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        var usedTitles = Set(
            cues.compactMap { normalizedTitle($0.titleText) }
        )

        for untitledCue in untitledCues {
            let title = nextAvailableUntitledTitle(usedTitles: usedTitles)
            if untitledCue.id == cue.id {
                return title
            }
            usedTitles.insert(title)
        }

        return nextAvailableUntitledTitle(usedTitles: usedTitles)
    }

    private func nextAvailableUntitledTitle(usedTitles: Set<String>) -> String {
        let baseTitle = "未命名 Cue"
        if !usedTitles.contains(baseTitle) {
            return baseTitle
        }

        var index = 2
        while usedTitles.contains("\(baseTitle) \(index)") {
            index += 1
        }
        return "\(baseTitle) \(index)"
    }

    @discardableResult
    func startNewCue() throws -> CueRecord {
        let timestamp = now()
        archiveCurrentDroppingEmpty(at: timestamp)

        let cue = makeCurrentCue(at: timestamp)
        setCurrentCue(id: cue.id)
        try persist()
        return cue
    }

    @discardableResult
    func createCue(quoteText: String, annotationText: String?) throws -> CueRecord {
        try validateQuote(quoteText)
        let timestamp = now()
        archiveCurrentDroppingEmpty(at: timestamp)

        let cue = makeCurrentCue(at: timestamp)
        _ = makeItem(
            cueID: cue.id,
            quoteText: quoteText,
            annotationText: annotationText,
            position: 0,
            timestamp: timestamp
        )
        setCurrentCue(id: cue.id)
        try persist()
        return cue
    }

    @discardableResult
    func appendItem(quoteText: String, annotationText: String?) throws -> CueItemRecord {
        try validateQuote(quoteText)
        guard let cue = currentCue else {
            let timestamp = now()
            let cue = makeCurrentCue(at: timestamp)
            let item = makeItem(
                cueID: cue.id,
                quoteText: quoteText,
                annotationText: annotationText,
                position: 0,
                timestamp: timestamp
            )
            setCurrentCue(id: cue.id)
            try persist()
            return item
        }

        let timestamp = now()
        let item = makeItem(
            cueID: cue.id,
            quoteText: quoteText,
            annotationText: annotationText,
            position: nextItemPosition(for: cue),
            timestamp: timestamp
        )
        touch(cue, at: timestamp)
        try persist()
        return item
    }

    func updateAnnotation(itemID: UUID, annotationText: String?) throws {
        guard let item = items.first(where: { $0.id == itemID }),
              let cue = cue(containing: itemID) else {
            throw StoreError.itemNotFound
        }
        let timestamp = now()
        item.annotationText = normalizedAnnotation(annotationText)
        item.updatedAt = timestamp
        touch(cue, at: timestamp)
        try persist()
    }

    @discardableResult
    func deleteItem(itemID: UUID) throws -> DeletedItemSnapshot {
        guard let item = items.first(where: { $0.id == itemID }),
              let cue = cue(containing: itemID) else {
            throw StoreError.itemNotFound
        }

        let snapshot = DeletedItemSnapshot(
            cueID: cue.id,
            itemID: item.id,
            quoteText: item.quoteText,
            annotationText: item.annotationText,
            position: item.position,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
        items.removeAll { $0.id == itemID }
        context.delete(item)
        touch(cue, at: now())
        try persist()
        return snapshot
    }

    func restoreItem(_ snapshot: DeletedItemSnapshot) throws {
        guard let cue = cues.first(where: { $0.id == snapshot.cueID }) else {
            throw StoreError.cueNotFound
        }
        let item = CueItemRecord(
            id: snapshot.itemID,
            cueID: cue.id,
            quoteText: snapshot.quoteText,
            annotationText: snapshot.annotationText,
            position: snapshot.position,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        context.insert(item)
        items.append(item)
        touch(cue, at: now())
        try persist()
    }

    func restoreCurrent(cueID: UUID) throws {
        guard let cue = cues.first(where: { $0.id == cueID }) else {
            throw StoreError.cueNotFound
        }
        guard cue.id != currentCueID else { return }

        let timestamp = now()
        archiveCurrent(at: timestamp)
        cue.status = .current
        cue.deactivatedAt = nil
        touch(cue, at: timestamp)
        stateRecord().currentCueID = cue.id
        try persist()
    }

    func closeCurrent(cueID: UUID) throws {
        guard let cue = cues.first(where: { $0.id == cueID }) else {
            throw StoreError.cueNotFound
        }
        guard cue.status == .current else { return }

        if itemCount(for: cue) == 0 {
            context.delete(cue)
            cues.removeAll { $0.id == cueID }
        } else {
            archive(cue, at: now())
        }
        if currentCueID == cueID {
            stateRecord().currentCueID = nil
        }
        try persist()
    }

    func outputText(cueID: UUID) throws -> String {
        guard let cue = cues.first(where: { $0.id == cueID }) else {
            throw StoreError.cueNotFound
        }
        guard itemCount(for: cue) > 0 else {
            throw StoreError.emptyCue
        }
        touch(cue, at: now())
        try persist()
        return formattedOutput(for: cue)
    }

    func cueOutputText(cueID: UUID) throws -> String {
        let output = try outputText(cueID: cueID)
        let template = cuePromptProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTemplate = template.isEmpty ? AppSettings.defaultCuePrompt : template
        if resolvedTemplate.contains(AppSettings.cuePlaceholder) {
            return resolvedTemplate.replacingOccurrences(
                of: AppSettings.cuePlaceholder,
                with: output
            )
        }

        return """
        \(resolvedTemplate)

        \(output)
        """
    }

    func delete(cueID: UUID) throws {
        guard let cue = cues.first(where: { $0.id == cueID }) else {
            throw StoreError.cueNotFound
        }
        let deletingCurrentCue = currentCueID == cueID
        items(for: cue).forEach(context.delete)
        items.removeAll { $0.cueID == cue.id }
        context.delete(cue)
        if deletingCurrentCue {
            stateRecord().currentCueID = nil
        }
        try persist()
    }

    @discardableResult
    func cleanupHistoryCues(at date: Date? = nil) throws -> Int {
        let timestamp = date ?? now()
        let cutoff = timestamp.addingTimeInterval(-Self.historyLifetime)
        let expired = cues.filter { cue in
            guard cue.status == .history else { return false }
            return cue.updatedAt < cutoff
        }
        expired.forEach { cue in
            items(for: cue).forEach(context.delete)
            items.removeAll { $0.cueID == cue.id }
            context.delete(cue)
        }
        if !expired.isEmpty {
            try persist()
        }
        return expired.count
    }

    func refresh() {
        do {
            try reload(repairingCurrent: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validateQuote(_ quoteText: String) throws {
        if quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StoreError.emptyQuote
        }
    }

    private func normalizedAnnotation(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private func normalizedTitle(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func makeCurrentCue(at timestamp: Date) -> CueRecord {
        let cue = CueRecord(
            status: .current,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastTouchedAt: timestamp
        )
        context.insert(cue)
        cues.append(cue)
        return cue
    }

    private func makeItem(
        cueID: UUID,
        quoteText: String,
        annotationText: String?,
        position: Int,
        timestamp: Date
    ) -> CueItemRecord {
        let item = CueItemRecord(
            cueID: cueID,
            quoteText: quoteText,
            annotationText: normalizedAnnotation(annotationText),
            position: position,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(item)
        items.append(item)
        return item
    }

    private func setCurrentCue(id: UUID?) {
        stateRecord().currentCueID = id
        currentCueID = id
    }

    private func nextItemPosition(for cue: CueRecord) -> Int {
        (items(for: cue).map(\.position).max() ?? -1) + 1
    }

    private func touch(_ cue: CueRecord, at timestamp: Date) {
        cue.updatedAt = timestamp
        cue.lastTouchedAt = timestamp
    }

    private func cue(containing itemID: UUID) -> CueRecord? {
        guard let item = items.first(where: { $0.id == itemID }) else {
            return nil
        }
        return cues.first { cue in
            cue.id == item.cueID
        }
    }

    private func archiveCurrent(at timestamp: Date) {
        cues
            .filter { $0.status == .current }
            .forEach { archive($0, at: timestamp) }
    }

    private func archiveCurrentDroppingEmpty(at timestamp: Date) {
        cues
            .filter { $0.status == .current }
            .forEach { cue in
                if itemCount(for: cue) == 0 {
                    context.delete(cue)
                    cues.removeAll { $0.id == cue.id }
                } else {
                    archive(cue, at: timestamp)
                }
            }
    }

    private func archive(_ cue: CueRecord, at timestamp: Date) {
        cue.status = .history
        cue.updatedAt = timestamp
        cue.deactivatedAt = timestamp
    }

    private func sortedRecent(_ records: [CueRecord]) -> [CueRecord] {
        var seen = Set<UUID>()
        return records
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                if $0.lastTouchedAt != $1.lastTouchedAt {
                    return $0.lastTouchedAt > $1.lastTouchedAt
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func formattedOutput(for cue: CueRecord) -> String {
        orderedItems(for: cue)
            .map { item in
                var lines = [item.quoteText]
                if let annotation = item.annotationText, !annotation.isEmpty {
                    lines.append("批注：\(annotation)")
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    private func stateRecord() -> AppStateRecord {
        if let existing = try? context.fetch(FetchDescriptor<AppStateRecord>()).first {
            return existing
        }
        let state = AppStateRecord()
        context.insert(state)
        return state
    }

    private func persist() throws {
        do {
            try context.save()
            try reload(repairingCurrent: false)
            errorMessage = nil
        } catch {
            context.rollback()
            try? reload(repairingCurrent: false)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func reload(repairingCurrent: Bool) throws {
        cues = try context.fetch(FetchDescriptor<CueRecord>())
        items = try context.fetch(FetchDescriptor<CueItemRecord>())
        let state = try context.fetch(FetchDescriptor<AppStateRecord>()).first
        currentCueID = state?.currentCueID

        guard repairingCurrent else { return }

        let currentCandidates = sortedRecent(cues.filter { $0.status == .current })
        let validCurrent = currentCueID.flatMap { id in
            currentCandidates.first { $0.id == id }
        }
        let repairedID = validCurrent?.id ?? currentCandidates.first?.id
        let timestamp = now()

        cues
            .filter { cue in
                guard cue.status == .current else { return false }
                guard let repairedID else { return true }
                return cue.id != repairedID
            }
            .forEach { archive($0, at: timestamp) }

        if repairedID != currentCueID {
            stateRecord().currentCueID = repairedID
            try context.save()
            currentCueID = repairedID
        }
    }

    private static let historyLifetime: TimeInterval = 24 * 60 * 60
}
