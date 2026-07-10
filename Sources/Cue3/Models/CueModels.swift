import Foundation
import SwiftData

enum CueStatus: String, Codable {
    case current
    case history

    init(storedValue: String) {
        switch storedValue {
        case Self.current.rawValue, "active":
            self = .current
        case Self.history.rawValue, "inactive":
            self = .history
        default:
            self = .history
        }
    }
}

enum Cue3SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        CueRecord.self,
        CueItemRecord.self,
        AppStateRecord.self
    ]

    @Model
    final class CueRecord {
        var id: UUID
        var statusRaw: String
        var createdAt: Date
        var updatedAt: Date
        var lastTouchedAt: Date
        var deactivatedAt: Date?
        var titleText: String?

        init(
            id: UUID = UUID(),
            status: CueStatus = .current,
            createdAt: Date,
            updatedAt: Date,
            lastTouchedAt: Date,
            deactivatedAt: Date? = nil,
            titleText: String? = nil
        ) {
            self.id = id
            statusRaw = status.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lastTouchedAt = lastTouchedAt
            self.deactivatedAt = deactivatedAt
            self.titleText = titleText
        }

        var status: CueStatus {
            get { CueStatus(storedValue: statusRaw) }
            set { statusRaw = newValue.rawValue }
        }
    }

    @Model
    final class CueItemRecord {
        var id: UUID
        var cueID: UUID
        private(set) var quoteText: String
        var annotationText: String?
        var position: Int
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            cueID: UUID,
            quoteText: String,
            annotationText: String? = nil,
            position: Int,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.cueID = cueID
            self.quoteText = quoteText
            self.annotationText = annotationText
            self.position = position
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class AppStateRecord {
        var key: String
        var currentCueID: UUID?

        init(key: String = "main", currentCueID: UUID? = nil) {
            self.key = key
            self.currentCueID = currentCueID
        }
    }
}

typealias CueRecord = Cue3SchemaV1.CueRecord
typealias CueItemRecord = Cue3SchemaV1.CueItemRecord
typealias AppStateRecord = Cue3SchemaV1.AppStateRecord

enum Cue3MigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [Cue3SchemaV1.self]
    static let stages: [MigrationStage] = []
}

enum Cue3Schema {
    static let schema = Schema(versionedSchema: Cue3SchemaV1.self)

    static func makeContainer(
        configurations: [ModelConfiguration]
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: Cue3MigrationPlan.self,
            configurations: configurations
        )
    }
}
