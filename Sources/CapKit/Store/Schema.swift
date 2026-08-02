import Foundation

public enum Schema {
    public static let captures = "captures"
    public static let capturesFTS = "captures_fts"

    /// One list because the order is shared: FTS5 declares its columns in it, and `bm25()`
    /// reads its weight arguments in it. `url` is absent because a porter tokenizer shreds
    /// URLs; URL matching goes through the indexed `LIKE` fallback instead.
    public static let ranking: [(column: String, weight: Double)] = [
        (Capture.CodingKeys.title.rawValue, 4.0),
        (Capture.CodingKeys.host.rawValue, 3.0),
        (Capture.CodingKeys.note.rawValue, 2.0),
        (Capture.CodingKeys.selection.rawValue, 2.0),
        (Capture.CodingKeys.body.rawValue, 1.0),
        (Capture.CodingKeys.ocrText.rawValue, 1.0),
    ]

    /// Lower is a better match, so callers order ascending.
    public static var bm25SQL: String {
        let weights = ranking.map { String(format: "%.1f", $0.weight) }.joined(separator: ", ")
        return "bm25(\(capturesFTS), \(weights))"
    }
}
