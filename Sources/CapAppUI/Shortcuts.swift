import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // ⌃⌥Space is reserved by macOS for input-source switching.
    package static let search = Self(
        "search", initial: .init(.space, modifiers: [.option, .shift]))

    package static let capture = Self(
        "capture", initial: .init(.c, modifiers: [.control, .option]))

    package static let annotate = Self(
        "annotate", initial: .init(.n, modifiers: [.control, .option]))
}
