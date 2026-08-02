import ApplicationServices

/// Reads the frontmost tab out of a Gecko browser over Accessibility: Gecko has no
/// Apple Events tab dictionary, but the content document is an `AXWebArea` carrying
/// the page URL in `AXURL`.
///
/// Best-effort like the other AX readers — a missing grant or a window with no web
/// area comes back nil. Gecko builds its accessibility tree lazily on the first
/// query, so a failed attempt gets one short-delay retry before giving up.
enum GeckoTabReader {
    @MainActor
    static func read(processIdentifier pid: pid_t) async -> BrowserTab? {
        if let tab = attempt(pid) { return tab }
        try? await Task.sleep(for: .milliseconds(150))
        return attempt(pid)
    }

    private static func attempt(_ pid: pid_t) -> BrowserTab? {
        let app = AXUIElementCreateApplication(pid)
        guard
            let window = element(of: app, kAXFocusedWindowAttribute)
                ?? element(of: app, kAXMainWindowAttribute),
            let webArea = largestWebArea(under: window),
            let url = string(of: webArea, kAXURLAttribute), !url.isEmpty
        else { return nil }
        let title = string(of: webArea, kAXTitleAttribute)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserTab(url: url, title: title?.isEmpty == false ? title : nil)
    }

    /// Bounds the walk so a pathological window cannot stall the hotkey path.
    private static let nodeBudget = 512

    /// Zen can show several documents at once — sidebar web panels, split view — and
    /// the one the user means is the biggest on screen, not the first in tree order.
    private static func largestWebArea(under root: AXUIElement) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var best: (element: AXUIElement, area: CGFloat)?
        while index < queue.count, index < nodeBudget {
            let node = queue[index]
            index += 1
            if role(of: node) == "AXWebArea" {
                // Not descended into: anything nested is an iframe, never the page.
                let nodeArea = area(of: node)
                if best == nil || nodeArea > best!.area {
                    best = (node, nodeArea)
                }
                continue
            }
            queue.append(contentsOf: children(of: node))
        }
        return best?.element
    }

    private static func element(of parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of node: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &value)
                == .success
        else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func role(of node: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func string(of node: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(node, attribute as CFString, &value) == .success,
            let value
        else { return nil }
        if let url = value as? URL {
            return url.absoluteString
        }
        return value as? String
    }

    private static func area(of node: AXUIElement) -> CGFloat {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(node, kAXSizeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return 0 }
        var size = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &size) else { return 0 }
        return size.width * size.height
    }
}
