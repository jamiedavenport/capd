import Foundation

/// Names and ranking constants shared by everything that reads the database.
///
/// Search, capture, and the enrichment agent all build SQL against these, so a column rename
/// is a single edit rather than a hunt through string literals.
public enum Schema {
    public static let captures = "captures"
    public static let capturesFTS = "captures_fts"

    /// The full-text columns and their bm25 weights, in declaration order.
    ///
    /// Order matters twice over: it is the order the FTS5 table declares its columns, and the
    /// order `bm25()` reads its weight arguments. Keeping both from one list stops them
    /// drifting apart into silently wrong ranking.
    ///
    /// `url` is deliberately absent. A porter tokenizer splits URLs into useless fragments, so
    /// URL matching goes through the indexed `LIKE` fallback instead, and `host` carries the
    /// part of a URL worth ranking.
    public static let ranking: [(column: String, weight: Double)] = [
        (Capture.CodingKeys.title.rawValue, 4.0),
        (Capture.CodingKeys.host.rawValue, 3.0),
        (Capture.CodingKeys.note.rawValue, 2.0),
        (Capture.CodingKeys.selection.rawValue, 2.0),
        (Capture.CodingKeys.body.rawValue, 1.0),
        (Capture.CodingKeys.ocrText.rawValue, 1.0),
    ]

    /// `bm25(captures_fts, 4.0, 3.0, ...)` — lower is a better match, so order ascending.
    public static var bm25SQL: String {
        let weights = ranking.map { String(format: "%.1f", $0.weight) }.joined(separator: ", ")
        return "bm25(\(capturesFTS), \(weights))"
    }
}
