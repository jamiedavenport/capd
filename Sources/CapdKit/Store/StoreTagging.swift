import Foundation
import GRDB

/// How one tag is being used across the library: the input to consolidation and the
/// order the search window cycles tags in.
public struct TagUsage: Sendable, Equatable {
    public let tag: String
    public let count: Int
    public let sampleTitles: [String]

    public init(tag: String, count: Int, sampleTitles: [String]) {
        self.tag = tag
        self.count = count
        self.sampleTitles = sampleTitles
    }
}

extension Store {
    public func taxonomy() throws -> Taxonomy {
        try reader.read { db in try Self.fetchTaxonomy(db) }
    }

    /// Only `capd-agent` calls this; the app's writes go through ``setTaggingEnabled(_:now:)``
    /// so two processes never race on the tag list itself.
    func saveTaxonomy(_ taxonomy: Taxonomy) throws {
        try dbPool.write { db in
            try Self.persistTaxonomy(taxonomy, in: db)
        }
    }

    public func setTaggingEnabled(_ enabled: Bool, now: Date = Date()) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE \(Schema.taxonomy)
                    SET tagging_enabled = :enabled, updated_at = :now
                    WHERE id = 1
                    """,
                arguments: ["enabled": enabled, "now": now])
        }
    }

    /// Captures the tagging pass still owes tags, oldest first. Rows mid-enrichment are
    /// skipped so tagging sees the page body once there is one.
    func untaggedCaptures(limit: Int) throws -> [Capture] {
        try reader.read { db in
            try Capture.fetchAll(
                db,
                sql: """
                    SELECT * FROM \(Schema.captures)
                    WHERE tags_version = 0 AND enrichment_state IN (:ok, :thin, :failed)
                    ORDER BY id
                    LIMIT :limit
                    """,
                arguments: [
                    "ok": EnrichmentState.ok.rawValue,
                    "thin": EnrichmentState.thin.rawValue,
                    "failed": EnrichmentState.failed.rawValue,
                    "limit": limit,
                ])
        }
    }

    /// One transaction for one tagging outcome: the capture's tags and the taxonomy the
    /// caller may have grown or advanced while assigning them.
    func completeTagging(
        id: Int64,
        tags: [String],
        taxonomy: Taxonomy,
        now: Date = Date()
    ) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE \(Schema.captures)
                    SET tags = :tags, tags_version = :version, updated_at = :now
                    WHERE id = :id
                    """,
                arguments: [
                    "tags": tags.isEmpty ? nil : tags.joined(separator: " "),
                    "version": taxonomy.version,
                    "now": now,
                    "id": id,
                ])
            try Self.persistTaxonomy(taxonomy, in: db)
        }
    }

    /// Per-tag capture counts, most used first, each with a few recent titles for the
    /// consolidation prompt.
    ///
    /// Consolidation passes `includePinned: false`: pinned tags are outside the taxonomy,
    /// and counting them would trip the over-cap trigger on every pass after a large import.
    public func tagUsage(sampleLimit: Int = 5, includePinned: Bool = true) throws -> [TagUsage] {
        let rows = try reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT tags, title FROM \(Schema.captures)
                    WHERE tags IS NOT NULL AND tags != ''
                    \(includePinned ? "" : "AND tags_version != \(Capture.pinnedTagsVersion)")
                    ORDER BY created_at DESC
                    """)
        }

        var counts: [String: Int] = [:]
        var samples: [String: [String]] = [:]
        var order: [String] = []
        for row in rows {
            let joined: String = row["tags"]
            let title: String? = row["title"]
            for tag in joined.split(separator: " ").map(String.init) {
                if counts[tag] == nil { order.append(tag) }
                counts[tag, default: 0] += 1
                if let title, !title.isEmpty, samples[tag, default: []].count < sampleLimit {
                    samples[tag, default: []].append(title)
                }
            }
        }

        return
            order
            .map { TagUsage(tag: $0, count: counts[$0] ?? 0, sampleTitles: samples[$0] ?? []) }
            .sorted { ($0.count, $1.tag) > ($1.count, $0.tag) }
    }

    /// Rewrites every tagged capture under a revised taxonomy, in batches so no single
    /// write transaction blocks the other processes for long.
    ///
    /// `mapping` sends each old tag to its surviving name; unmapped tags are dropped. A
    /// capture left with no tags — including one that had none applicable under the old
    /// taxonomy — resets to `tags_version = 0`, so the incremental pass re-tags it
    /// against the new vocabulary. Rows with pinned tags are not the taxonomy's to
    /// rewrite and are skipped.
    func applyTaxonomyRevision(
        mapping: [String: String],
        taxonomy: Taxonomy,
        batchSize: Int = 200,
        now: Date = Date()
    ) throws {
        var lastID: Int64 = 0
        while true {
            let rows = try reader.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, tags FROM \(Schema.captures)
                        WHERE id > :last
                            AND tags_version != \(Capture.pinnedTagsVersion)
                            AND (tags IS NOT NULL OR tags_version > 0)
                        ORDER BY id
                        LIMIT :limit
                        """,
                    arguments: ["last": lastID, "limit": batchSize])
            }
            guard !rows.isEmpty else { break }

            try dbPool.write { db in
                for row in rows {
                    let id: Int64 = row["id"]
                    let joined: String? = row["tags"]
                    var mapped: [String] = []
                    for tag in (joined ?? "").split(separator: " ") {
                        guard let survivor = mapping[String(tag)] else { continue }
                        if !mapped.contains(survivor) { mapped.append(survivor) }
                    }
                    try db.execute(
                        sql: """
                            UPDATE \(Schema.captures)
                            SET tags = :tags, tags_version = :version, updated_at = :now
                            WHERE id = :id
                            """,
                        arguments: [
                            "tags": mapped.isEmpty ? nil : mapped.joined(separator: " "),
                            "version": mapped.isEmpty ? 0 : taxonomy.version,
                            "now": now,
                            "id": id,
                        ])
                }
            }
            lastID = rows.last!["id"]
        }
        try saveTaxonomy(taxonomy)
    }

    static func fetchTaxonomy(_ db: Database) throws -> Taxonomy {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT * FROM \(Schema.taxonomy) WHERE id = 1")
        else {
            // Migration "002" seeds the row; reaching here means the file predates it,
            // and a default keeps readers working until a writer lays it down.
            return Taxonomy(updatedAt: .distantPast)
        }
        let joined: String = row["tags"]
        return Taxonomy(
            version: row["version"],
            tags: joined.split(separator: " ").map(String.init),
            taggedSinceConsolidation: row["tagged_since_consolidation"],
            taggingEnabled: row["tagging_enabled"],
            updatedAt: row["updated_at"])
    }

    static func persistTaxonomy(_ taxonomy: Taxonomy, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO \(Schema.taxonomy)
                    (id, version, tags, tagged_since_consolidation, tagging_enabled, updated_at)
                VALUES (1, :version, :tags, :tagged, :enabled, :now)
                """,
            arguments: [
                "version": taxonomy.version,
                "tags": taxonomy.tags.joined(separator: " "),
                "tagged": taxonomy.taggedSinceConsolidation,
                "enabled": taxonomy.taggingEnabled,
                "now": taxonomy.updatedAt,
            ])
    }
}
