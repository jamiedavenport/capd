import ApplicationServices

/// Reads the selected text out of an app's focused element over Accessibility.
///
/// Best-effort: a missing grant, an app with no AX support, or an empty selection all
/// come back nil, and the caller falls through to the pasteboard.
struct SelectionReader {
    func selectedText(inAppWithProcessIdentifier pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
            let text = value as? String
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
