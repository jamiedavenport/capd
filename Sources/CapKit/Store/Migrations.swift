import Foundation
import GRDB

enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("001", migrate: createCaptures)
        return migrator
    }

    private static func createCaptures(_ db: Database) throws {
        try db.create(table: Schema.captures) { t in
            t.autoIncrementedPrimaryKey(Capture.CodingKeys.id.rawValue)

            t.column(Capture.CodingKeys.kind.rawValue, .text).notNull()
                .check { CaptureKind.allCases.map(\.rawValue).contains($0) }

            t.column(Capture.CodingKeys.url.rawValue, .text)
            t.column(Capture.CodingKeys.host.rawValue, .text)
            t.column(Capture.CodingKeys.title.rawValue, .text)
            t.column(Capture.CodingKeys.note.rawValue, .text)
            t.column(Capture.CodingKeys.selection.rawValue, .text)
            t.column(Capture.CodingKeys.body.rawValue, .text)
            t.column(Capture.CodingKeys.ocrText.rawValue, .text)
            t.column(Capture.CodingKeys.assetPath.rawValue, .text)
            t.column(Capture.CodingKeys.sourceAppBundleID.rawValue, .text)

            t.column(Capture.CodingKeys.enrichmentState.rawValue, .text).notNull()
                .defaults(to: EnrichmentState.pending.rawValue)
                .check { EnrichmentState.allCases.map(\.rawValue).contains($0) }

            t.column(Capture.CodingKeys.bodyStatus.rawValue, .text).notNull()
                .defaults(to: BodyStatus.none.rawValue)
                .check { BodyStatus.allCases.map(\.rawValue).contains($0) }

            // Nullable on purpose: SQLite passes a CHECK whose expression is NULL.
            t.column(Capture.CodingKeys.bodySource.rawValue, .text)
                .check { BodySource.allCases.map(\.rawValue).contains($0) }

            t.column(Capture.CodingKeys.attemptCount.rawValue, .integer).notNull().defaults(to: 0)
            t.column(Capture.CodingKeys.lastAttemptAt.rawValue, .datetime)

            t.column(Capture.CodingKeys.contentHash.rawValue, .text)
            t.column(Capture.CodingKeys.createdAt.rawValue, .datetime).notNull()
            t.column(Capture.CodingKeys.updatedAt.rawValue, .datetime).notNull()
            t.column(Capture.CodingKeys.lastSeenAt.rawValue, .datetime).notNull()
            t.column(Capture.CodingKeys.seenCount.rawValue, .integer).notNull().defaults(to: 1)
        }

        try db.create(virtualTable: Schema.capturesFTS, using: FTS5()) { t in
            t.synchronize(withTable: Schema.captures)
            // remove_diacritics=2 rather than SQLite's legacy default, which only folds
            // accents across part of the Latin range. The mode is compiled into the table,
            // so getting it wrong costs a full re-index of every capture.
            t.tokenizer = .porter(wrapping: .unicode61(diacritics: .remove))
            for entry in Schema.ranking {
                t.column(entry.column)
            }
        }

        // Partial because SQLite treats every NULL as distinct, and captures with no hash
        // are legitimate.
        try db.create(
            index: "captures_on_content_hash",
            on: Schema.captures,
            columns: [Capture.CodingKeys.contentHash.rawValue],
            options: .unique,
            condition: Capture.CodingKeys.contentHash != nil
        )

        try db.create(
            index: "captures_on_enrichment_state",
            on: Schema.captures,
            columns: [
                Capture.CodingKeys.enrichmentState.rawValue,
                Capture.CodingKeys.lastAttemptAt.rawValue,
            ]
        )

        try db.create(
            index: "captures_on_created_at",
            on: Schema.captures,
            columns: [Capture.CodingKeys.createdAt.rawValue]
        )

        try db.create(
            index: "captures_on_host",
            on: Schema.captures,
            columns: [Capture.CodingKeys.host.rawValue]
        )

        // Substring search can't seek an index but can scan one, which keeps the fallback off
        // the table, where every row drags a full page body along with it.
        try db.create(
            index: "captures_on_url",
            on: Schema.captures,
            columns: [Capture.CodingKeys.url.rawValue]
        )

        try db.create(
            index: "captures_on_title",
            on: Schema.captures,
            columns: [Capture.CodingKeys.title.rawValue]
        )
    }
}
