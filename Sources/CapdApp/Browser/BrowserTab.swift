/// A browser's frontmost tab, as reported by the browser itself.
struct BrowserTab: Equatable, Sendable {
    var url: String
    var title: String?
}
