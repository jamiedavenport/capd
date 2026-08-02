/// Decides which field a piece of loose text rides in — `url` or `text` — before ingest.
public enum LinkDetection {
    /// "://" rather than a full parse: ingest owns URL validity; this only decides which
    /// field the input rides in, and a scheme-less string is a note, not a broken link.
    /// Whitespace disqualifies, or prose that merely mentions a link would ride as one.
    public static func looksLikeURL(_ candidate: String) -> Bool {
        candidate.contains("://") && !candidate.contains(where: \.isWhitespace)
    }
}
